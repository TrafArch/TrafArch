import '../reference_data/domain/station_codes.dart';
import '../reference_data/domain/tunion_terminal_decoder.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import '../../protocols/transit/tunion/tunion_trip_matcher.dart';

/// 交易后余额倒推口径的起始解析版本：该版本起 `balanceAfterFen`
/// 优先取 0x1E 记录余额、缺失处按连续交易倒推（未配对 0x1E 的交易
/// 也可能带余额）；更早版本只保存 0x1E 配对的记录余额。
const int kBalanceReconstructionParseVersion = 6;

/// v8 起钱包连续倒推优先；1E 仅回退展示原始记录余额、不恢复倒推链。
/// 快照显式保存余额来源，避免用数值相等推断口径。
const int kWalletAnchoredBalanceParseVersion = 8;

/// 行程解析口径版本：解析 / 关联规则变更时递增，随读取批次持久化，
/// 历史数据据此识别产出批次所用的解析口径。
const int kTripParseVersion = kWalletAnchoredBalanceParseVersion;

/// 识别证据：来源、说明与权重（0 表示"出场但未命中"）。
class Evidence {
  final String source;
  final String detail;
  final double weight;

  const Evidence({
    required this.source,
    required this.detail,
    required this.weight,
  });
}

/// 卡片身份识别结果（多证据融合 + 置信度 + 证据链）。
class CardIdentity {
  final String? cityCode;
  final String? cityName;
  final String? provinceName;
  final String? operatorName;
  final String? cardFamily;
  final double confidence;
  final List<Evidence> evidence;

  const CardIdentity({
    this.cityCode,
    this.cityName,
    this.provinceName,
    this.operatorName,
    this.cardFamily,
    required this.confidence,
    this.evidence = const [],
  });

  bool get isKnown => cityName != null || operatorName != null;

  String get confidenceText => '${(confidence * 100).round()}%';
}

/// 钱包货币：金额字段口径为该货币的最小单位（分），展示符号与单位随
/// 条目声明而定。数据源为卡号前缀库条目的 currency 字段；未声明时
/// 缺省人民币（不猜测外币）。
class Currency {
  final String code; // ISO 4217 货币代码（CNY / HKD）
  final String symbol; // 展示符号（¥ / HK$）
  final String unit; // 中文单位名（元 / 港元）

  const Currency({
    required this.code,
    required this.symbol,
    required this.unit,
  });

  static const cny = Currency(code: 'CNY', symbol: '¥', unit: '元');
  static const hkd = Currency(code: 'HKD', symbol: 'HK\$', unit: '港元');
  static const mop = Currency(code: 'MOP', symbol: 'MOP\$', unit: '澳门元');

  static const _known = <String, Currency>{'CNY': cny, 'HKD': hkd, 'MOP': mop};

  /// 货币代码 → 货币；null / 未收录回退人民币（缺省口径）。
  static Currency fromCode(String? code) {
    if (code == null) return cny;
    return _known[code.trim().toUpperCase()] ?? cny;
  }
}

/// 钱包摘要（金额口径为 [currency] 的最小单位"分"）。
class WalletSummary {
  final String? cardNumber;
  final int? balanceFen;
  final DateTime? effectiveDate;
  final DateTime? expireDate;
  final bool expired;
  final int? daysRemaining;

  /// 钱包货币（按卡号前缀库判定）；缺省人民币。
  final Currency currency;

  const WalletSummary({
    this.cardNumber,
    this.balanceFen,
    this.effectiveDate,
    this.expireDate,
    required this.expired,
    this.daysRemaining,
    this.currency = Currency.cny,
  });

  factory WalletSummary.of(
    TUnionCardInfo info,
    DateTime now, {
    Currency currency = Currency.cny,
  }) {
    final exp = info.expireDate;
    return WalletSummary(
      cardNumber: info.displayCardNumber,
      balanceFen: info.balanceFen,
      effectiveDate: info.effectiveDate,
      expireDate: exp,
      expired: exp != null && exp.isBefore(now),
      daysRemaining: exp?.difference(now).inDays,
      currency: currency,
    );
  }

  String? get balanceText => balanceFen == null
      ? null
      : '${currency.symbol}${(balanceFen! / 100).toStringAsFixed(2)}';
}

/// 行程段（v0.1：一条交易记录 = 一段行程，含终端解码结果；
/// 未来可扩展为进/出站配对的完整行程）。
class TransitTrip {
  final DateTime time;
  final int amountFen;
  final int overdraftLimitFen;
  final bool isConsume;
  final String typeName;

  /// 是否为复合消费（0x09）交易：0x18 用一条记录一次性结算进出站行程。
  /// 供行程流去重——其时间戳与某条 0x1A 进 / 出站记录完全匹配时，
  /// 该行程已由更完整的 0x1A 明细表达，复合消费条目被屏蔽。
  final bool isCompositeConsume;

  final int sequence;
  final String terminalId;
  final TerminalLocation? location;
  final String? cityName;

  /// 交易城市代码（终端解码切分或 0x1E / 0x1A 配对记录读出，全 0 视为
  /// 未写入）；无法确定时为 null，展示层据此判定异地用卡（未知不判定）。
  final String? cityCode;

  final String? lineLabel;
  final String? stationLabel;

  /// 站点条目类型（如 "地铁" / "BRT" / "公交"）；
  /// 未命中站点代码表（回退原始编码或无位置数据）时为 null。
  final String? stationType;

  /// 应用分类名称（如 "城市轨道交通" / "公共汽电车"）；
  /// 由 0x1E 过程记录按"时间 + 金额"配对补充，未配对或未收录时为 null。
  final String? appTypeName;

  /// 交易余额（分）：优先从当前钱包沿连续账本倒推交易后余额；无法
  /// 倒推时仅回退展示配对的 1E 原始记录余额，由来源字段区分口径。
  final int? balanceAfterFen;

  /// 余额来源：true 为 0x1E 记录余额（前后语义未知）；false 为当前钱包
  /// 或按连续交易倒推的交易后余额；
  /// null 为旧数据 / 未标注（展示层按记录余额兼容）。
  final bool? balanceAfterIsRecorded;

  /// 复合消费（0x09）行程配对命中时的状态短名（如 "出站" / "进站" /
  /// "上车" / "下车"）；其他行程或未配对时为 null，展示层据此替换
  /// "复合消费"类型名（未配对保持原名，不猜测）。
  final String? rideStatusName;

  /// 是否为进站记录：0 元交易与 0x1E 入站类记录（EC 0x01 / EP 0x03）
  /// 按"时间 + 金额"配对命中时为 true；0x1E 未命中时按 0x1A 记录 1/2
  /// （城市轨道 / 公共汽电车应用信息记录）的进站时间兜底配对。
  /// 展示层据此改显进站时间与站点。
  final bool isEntry;

  /// 与 0x18 双向唯一配对的 0x1E 原始证据；无来源时不得推断 1A 去重。
  final TUnionTripRecord? matchedProcessTrip;

  /// 独立展示关联证据；不得用于恢复记录余额。
  final String? displayProcessKey;
  final String? displayApplicationKey;

  /// 站点名称匹配置信级别（精确 / 歧义 / 未匹配；已取消站名推测）；
  /// 名称来自站点库命中时非 null，回退原始编码时为 null（不猜测）。
  final StationMatchConfidence? stationConfidence;

  /// 0x18 原始记录字节 HEX（详情页原始数据展示）；未保留时为 null。
  final String? rawHex;

  /// 钱包货币（与钱包摘要一致，金额文本按该货币符号展示）。
  final Currency currency;

  const TransitTrip({
    required this.time,
    required this.amountFen,
    required this.overdraftLimitFen,
    required this.isConsume,
    required this.typeName,
    this.isCompositeConsume = false,
    required this.sequence,
    required this.terminalId,
    this.location,
    this.cityName,
    this.cityCode,
    this.lineLabel,
    this.stationLabel,
    this.stationType,
    this.appTypeName,
    this.balanceAfterFen,
    this.balanceAfterIsRecorded,
    this.rideStatusName,
    this.isEntry = false,
    this.matchedProcessTrip,
    this.displayProcessKey,
    this.displayApplicationKey,
    this.stationConfidence,
    this.rawHex,
    this.currency = Currency.cny,
  });

  String get amountText =>
      '${isConsume ? '-' : '+'}${currency.symbol}${(amountFen / 100).toStringAsFixed(2)}';

  /// 余额展示文本（如 "¥53.40" / "HK\$53.40"）；无余额证据时为 null。
  String? get balanceAfterText => balanceAfterFen == null
      ? null
      : '${currency.symbol}${(balanceAfterFen! / 100).toStringAsFixed(2)}';

  /// 余额口径标签：记录余额 / 交易后余额（旧数据按记录余额兼容）。
  String? get balanceAfterLabel => balanceAfterFen == null
      ? null
      : balanceAfterIsRecorded == false
      ? '交易后余额'
      : '记录余额';

  bool get hasLocation =>
      lineLabel != null || stationLabel != null || cityName != null;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get timeText =>
      '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
}

/// JT/T 978 符合性单项状态。
enum ComplianceStatus { pass, warn, fail, info }

/// JT/T 978 符合性检查项。
class ComplianceItem {
  final String id;
  final String title;
  final ComplianceStatus status;
  final String detail;

  const ComplianceItem({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
  });

  double get weight => switch (status) {
    ComplianceStatus.pass => 1,
    ComplianceStatus.warn => 0.5,
    ComplianceStatus.fail => 0,
    ComplianceStatus.info => 0,
  };
}

/// JT/T 978 符合性报告（info 项不计入覆盖率）。
class ComplianceReport {
  final List<ComplianceItem> items;
  final int scorePercent;

  const ComplianceReport({required this.items, required this.scorePercent});

  int get passCount =>
      items.where((i) => i.status == ComplianceStatus.pass).length;
  int get warnCount =>
      items.where((i) => i.status == ComplianceStatus.warn).length;
  int get failCount =>
      items.where((i) => i.status == ComplianceStatus.fail).length;
}

/// 异常严重级别。
enum AnomalySeverity { info, warn, critical }

/// 异常数据项。
class Anomaly {
  final String code;
  final AnomalySeverity severity;
  final String message;

  const Anomaly({
    required this.code,
    required this.severity,
    required this.message,
  });
}

/// 分析引擎输出契约：UI 只消费这一个模型。
class CardAnalysisResult {
  final CardIdentity identity;
  final WalletSummary wallet;

  /// 钱包货币（按卡号前缀库条目声明判定）；未声明时缺省人民币。
  final Currency currency;
  final List<TransitTrip> trips;
  final ComplianceReport compliance;
  final List<Anomaly> anomalies;
  final DateTime generatedAt;

  const CardAnalysisResult({
    required this.identity,
    required this.wallet,
    this.currency = Currency.cny,
    required this.trips,
    required this.compliance,
    required this.anomalies,
    required this.generatedAt,
  });
}

/// 行程流条目：把交易明细（[TransitTrip]）与 0x1A 过程记录
/// ——城市轨道交通进出站（[TransitRecord]）、公共汽电车上下车
/// （[BusTransitRecord]）——统一为一类可按时间排序的元素，供行程页 /
/// 卡片详情页合并成一条按时间倒序的行程流展示。0x1A 记录按进 / 出
/// （上 / 下）两侧各拆为一条行程记录，展示样式与 0x1E 配对的行程卡片一致。
sealed class TripEntry {
  const TripEntry();

  /// 排序用时间：取行程/记录的发生时间，进站/上车时间优先。
  DateTime get time;
}

/// 交易明细行程（0x18）。
final class TransactionTripEntry extends TripEntry {
  final TransitTrip trip;
  const TransactionTripEntry(this.trip);
  @override
  DateTime get time => trip.time;
}

/// 0x1A 记录 1：城市轨道交通进出站记录的一侧（进站 / 出站）。
/// [isEntry] 为 true 表示进闸侧行程，false 表示出闸侧；
/// 展示层按侧取对应字段渲染为单条行程卡片。
final class RailRecordEntry extends TripEntry {
  final TransitRecord record;
  final bool isEntry;
  const RailRecordEntry(this.record, {required this.isEntry});
  @override
  DateTime get time => isEntry
      ? (record.entryTime ?? record.exitTime ?? DateTime(0))
      : (record.exitTime ?? record.entryTime ?? DateTime(0));
}

/// 0x1A 记录 2：公共汽电车上下车记录的一侧（上车 / 下车）。
/// [isEntry] 为 true 表示上车侧行程，false 表示下车侧；
/// 展示层按侧取对应字段渲染为单条行程卡片。
final class BusRecordEntry extends TripEntry {
  final BusTransitRecord record;
  final bool isEntry;
  const BusRecordEntry(this.record, {required this.isEntry});
  @override
  DateTime get time => isEntry
      ? (record.entryTime ?? record.exitTime ?? DateTime(0))
      : (record.exitTime ?? record.entryTime ?? DateTime(0));
}

/// 未与任何 0x18 交易关联的 0x1E 过程记录（独立过程事件条目）。
/// 关联不成立时保留展示（不漏显），统计口径计入过程事件、
/// 出站/结算类另计行程，不重复计入消费。
final class ProcessTripEntry extends TripEntry {
  final TUnionTripRecord record;
  const ProcessTripEntry(this.record);
  @override
  DateTime get time => record.time;
}

/// 合并交易行程（0x18，主干来源）、0x1A 过程记录（按进 / 出侧拆分）与
/// 0x1E 过程记录为按时间倒序的行程流：
/// - 已与交易配对的 0x1E 由交易条目代表；无法配对的 0x1E 保留为
///   [ProcessTripEntry]（独立过程事件，不丢弃）；
/// - 1A 仅隐藏已保存展示关联的具体侧；不隐藏基础交易或未匹配侧。
List<TripEntry> buildTripStream({
  required List<TransitTrip> trips,
  List<TransitRecord> rails = const [],
  List<BusTransitRecord> buses = const [],
  List<TUnionTripRecord> processTrips = const [],
}) {
  // 仅消费分析阶段保存的关联；不按存在某类文件全局压制事件。
  final halves = <TripEntry>[
    for (final rail in rails) ..._railHalves(rail),
    for (final bus in buses) ..._busHalves(bus),
  ];
  final applicationKeys = [
    for (final t in trips)
      if (t.displayApplicationKey != null) t.displayApplicationKey!,
  ];
  final processKeys = [
    for (final t in trips)
      if (t.displayProcessKey != null) t.displayProcessKey!,
  ];
  bool consume(List<String> keys, String key) {
    final index = keys.indexOf(key);
    if (index < 0) return false;
    keys.removeAt(index);
    return true;
  }

  String sideKey(TripEntry side) => switch (side) {
    RailRecordEntry(:final record, :final isEntry) => TunionApplicationSide(
      rail: record,
      isEntry: isEntry,
    ).key,
    BusRecordEntry(:final record, :final isEntry) => TunionApplicationSide(
      bus: record,
      isEntry: isEntry,
    ).key,
    _ => '',
  };
  // 已关联到交易的 0x1E 记录（配对证据随快照保存，按值比对）不再单独展示。
  // 旧快照只兼容其严格关联；新展示证据存在时不再额外消费余额关联。
  processKeys.addAll([
    for (final t in trips)
      if (t.displayProcessKey == null && t.matchedProcessTrip != null)
        cycleDisplayKey(t.matchedProcessTrip!),
  ]);
  return <TripEntry>[
    for (final t in trips) TransactionTripEntry(t),
    ...halves.where((side) => !consume(applicationKeys, sideKey(side))),
    for (final p in processTrips)
      if (!consume(processKeys, cycleDisplayKey(p))) ProcessTripEntry(p),
  ]..sort((a, b) => b.time.compareTo(a.time));
}

/// 0x1A 城市轨道记录是否与 0x1E 过程记录描述同一进 / 出站侧：
/// 类型、时间、城市及金额 / 终端互证；仅凭时间或金额相似不成立。
bool railRecordMatchesProcess(TransitRecord rail, TUnionTripRecord process) {
  if (!process.isCityRail) return false;
  final entry = _processEntrySide(process.typeCode);
  if (entry == null) return false;
  return _matchesProcessEvidence(
    source: process,
    entry: entry,
    time: entry ? rail.entryTime : rail.exitTime,
    city: entry ? rail.entryCityCode : rail.exitCityCode,
    terminal: entry ? rail.entryTerminalId : rail.exitTerminalId,
    amount: entry ? rail.entryAmountFen : rail.exitAmountFen,
  );
}

bool? _processEntrySide(int typeCode) => switch (typeCode) {
  0x01 || 0x03 => true,
  0x02 || 0x04 => false,
  _ => null,
};

bool matchesLegacyProcessSide(TransitTrip trip, TripEntry side) {
  final source = trip.matchedProcessTrip;
  if (source == null || !trip.isConsume) return false;
  switch (side) {
    case RailRecordEntry(:final record, :final isEntry):
      if (!source.isCityRail) return false;
      return _matchesProcessEvidence(
        source: source,
        entry: isEntry,
        time: isEntry ? record.entryTime : record.exitTime,
        city: isEntry ? record.entryCityCode : record.exitCityCode,
        terminal: isEntry ? record.entryTerminalId : record.exitTerminalId,
        amount: isEntry ? record.entryAmountFen : record.exitAmountFen,
      );
    case BusRecordEntry(:final record, :final isEntry):
      if (!source.isBus) return false;
      return _matchesProcessEvidence(
        source: source,
        entry: isEntry,
        time: isEntry ? record.entryTime : record.exitTime,
        city: isEntry ? record.entryCityCode : record.exitCityCode,
        terminal: isEntry ? record.entryTerminalId : record.exitTerminalId,
        // 公交 transactionAmountFen 未声明侧归属，不能用作任一侧金额证据。
        amount: null,
      );
    default:
      return false;
  }
}

bool _matchesProcessEvidence({
  required TUnionTripRecord source,
  required bool entry,
  required DateTime? time,
  required String? city,
  required String? terminal,
  required int? amount,
}) {
  final sourceEntry = _processEntrySide(source.typeCode);
  if (sourceEntry == null || entry != sourceEntry) return false;
  String? validHex(String? value, int length) {
    final text = value?.trim().toUpperCase();
    if (text == null ||
        !RegExp('^[0-9A-F]{$length}\$').hasMatch(text) ||
        RegExp(r'^[0F]+$').hasMatch(text)) {
      return null;
    }
    return text;
  }

  final validCity = validHex(city, 4);
  if (time == null ||
      time != source.time ||
      validCity == null ||
      validCity != validHex(source.cityCode, 4)) {
    return false;
  }
  if (amount != null && amount != source.amountFen) return false;
  final sideTerminal = validHex(terminal, 16);
  final sourceTerminal = validHex(source.terminalId, 16);
  if (sideTerminal != null &&
      sourceTerminal != null &&
      sideTerminal != sourceTerminal) {
    return false;
  }
  // 无侧金额（包括公交）时必须另有同侧终端证据。
  return amount != null ||
      (sideTerminal != null && sideTerminal == sourceTerminal);
}

/// 0x1E 记录同一性判定（跨快照重建对象后仍可按值关联）：
/// 优先按原始 HEX；无原始字节时按 类型 + 时间 + 金额 + 终端 四要素。
bool sameProcessRecord(TUnionTripRecord a, TUnionTripRecord b) {
  if (identical(a, b)) return true;
  final ra = a.rawHex;
  final rb = b.rawHex;
  if (ra != null && rb != null) return ra == rb;
  return a.typeCode == b.typeCode &&
      a.time == b.time &&
      a.amountFen == b.amountFen &&
      a.terminalId == b.terminalId;
}

/// 0x1A 记录 1 拆分：进站侧（有进站时间时）+ 出站侧（有出站时间时）；
/// 两侧时间均未写入时保留一条出站侧兜底（时间排在行程流末尾）。
List<TripEntry> _railHalves(TransitRecord rail) {
  final halves = <TripEntry>[
    if (rail.entryTime != null) RailRecordEntry(rail, isEntry: true),
    if (rail.exitTime != null) RailRecordEntry(rail, isEntry: false),
  ];
  return halves.isEmpty ? [RailRecordEntry(rail, isEntry: false)] : halves;
}

/// 0x1A 记录 2 拆分：上车侧 + 下车侧，规则同 [_railHalves]。
List<TripEntry> _busHalves(BusTransitRecord bus) {
  final halves = <TripEntry>[
    if (bus.entryTime != null) BusRecordEntry(bus, isEntry: true),
    if (bus.exitTime != null) BusRecordEntry(bus, isEntry: false),
  ];
  return halves.isEmpty ? [BusRecordEntry(bus, isEntry: false)] : halves;
}

/// 行程流统一统计口径（三类计数互不混用；0x1E / 0x1A 过程记录
/// 不重复计入交易与消费）：
/// - [transactionCount] / [consumeCount]：0x18 交易明细笔数 / 其中消费；
/// - [processEventCount]：独立展示的 0x1E 与 0x1A 过程事件条数
///   （已与交易确认重复合并的不重复计数）；
/// - [tripCount]：实际行程数 = 0x18 消费交易 + 未关联 0x1E 的
///   出站 / 结算类记录（入站 / 上车类过程不计行程）。
class TripStreamStats {
  final int transactionCount;
  final int consumeCount;
  final int processEventCount;
  final int tripCount;

  const TripStreamStats({
    required this.transactionCount,
    required this.consumeCount,
    required this.processEventCount,
    required this.tripCount,
  });

  String get summaryText =>
      '交易 $transactionCount 笔（消费 $consumeCount） · '
      '过程事件 $processEventCount 条 · 行程 $tripCount 次';
}

TripStreamStats summarizeTripStream(List<TripEntry> stream) {
  var txn = 0, consume = 0, process = 0, trips = 0;
  for (final entry in stream) {
    switch (entry) {
      case TransactionTripEntry(:final trip):
        txn++;
        if (trip.isConsume) {
          consume++;
          trips++;
        }
      case ProcessTripEntry(:final record):
        process++;
        if (!record.isEntry) trips++;
      case RailRecordEntry():
      case BusRecordEntry():
        process++;
    }
  }
  return TripStreamStats(
    transactionCount: txn,
    consumeCount: consume,
    processEventCount: process,
    tripCount: trips,
  );
}

/// 行程流按自然日分组（流已按时间倒序，组内保持原顺序）。
class TripDateGroup {
  final DateTime date;
  final List<TripEntry> entries;
  const TripDateGroup({required this.date, required this.entries});

  String get dateText =>
      '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

List<TripDateGroup> groupTripsByDate(List<TripEntry> stream) {
  final groups = <TripDateGroup>[];
  for (final entry in stream) {
    final day = DateTime(entry.time.year, entry.time.month, entry.time.day);
    if (groups.isNotEmpty && groups.last.date == day) {
      groups.last.entries.add(entry);
    } else {
      groups.add(TripDateGroup(date: day, entries: [entry]));
    }
  }
  return groups;
}
