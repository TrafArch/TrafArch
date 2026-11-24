import '../local/local_card_models.dart';
import '../local/local_hex.dart';
import '../city_union/city_union_models.dart';
import 'local_application_capture.dart';
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
    this.observations = const {},
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

  /// Original file/selector observations scoped to this selected application.
  final Map<String, String> observations;

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
    Map<String, String> observations = const {},
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
    observations: observations,
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
      if (summary == null && records.isNotEmpty)
        'records': [for (final record in records) captureLocalRecord(record)],
      if (observations.isNotEmpty) 'observations': observations,
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
    ParsedCard card => {
      'kind': 'parsed_card',
      'parserId': card.parserId,
      'parserName': card.parserName,
      'selectedAid': card.selectedAidHex,
      'balanceFen': ?card.info.balanceFen,
      'records': [
        if (appId == 'tu') ...[
          for (final tx in card.transactions)
            if (tx.rawHex case final raw?)
              {'sfi': 0x18, 'recordNumber': ?tx.recordNumber, 'rawHex': raw},
          for (final record in card.transitProcessRecords)
            {
              'sfi': record.sfi,
              'recordNumber': record.recordNumber,
              'rawHex': record.rawHex,
            },
        ],
        if (appId == 'cu')
          for (final file in card.cityUnionFiles)
            {
              'sfi': file.sfi,
              if (file is CityUnionWalletTransaction)
                'recordNumber': ?file.recordNumber,
              if (file is CityUnionRawFileView)
                'recordNumber': ?file.recordNumber,
              'rawHex': file.rawHex,
              if (file.errors.isNotEmpty) 'errors': file.errors,
            },
      ],
    },
    ReadResult wallet => captureLocalApplication(wallet),
    Map<String, dynamic> frozen when frozen['kind'] == 'parsed_card' => frozen,
    _ => null,
  };

  /// 旧快照中的银行卡条目保留原文，跳过展示投影。
  static bool isRetiredBankEntry(Object? raw) =>
      raw is Map && raw['appId'] == 'bank';

  static List<ApplicationEvidence> parseList(Object? raw) => [
    if (raw is List)
      for (final item in raw) ?tryParse(item),
  ];

  /// Original records grouped by this application, including their physical
  /// file/directory when captured. Never project another wallet's ledger here.
  Iterable<({String source, String rawHex})> get rawRecords sync* {
    for (final entry in observations.entries) {
      yield (source: entry.key, rawHex: entry.value);
    }
    final wallet = payload;
    if (wallet is ReadResult || wallet == null) {
      for (final record in wallet is ReadResult ? wallet.records : records) {
        final bytes = record.rawBody ?? record.response;
        if (bytes == null || bytes.isEmpty) continue;
        yield (
          source: [
            ?record.directory,
            if (record.fileSelector > 0)
              'SFI ${_file(record.fileSelector >> 3)}',
            if (record.recordNumber > 0) '#${record.recordNumber}',
            if (record.label?.isNotEmpty == true) record.label!,
          ].join(' · '),
          rawHex: LocalHex.bytesToHex(bytes),
        );
      }
      return;
    }
    final rows = payloadSummary()?['records'];
    if (rows is! List) return;
    for (final row in rows.whereType<Map>()) {
      if (row['rawHex'] case final String raw when raw.isNotEmpty) {
        yield (
          source: [
            if (row['sfi'] case final int sfi) 'SFI ${_file(sfi)}',
            if (row['recordNumber'] case final int number) '#$number',
            if (row['errors'] case final List errors)
              ...errors.whereType<String>(),
          ].join(' · '),
          rawHex: raw,
        );
      }
    }
  }

  static String _file(int value) =>
      '0x${value.toRadixString(16).toUpperCase().padLeft(2, '0')}';

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
    final observations = json['observations'];
    final rawPayload = json['payload'];
    final transportFailure = failureMap == null
        ? null
        : TransportFailure(
            kind: failureKind ?? TransportFailureKind.unknown,
            message: failureMap['message']?.toString() ?? '',
            code: failureMap['code']?.toString(),
          );
    final Object? payload;
    if (json['appId'] == 'tuCash' && json['confirmed'] == true) {
      payload = TUnionCashLog.fromPayload(rawPayload);
    } else if (rawPayload is Map && rawPayload['kind'] == 'parsed_card') {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      payload = restoreLocalApplication(
        rawPayload,
        readError: json['readError']?.toString(),
        transportFailure: transportFailure,
      );
    }
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
      transportFailure: transportFailure,
      payload: payload,
      records: payload is ReadResult
          ? payload.records
          : [
              if (json['records'] case final List rows)
                for (final row in rows.whereType<Map>())
                  restoreApplicationRecord(row),
            ],
      observations: {
        if (observations is Map)
          for (final entry in observations.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      notes: [
        for (final note in notesRaw is List ? notesRaw : const [])
          if (note is String) note,
      ],
    );
  }
}
