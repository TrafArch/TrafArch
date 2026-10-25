import 'tunion_models.dart';

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

/// 同一来源顺序扫描，先到的事件占用先到的基础交易；来源之间独立占用。
Map<int, int> matchTunionDisplayEvents<B, E>(
  List<B> basics,
  List<E> events, {
  required DateTime? Function(B) basicTime,
  required String? Function(B) basicPos,
  required DateTime? Function(E) eventTime,
  required String? Function(E) eventPos,
}) {
  final result = <int, int>{};
  for (var event = 0; event < events.length; event++) {
    for (var basic = 0; basic < basics.length; basic++) {
      if (result.containsKey(basic)) continue;
      if (matchesTunionDisplay(
        basicTime: basicTime(basics[basic]),
        basicPos: basicPos(basics[basic]),
        extendedTime: eventTime(events[event]),
        extendedPos: eventPos(events[event]),
      )) {
        result[basic] = event;
        break;
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
