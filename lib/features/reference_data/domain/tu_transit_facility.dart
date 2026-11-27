/// 重庆以公交线路字段记录的一票制设施，不改变原始记录或线路编码。
///
/// 调用方须先确认记录属于公交消费；这里仅匹配本笔记录的受理城市和线路，
/// 不使用发卡城市，也不从站名、终端号等其他字段猜测设施。
enum TuTransitFacility {
  yangtzeCableway('701', '长江索道', '索道'),
  kaixuanRoadElevator('703', '凯旋路电梯', '电梯'),
  crownEscalator('704', '皇冠大扶梯', '扶梯');

  const TuTransitFacility(this.routeNumber, this.nameLabel, this.modeLabel);

  final String routeNumber;
  final String nameLabel;
  final String modeLabel;

  static final _busLinePattern = RegExp(r'^0?([0-9]{3})路?$');
  static final _byRouteNumber = {
    for (final facility in values) facility.routeNumber: facility,
  };

  /// 接受四位 BCD 线路码（如 0703）及已保存的公交线路标签（如 703路）。
  static TuTransitFacility? fromBusLine(String? cityCode, String? line) {
    if (cityCode != '6900' || line == null) return null;
    final number = _busLinePattern.firstMatch(line.trim())?.group(1);
    return _byRouteNumber[number];
  }
}
