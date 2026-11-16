import '../local/local_card_models.dart';
import '../tunion/tunion_cash_log.dart';
import '../card_parser.dart';
import '../../transport/transport_failure.dart';

/// 一次识读中单个应用（TU / CU / 地方钱包等）的探测状态。
///
/// 一芯多应用卡不再用单一 [ParsedCard] 布尔标记表达组合；每个应用独立
/// 记录探测与否、选择结果、读取结果、身份、余额、流水与传输失败。
enum ApplicationProbeState {
  notProbed,
  selectRejected,
  confirmed,
  readSucceeded,
  partial,
  failed,
}

/// 单个应用在本次会话中的独立证据。
class ApplicationEvidence {
  const ApplicationEvidence({
    required this.appId,
    required this.displayName,
    this.state = ApplicationProbeState.notProbed,
    this.probed = false,
    this.confirmed = false,
    this.readSucceeded = false,
    this.cardNumber,
    this.balanceFen,
    this.recordCount = 0,
    this.records = const [],
    this.readError,
    this.transportFailure,
    this.payload,
    this.notes = const [],
  });

  /// 稳定应用标识（tu / cu / lingnan / shenzhen / macau 等）。
  final String appId;
  final String displayName;
  final ApplicationProbeState state;

  /// 是否实际发出过探测指令（区别于受门控跳过）。
  final bool probed;

  /// 应用是否已确认（选择成功，应用结构存在）。
  final bool confirmed;

  /// 是否读取成功（拿到可解析数据）；部分读取仍可配合 [readError]。
  final bool readSucceeded;

  final String? cardNumber;
  final int? balanceFen;
  final int recordCount;

  /// 该应用自身的原始流水（不含其他应用）。
  final List<ApduRecord> records;

  final Object? readError;
  final TransportFailure? transportFailure;

  /// 类型化产物（如 ParsedCard / ReadResult），按应用使用。
  final Object? payload;

  /// 补充诊断原文，仅供展示，不替代字段。
  final List<String> notes;

  /// 取识别/余额可用的展示字段；未知保持 null。
  List<ApduRecord> get trips =>
      records.where((r) => r.type == 2).toList(growable: false);

  factory ApplicationEvidence.rejected(
    String appId,
    String displayName, {
    String? reason,
  }) => ApplicationEvidence(
    appId: appId,
    displayName: displayName,
    state: ApplicationProbeState.selectRejected,
    probed: true,
    notes: reason == null ? const [] : [reason],
  );

  factory ApplicationEvidence.confirmed(String appId, String displayName) =>
      ApplicationEvidence(
        appId: appId,
        displayName: displayName,
        state: ApplicationProbeState.confirmed,
        probed: true,
        confirmed: true,
      );

  factory ApplicationEvidence.succeeded(
    String appId,
    String displayName, {
    String? cardNumber,
    int? balanceFen,
    int recordCount = 0,
    List<ApduRecord> records = const [],
    Object? readError,
    TransportFailure? transportFailure,
    Object? payload,
    List<String> notes = const [],
  }) => ApplicationEvidence(
    appId: appId,
    displayName: displayName,
    state: readError == null
        ? ApplicationProbeState.readSucceeded
        : ApplicationProbeState.partial,
    probed: true,
    confirmed: true,
    readSucceeded: readError == null,
    cardNumber: cardNumber,
    balanceFen: balanceFen,
    recordCount: recordCount,
    records: records,
    readError: readError,
    transportFailure: transportFailure,
    payload: payload,
    notes: notes,
  );

  factory ApplicationEvidence.failed(
    String appId,
    String displayName, {
    Object? readError,
    TransportFailure? transportFailure,
  }) => ApplicationEvidence(
    appId: appId,
    displayName: displayName,
    state: ApplicationProbeState.failed,
    probed: true,
    readError: readError,
    transportFailure: transportFailure,
  );

  /// 可序列化投影（快照 / 诊断 / 导出共用）；原始字节已在会话帧中保存。
  Map<String, dynamic> toJson() {
    final summary = payloadSummary();
    return {
      'appId': appId,
      'displayName': displayName,
      'state': state.name,
      'probed': probed,
      'confirmed': confirmed,
      'readSucceeded': readSucceeded,
      if (cardNumber != null) 'cardNumber': cardNumber,
      if (balanceFen != null) 'balanceFen': balanceFen,
      if (recordCount != 0) 'recordCount': recordCount,
      if (notes.isNotEmpty) 'notes': notes,
      if (readError != null) 'readError': '$readError',
      'transportFailure': ?_failureJson(transportFailure),
      'payload': ?summary,
    };
  }

  static Map<String, dynamic>? _failureJson(TransportFailure? failure) {
    if (failure == null) return null;
    return {
      'kind': failure.kind.name,
      if (failure.code != null) 'code': failure.code,
      'message': failure.message,
    };
  }

  /// 类型化产物的轻量摘要；未知或不可序列化类型保留 null。
  Map<String, dynamic>? payloadSummary() => switch (payload) {
    TUnionCashLog log => log.toJson(),
    ParsedCard(
      :final parserId,
      :final parserName,
      :final selectedAidHex,
      :final info,
    ) =>
      {
        'kind': 'parsed_card',
        'parserId': parserId,
        'parserName': parserName,
        'selectedAid': selectedAidHex,
        if (info.balanceFen != null) 'balanceFen': info.balanceFen,
      },
    ReadResult(:final info) => {
      'kind': 'read_result',
      'isLocalCard': info.isLocalCard,
      if (info.cardNumber.isNotEmpty) 'cardNumber': info.cardNumber,
      if (info.observedBalance != null) 'balanceFen': info.observedBalance,
    },
    _ => null,
  };

  /// 旧快照中的银行卡条目保留原文，跳过展示投影。
  static bool isRetiredBankEntry(Object? raw) =>
      raw is Map && raw['appId'] == 'bank';

  /// 从快照 / 诊断投影恢复；损坏条目返回 null，由调用方按容错策略保留原文。
  static ApplicationEvidence? tryParse(Object? raw) {
    if (raw is! Map || isRetiredBankEntry(raw)) return null;
    final json = Map<String, dynamic>.from(raw);
    final stateName = json['state'];
    final state = stateName is String
        ? ApplicationProbeState.values.asNameMap()[stateName]
        : null;
    final failure = json['transportFailure'];
    final failureMap = failure is Map
        ? Map<String, dynamic>.from(failure)
        : null;
    final kindName = failureMap?['kind'];
    final failureKind = kindName is String
        ? TransportFailureKind.values.asNameMap()[kindName]
        : null;
    final notesRaw = json['notes'];
    return ApplicationEvidence(
      appId: json['appId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      state: state ?? ApplicationProbeState.notProbed,
      probed: json['probed'] == true,
      confirmed: json['confirmed'] == true,
      readSucceeded: json['readSucceeded'] == true,
      cardNumber: json['cardNumber']?.toString(),
      balanceFen: json['balanceFen'] is int ? json['balanceFen'] as int : null,
      recordCount: json['recordCount'] is int ? json['recordCount'] as int : 0,
      readError: json['readError']?.toString(),
      transportFailure: failureMap == null
          ? null
          : TransportFailure(
              kind: failureKind ?? TransportFailureKind.unknown,
              message: failureMap['message']?.toString() ?? '',
              code: failureMap['code']?.toString(),
            ),
      payload: json['appId'] == 'tuCash' && json['confirmed'] == true
          ? TUnionCashLog.fromPayload(json['payload'])
          : null,
      notes: [
        for (final note in notesRaw is List ? notesRaw : const [])
          if (note is String) note,
      ],
    );
  }
}
