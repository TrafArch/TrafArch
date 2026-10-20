// lib/core/transit/local_card/cards/shanghai_transit_union_models.dart

library;

import '../../../card/card_parser.dart';
import '../../city_union/city_union_models.dart';
import '../../tunion/tunion_models.dart';
import '../local_card_models.dart';

/// 上海交通卡（交通联合版）识别常量。
///
/// 该卡种默认按 TU（JT/T 978.2）+ CU（CJ/T 331-2016）双标卡处理，
/// 由专用识别器 [ShanghaiTransitUnionCardParser] 独立识读，不归入普通
/// 交通联合卡解析器。
abstract final class ShanghaiTransitUnionIds {
  /// 展示 / 日志用模块名。
  static const String moduleName = '上海交通卡（交通联合版）';

  /// 卡号（应用序列号）IIN 前缀。
  ///
  /// 仅作辅助线索：卡片内部是否真的具备 TU / CU 应用结构，必须由
  /// AID 选择结果与实际读取数据确认，前缀不能单独证明应用结构。
  static const String cardNumberPrefix = '31047700';

  /// 发卡机构标识（HEX）前缀，同为辅助线索（卡号 IIN 未命中时的回退）。
  static const String issuerIdPrefix = '02002900';

  /// 两个应用的展示名（日志 / 状态文本）。
  static const String tuSystem = '交通联合（TU）';
  static const String cuSystem = '城市一卡通（CU）';
}

/// 上海交通卡（交通联合版）识别结果。
///
/// `Available` 表示**实际读取并解析后确认可用**（应用已确认 + 读取成功 +
/// 数据完整），不代表卡片理论上一定只具有某一种应用。
enum ShanghaiTransitUnionStatus {
  bothAvailable,
  tuOnlyAvailable,
  cuOnlyAvailable,
  recognizedButUnreadable,
  unknown;

  /// 是否存在实际可用的应用数据（至少一侧可用）。
  bool get hasAvailableApplication =>
      this == ShanghaiTransitUnionStatus.bothAvailable ||
      this == ShanghaiTransitUnionStatus.tuOnlyAvailable ||
      this == ShanghaiTransitUnionStatus.cuOnlyAvailable;
}

extension ShanghaiTransitUnionStatusLabel on ShanghaiTransitUnionStatus {
  String get label => switch (this) {
        ShanghaiTransitUnionStatus.bothAvailable => 'TU + CU 双应用可用',
        ShanghaiTransitUnionStatus.tuOnlyAvailable => '仅交通联合（TU）可用',
        ShanghaiTransitUnionStatus.cuOnlyAvailable => '仅城市一卡通（CU）可用',
        ShanghaiTransitUnionStatus.recognizedButUnreadable =>
          '应用已确认，数据不可读',
        ShanghaiTransitUnionStatus.unknown => '未确认上海交通卡应用',
      };
}

/// 单侧应用（TU / CU）的独立识读结果。
///
/// 三个状态分开记录，互不替代：
/// - [confirmed]：应用是否确认（AID 选择成功，结构存在）；
/// - [readSucceeded]：读取是否成功（拿到可解析的数据）；
/// - [dataComplete]：数据是否完整（关键标识与钱包数据齐全）。
///
/// [card] / [records] / [errors] 保留该侧原始产物与解析错误，供合并与
/// 专家模式分别核对，不做相互覆盖。
class ShanghaiTransitApplication {
  const ShanghaiTransitApplication({
    required this.system,
    required this.cardInfo,
    required this.records,
    this.confirmed = false,
    this.readSucceeded = false,
    this.dataComplete = false,
    this.card,
    this.identity,
    this.errors = const [],
    this.warnings = const [],
  });

  /// 应用名（[ShanghaiTransitUnionIds.tuSystem] / [ShanghaiTransitUnionIds.cuSystem]）。
  final String system;

  /// 应用是否确认（AID 选择成功）。
  final bool confirmed;

  /// 读取是否成功（TU：完整识读返回结果；CU：读到非空标准文件）。
  final bool readSucceeded;

  /// 数据是否完整（关键标识 + 钱包数据齐全）。
  final bool dataComplete;

  /// 该侧解析产物（失败时为 null）。
  final ParsedCard? card;

  /// 该侧可用的卡片标识（TU：交通联合卡信息；CU：钱包余额视图）。
  final TUnionCardInfo? identity;

  /// 该侧独立的新架构卡汇总（不与另一侧混用）。
  final CardInfo cardInfo;

  /// 该侧原始记录（含行程流水），不与另一侧混用。
  final List<ApduRecord> records;

  /// 该侧解析错误（应用未确认 / 读取失败 / 校验不通过等）。
  final List<String> errors;

  /// 该侧数据不完整的提示（不阻断另一侧，也不阻断合并）。
  final List<String> warnings;

  /// 实际可用：应用已确认 + 读取成功 + 数据完整。
  bool get available => confirmed && readSucceeded && dataComplete;

  /// 城市一卡通公共应用基本信息文件（SFI 0x15）；非 CU 侧或未读到时为 null。
  CjT331PublicInfo? get cityUnionPublicInfo {
    final views = card?.cityUnionFiles;
    if (views == null) return null;
    for (final view in views) {
      if (view is CjT331PublicInfo) return view;
    }
    return null;
  }

  /// 卡号类候选标识（十进制卡号 / 应用序列号），供前缀辅助判定。
  Iterable<String> get cardNumberCandidates sync* {
    final public = cityUnionPublicInfo;
    final values = <String?>[
      identity?.displayCardNumber,
      card?.info.displayCardNumber,
      public?.displayApplicationSerialNumber,
      public?.applicationSerialNumber,
      cardInfo.cardNumber.isEmpty ? null : cardInfo.cardNumber,
    ];
    for (final value in values) {
      if (value != null) yield value;
    }
  }

  /// 发卡机构类候选标识，供发卡机构前缀辅助判定。
  Iterable<String> get issuerCandidates sync* {
    final values = <String?>[
      identity?.issuerId,
      cityUnionPublicInfo?.issuerCode,
      cardInfo.issuerCode.isEmpty ? null : cardInfo.issuerCode,
    ];
    for (final value in values) {
      if (value != null) yield value;
    }
  }

  /// 状态摘要（专家模式 / 运行日志）。
  String get stateText => '应用${confirmed ? '已确认' : '未确认'} · '
      '读取${readSucceeded ? '成功' : '未成功'} · '
      '数据${dataComplete ? '完整' : '不完整'}';
}

/// 行程合并结果：去重后的记录 + 去掉的重复条数。
class ShanghaiTransitTripMerge {
  const ShanghaiTransitTripMerge({
    required this.records,
    required this.duplicateCount,
  });

  final List<ApduRecord> records;
  final int duplicateCount;
}

/// TU / CU 行程去重：同一笔交易在两侧都记录时只保留一份。
///
/// 判重条件（全部满足才判重，宁可不删也不误删）：
/// - 交易时间精确到分钟一致（时间不可用时该条不参与判重）；
/// - 终端号可判定且一致（含 16 位 / 12 位 BCD 的包含关系）；
/// - 交易类型不矛盾（消费 / 充值；类型未知时不阻断判重）。
///
/// 保留顺序为 TU 记录在前、CU 独有记录在后，便于展示层对照。
abstract final class ShanghaiTransitTripMerger {
  static ShanghaiTransitTripMerge merge({
    required List<ApduRecord> tuRecords,
    required List<ApduRecord> cuRecords,
  }) {
    final merged = <ApduRecord>[];
    final seen = <_SeenTrip>[];
    for (final record in tuRecords) {
      merged.add(record);
      final entry = _entryOf(record);
      if (entry != null) seen.add(entry);
    }

    var duplicates = 0;
    for (final record in cuRecords) {
      final entry = _entryOf(record);
      final isDuplicate = entry != null &&
          seen.any((s) =>
              s.minuteEpoch == entry.minuteEpoch &&
              _sameTerminal(s.terminal, entry.terminal) &&
              _compatible(s.kind, entry.kind));
      if (isDuplicate) {
        duplicates++;
        continue;
      }
      merged.add(record);
      if (entry != null) seen.add(entry);
    }

    return ShanghaiTransitTripMerge(
      records: List<ApduRecord>.unmodifiable(merged),
      duplicateCount: duplicates,
    );
  }

  static _SeenTrip? _entryOf(ApduRecord record) {
    if (record.timestamp.millisecondsSinceEpoch <= 0) return null;
    final terminal = _normalizeTerminal(record.terminalHex);
    if (terminal == null) return null;
    final t = record.timestamp;
    return _SeenTrip(
      minuteEpoch: DateTime(t.year, t.month, t.day, t.hour, t.minute)
          .millisecondsSinceEpoch ~/
          Duration.millisecondsPerMinute,
      terminal: terminal,
      kind: _kindOf(record),
    );
  }

  /// 终端号规范化：去分隔符并大写；全 0（未写入）视为不可判定。
  static String? _normalizeTerminal(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (cleaned.isEmpty) return null;
    if (cleaned.replaceAll('0', '').isEmpty) return null;
    return cleaned;
  }

  /// 终端号一致判定：TU 为 16 位、CU 为 12 位 BCD，按包含关系比对。
  static bool _sameTerminal(String a, String b) {
    if (a == b) return true;
    if (a.length < 8 || b.length < 8) return false;
    return a.endsWith(b) || b.endsWith(a);
  }

  static _TripKind _kindOf(ApduRecord record) {
    final label = record.label ?? '';
    if (label.startsWith('CU 0x1A')) return _TripKind.recharge;
    if (label.startsWith('CU 0x18')) return _TripKind.consume;
    if (record.balanceDelta > 0) return _TripKind.recharge;
    if (record.balanceDelta < 0) return _TripKind.consume;
    return _TripKind.unknown;
  }

  static bool _compatible(_TripKind a, _TripKind b) =>
      a == _TripKind.unknown || b == _TripKind.unknown || a == b;
}

/// 上海交通卡（交通联合版）双路识读的合并结果。
///
/// - [tu] / [cu]：两套数据分别保留（含各自的原始记录与解析错误）；
/// - [status]：由两侧实际读取结果判定；
/// - [isShanghaiTransitUnion]：卡号 / 发卡机构辅助前缀 + 应用结构双重确认；
/// - [mergedRecords]：去重后的行程流水；
/// - [mergedCard]：仅在本卡种成立时产出的统一 [ParsedCard]
///   （parserId = [CardParserIds.shanghaiTunion]）。
class ShanghaiTransitUnionResult {
  const ShanghaiTransitUnionResult({
    required this.tu,
    required this.cu,
    required this.status,
    required this.matchedPrefix,
    required this.structureConfirmed,
    required this.isShanghaiTransitUnion,
    required this.mergedRecords,
    required this.duplicateTripCount,
    required this.mergedCardInfo,
    required this.mergedCard,
    required this.errors,
    required this.warnings,
  });

  final ShanghaiTransitApplication tu;
  final ShanghaiTransitApplication cu;

  /// 识别状态（仅描述两路数据的实际可用性）。
  final ShanghaiTransitUnionStatus status;

  /// 命中的辅助前缀（卡号 IIN / 发卡机构标识）；未命中为 null。
  final String? matchedPrefix;

  /// 是否至少一侧应用结构已被确认（AID 选择成功）。
  final bool structureConfirmed;

  /// 是否为上海交通卡（交通联合版）：辅助前缀 + 应用结构双重确认。
  final bool isShanghaiTransitUnion;

  /// 合并后的行程流水（TU 在前，CU 独有记录在后，已去重）。
  final List<ApduRecord> mergedRecords;

  /// 合并行程时判定为重复而移除的条数。
  final int duplicateTripCount;

  /// 合并后的新架构卡汇总（TU 侧可用时优先 TU）。
  final CardInfo mergedCardInfo;

  /// 统一解析结果；本卡种不成立时为 null（调用方回退普通 TU / CU 结果）。
  final ParsedCard? mergedCard;

  /// 两路解析错误汇总（各自明细仍保留在 [tu] / [cu] 中）。
  final List<String> errors;

  /// 两路数据不完整提示汇总。
  final List<String> warnings;

  /// 新架构读取汇总（供统一识读结果携带）。
  ReadResult get readResult => ReadResult(
        info: mergedCardInfo,
        records: mergedRecords,
        extras: CardExtras(),
      );

  factory ShanghaiTransitUnionResult.build({
    required ShanghaiTransitApplication tu,
    required ShanghaiTransitApplication cu,
  }) {
    final structureConfirmed = tu.confirmed || cu.confirmed;
    final matchedPrefix = _matchPrefix(tu, cu);
    final isShanghaiTransitUnion = matchedPrefix != null && structureConfirmed;

    final status = switch ((tu.available, cu.available)) {
      (true, true) => ShanghaiTransitUnionStatus.bothAvailable,
      (true, false) => ShanghaiTransitUnionStatus.tuOnlyAvailable,
      (false, true) => ShanghaiTransitUnionStatus.cuOnlyAvailable,
      _ => structureConfirmed
          ? ShanghaiTransitUnionStatus.recognizedButUnreadable
          : ShanghaiTransitUnionStatus.unknown,
    };

    final merge = ShanghaiTransitTripMerger.merge(
      tuRecords: tu.records,
      cuRecords: cu.records,
    );

    return ShanghaiTransitUnionResult(
      tu: tu,
      cu: cu,
      status: status,
      matchedPrefix: matchedPrefix,
      structureConfirmed: structureConfirmed,
      isShanghaiTransitUnion: isShanghaiTransitUnion,
      mergedRecords: merge.records,
      duplicateTripCount: merge.duplicateCount,
      mergedCardInfo: tu.readSucceeded ? tu.cardInfo : cu.cardInfo,
      mergedCard: isShanghaiTransitUnion ? _buildMergedCard(tu: tu, cu: cu) : null,
      errors: <String>[...tu.errors, ...cu.errors],
      warnings: <String>[...tu.warnings, ...cu.warnings],
    );
  }

  /// 辅助前缀匹配：卡号 IIN 优先，回退发卡机构标识。
  /// 命中只说明「像上海卡」，是否成立仍取决于 [structureConfirmed]。
  static String? _matchPrefix(
    ShanghaiTransitApplication tu,
    ShanghaiTransitApplication cu,
  ) {
    for (final candidate in <String>[
      ...tu.cardNumberCandidates,
      ...cu.cardNumberCandidates,
    ]) {
      final digits = _digitsOnly(candidate);
      if (digits != null &&
          digits.startsWith(ShanghaiTransitUnionIds.cardNumberPrefix)) {
        return ShanghaiTransitUnionIds.cardNumberPrefix;
      }
    }
    for (final candidate in <String>[
      ...tu.issuerCandidates,
      ...cu.issuerCandidates,
    ]) {
      final hex = _hexOnly(candidate);
      if (hex != null &&
          hex.length >= 8 &&
          hex.startsWith(ShanghaiTransitUnionIds.issuerIdPrefix)) {
        return ShanghaiTransitUnionIds.issuerIdPrefix;
      }
    }
    return null;
  }

  static String? _digitsOnly(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return RegExp(r'^[0-9]+$').hasMatch(trimmed) ? trimmed : null;
  }

  static String? _hexOnly(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// 统一解析结果：TU 侧优先承载卡信息 / 交易 / 过程记录，CU 侧承载
  /// 标准文件视图与住建部钱包余额；两套钱包互不覆盖。
  static ParsedCard? _buildMergedCard({
    required ShanghaiTransitApplication tu,
    required ShanghaiTransitApplication cu,
  }) {
    final tuCard = tu.card;
    final cuCard = cu.card;
    final info = tuCard?.info ??
        _infoFromCityUnion(cu.cityUnionPublicInfo, cuCard?.info.balanceFen);
    if (info == null) return null;
    final tuAid = tuCard?.selectedAidHex ?? '';
    return ParsedCard(
      parserId: CardParserIds.shanghaiTunion,
      parserName: ShanghaiTransitUnionIds.moduleName,
      info: info,
      transactions: tuCard?.transactions ?? const [],
      transitProcessRecords: tuCard?.transitProcessRecords ?? const [],
      cityUnionFiles: cuCard?.cityUnionFiles ?? const [],
      cityUnionBalanceFen: cuCard?.info.balanceFen,
      dualApplication: tuCard != null && cuCard != null,
      selectedAidHex:
          tuAid.isNotEmpty ? tuAid : (cuCard?.selectedAidHex ?? ''),
    );
  }

  /// CU 侧单独可用时，以公共应用基本信息文件（SFI 0x15）构建统一卡信息。
  static TUnionCardInfo? _infoFromCityUnion(
    CjT331PublicInfo? public,
    int? balanceFen,
  ) {
    if (public == null && balanceFen == null) return null;
    return TUnionCardInfo(
      applicationSerial: public?.applicationSerialNumber,
      cityCode: public?.cityCode,
      effectiveDate: _dateOf(public?.applicationStartDate),
      expireDate: _dateOf(public?.applicationExpiryDate),
      balanceFen: balanceFen,
    );
  }

  static DateTime? _dateOf(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

enum _TripKind { consume, recharge, unknown }

class _SeenTrip {
  const _SeenTrip({
    required this.minuteEpoch,
    required this.terminal,
    required this.kind,
  });

  final int minuteEpoch;
  final String terminal;
  final _TripKind kind;
}