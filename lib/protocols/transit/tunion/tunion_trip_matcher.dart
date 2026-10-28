import 'tunion_models.dart';

/// Strong same-operation evidence for a 1A side and a 1E record. This is a
/// display relationship only; no amounts or raw records are rewritten.
bool matchesTunionJourneySide({
  required bool isEntry,
  required bool isRail,
  required DateTime? time,
  required String? cityCode,
  required String? terminalId,
  required int? amountFen,
  required TUnionTripRecord cycle,
}) {
  String normalize(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
  final city = normalize(cityCode);
  final terminal = normalize(terminalId);
  return time != null &&
      time == cycle.time &&
      RegExp(r'^[0-9A-F]{4}$').hasMatch(city) &&
      !RegExp(r'^[0F]+$').hasMatch(city) &&
      city == normalize(cycle.cityCode) &&
      RegExp(r'^[0-9A-F]{16}$').hasMatch(terminal) &&
      !RegExp(r'^0+$|^F+$').hasMatch(terminal) &&
      terminal == normalize(cycle.terminalId) &&
      (isRail ? cycle.isCityRail : cycle.isBus) &&
      (isEntry
          ? const {0x01, 0x03}.contains(cycle.typeCode)
          : const {0x02, 0x04}.contains(cycle.typeCode)) &&
      (amountFen == null || amountFen == cycle.amountFen);
}

/// 展示关联，不是余额锚点：秒级时间相等 OR 有效基础 POS 被扩展 POS 包含。
bool matchesTunionDisplay({
  required DateTime? basicTime,
  required String? basicPos,
  required DateTime? extendedTime,
  required String? extendedPos,
}) {
  if (basicTime != null &&
      extendedTime != null &&
      basicTime.millisecondsSinceEpoch ~/ 1000 ==
          extendedTime.millisecondsSinceEpoch ~/ 1000) {
    return true;
  }
  String normalize(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
  bool valid(String value) =>
      value.isNotEmpty &&
      RegExp(r'^[0-9A-F]+$').hasMatch(value) &&
      !RegExp(r'^0+$|^F+$').hasMatch(value);
  final basic = normalize(basicPos);
  final extended = normalize(extendedPos);
  return valid(basic) &&
      !basic.contains('00000000') &&
      valid(extended) &&
      extended.contains(basic);
}

/// 同一来源先分配全部秒级对应，再按 POS 补缺；同强度候选保持原顺序。
/// 来源之间独立占用，终端复用不能抢占另一事件已知的精确时间对应。
Map<int, int> matchTunionDisplayEvents<B, E>(
  List<B> basics,
  List<E> events, {
  required DateTime? Function(B) basicTime,
  required String? Function(B) basicPos,
  required DateTime? Function(E) eventTime,
  required String? Function(E) eventPos,
}) {
  final result = <int, int>{};
  final usedEvents = <int>{};
  for (final exactTime in [true, false]) {
    for (var event = 0; event < events.length; event++) {
      if (usedEvents.contains(event)) continue;
      for (var basic = 0; basic < basics.length; basic++) {
        if (result.containsKey(basic)) continue;
        if (matchesTunionDisplay(
          basicTime: basicTime(basics[basic]),
          basicPos: exactTime ? null : basicPos(basics[basic]),
          extendedTime: eventTime(events[event]),
          extendedPos: exactTime ? null : eventPos(events[event]),
        )) {
          result[basic] = event;
          usedEvents.add(event);
          break;
        }
      }
    }
  }
  return result;
}

/// 只标识展示证据，不参与金融账本。保留侧与原始记录，供快照恢复去重。
String tunionDisplayKey(
  String source,
  DateTime? time,
  String? pos,
  String? raw, [
  Object? detail,
]) =>
    '$source|${time?.millisecondsSinceEpoch}|${pos?.replaceAll(RegExp(r'\s+'), '').toUpperCase()}|$raw|$detail';

String cycleDisplayKey(TUnionTripRecord record) => tunionDisplayKey(
  '1E',
  record.time,
  record.terminalId,
  record.rawHex,
  '${record.typeCode}:${record.amountFen}:${record.lineStationCode}',
);

class TunionApplicationSide {
  const TunionApplicationSide({this.rail, this.bus, required this.isEntry});
  final TransitRecord? rail;
  final BusTransitRecord? bus;
  final bool isEntry;
  DateTime? get time => isEntry
      ? rail?.entryTime ?? bus?.entryTime
      : rail?.exitTime ?? bus?.exitTime;
  String? get terminal => isEntry
      ? rail?.entryTerminalId ?? bus?.entryTerminalId
      : rail?.exitTerminalId ?? bus?.exitTerminalId;
  String get key => tunionDisplayKey(
    rail != null ? '1A-rail-$isEntry' : '1A-bus-$isEntry',
    time,
    terminal,
    rail?.rawHex ?? bus?.rawHex,
  );
}

List<TunionApplicationSide> tunionApplicationSides(
  List<TUnionProcessRecord> records,
) => [
  for (final record in records)
    if (record.sfi == 0x1A && !record.isBlank)
      for (final entry in [true, false])
        if ((entry
                ? record.railTransit?.entryTime ?? record.busTransit?.entryTime
                : record.railTransit?.exitTime ??
                      record.busTransit?.exitTime) !=
            null)
          TunionApplicationSide(
            rail: record.railTransit,
            bus: record.busTransit,
            isEntry: entry,
          ),
];
