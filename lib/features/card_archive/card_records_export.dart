// 新建文件：lib/features/card_archive/card_records_export.dart
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/app_info.dart';
import '../../core/logging/app_logger.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../database/app_database.dart';
import 'models/card_name_extension.dart';
import 'models/card_session_snapshot.dart';
import 'models/card_types.dart';

/// 将卡片档案（含行程记录快照）格式化为可导出的纯文本。
///
/// 供卡片列表页「导出卡片记录」使用：输出人类可读的分节文本，展示口径
/// 与卡片列表 / 详情页一致（名称 / 卡型 / 卡号 / 余额 / 交易条数 / 最近
/// 读取 + 行程记录）；最终由原生层写入手机下载目录（text/plain）。
///
/// [stationResolver] / [lineResolver]：可选的城市 + 原始编码 → 名称解析
/// 回调（TU 环境下由 AppState 注入 `resolveStationName / resolveLineName`），
/// 供 0x1A 城市轨道进出站记录在导出中展示线路名 / 站点名；未注入或解析
/// 未命中时回退原始编码（与页面口径一致，不猜测）。
String buildCardRecordsExport(
  List<SavedCard> cards, {
  DateTime? exportedAt,
  String? Function(String? cityCode, String? rawStationId)? stationResolver,
  String? Function(String? cityCode, String? rawLineCode)? lineResolver,
}) {
  final now = exportedAt ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('=== ${AppInfo.appName} 卡片记录导出 ===')
    ..writeln('应用版本：${AppInfo.version}（Build ${AppInfo.buildNumber}）')
    ..writeln('导出时间：${AppLogger.formatTimestamp(now)}')
    ..writeln('卡片数量：${cards.length}')
    ..writeln('================================================');

  if (cards.isEmpty) {
    buffer.writeln('（暂无已保存的卡片）');
    return buffer.toString();
  }

  var index = 0;
  for (final card in cards) {
    index++;
    final snapshot = card.sessionSnapshot;
    final trips = snapshot?.trips ?? const <TransitTrip>[];
    final rail = snapshot?.railRecord;
    final bus = snapshot?.busRecord;

    buffer
      ..writeln()
      ..writeln('【$index】${card.displayName}')
      ..writeln('卡型：${cardTypeLabel(card.cardType)}')
      ..writeln('识别信息：${card.subtitle}')
      ..writeln('卡号：${card.cardNumberText}')
      ..writeln('余额：${card.balanceText ?? '未读取到'}')
      ..writeln('交易记录：${card.transactionCountText ?? '未记录'}')
      ..writeln('最近读取：${card.lastReadFullText ?? '未记录'}');

    if (trips.isEmpty && rail == null && bus == null) {
      buffer.writeln('行程记录：（无）');
      continue;
    }

    if (trips.isNotEmpty) {
      buffer.writeln('行程记录（${trips.length} 条）：');
      for (final trip in trips) {
        buffer.writeln('  · ${_tripLine(trip, snapshot)}');
      }
    }
    if (rail != null) {
      buffer
        ..writeln('城市轨道交通 · 进出站记录：')
        ..writeln('  · ${_railLine(rail, stationResolver, lineResolver)}');
    }
    if (bus != null) {
      buffer
        ..writeln('公共汽电车 · 上下车记录：')
        ..writeln('  · ${_busLine(bus)}');
    }
  }
  return buffer.toString();
}

/// 单条行程文本行（时间 / 类型 / 序号 / 金额 / 余额 / 站点 / 城市）。
String _tripLine(TransitTrip trip, CardSessionSnapshot? snapshot) {
  final parts = <String>[
    trip.timeText,
    trip.rideStatusName ?? trip.typeName,
    '序号 ${trip.sequence}',
    trip.amountText,
    if (trip.balanceAfterText != null) '余额 ${trip.balanceAfterText}',
  ];
  final location = <String>[
    if (trip.lineLabel != null) trip.lineLabel!,
    if (trip.stationLabel != null) trip.stationLabel!,
  ];
  if (location.isNotEmpty) parts.add(location.join(' '));
  final city = trip.cityName;
  if (city != null && city.isNotEmpty) {
    final remote = snapshot?.isRemoteUse(trip.cityCode) ?? false;
    parts.add(remote ? '$city（异地用卡）' : city);
  }
  return parts.join(' | ');
}

/// 城市轨道进出站记录文本行。0x1A 站点 / 线路号在有解析回调时优先展示
/// 解析后的名称（TU 环境下与行程页 / 卡片详情页同一口径），未命中或
/// 未注入时回退原始编码（保持旧版导出内容不变）。
String _railLine(
  TransitRecord r, [
  String? Function(String? cityCode, String? rawStationId)? stationResolver,
  String? Function(String? cityCode, String? rawLineCode)? lineResolver,
]) {
  final parts = <String>['状态 ${r.statusName}'];
  if (r.entryTime != null) parts.add('进站 ${_fmt(r.entryTime!)}');
  if (r.exitTime != null) parts.add('出站 ${_fmt(r.exitTime!)}');
  final entryLine = lineResolver?.call(r.entryCityCode, r.entryLineCode?.toString());
  final exitLine = lineResolver?.call(r.exitCityCode, r.exitLineCode?.toString());
  final entryStation =
      stationResolver?.call(r.entryCityCode, r.entryStationId);
  final exitStation =
      stationResolver?.call(r.exitCityCode, r.exitStationId);
  if (entryLine != null) parts.add('进站线路 $entryLine');
  if (exitLine != null) parts.add('出站线路 $exitLine');
  if (r.entryStationId != null) {
    parts.add('进站站点 ${entryStation ?? r.entryStationId}');
  }
  if (r.exitStationId != null) {
    parts.add('出站站点 ${exitStation ?? r.exitStationId}');
  }
  if (r.entryBalanceFen != null) {
    parts.add('进站余额 ${_yuan(r.entryBalanceFen!)}');
  }
  if (r.exitAmountFen != null) parts.add('出站金额 ${_yuan(r.exitAmountFen!)}');
  return parts.join(' | ');
}

/// 公共汽电车上下车记录文本行。
String _busLine(BusTransitRecord r) {
  final parts = <String>['状态 ${r.statusName}'];
  if (r.entryTime != null) parts.add('上车 ${_fmt(r.entryTime!)}');
  if (r.exitTime != null) parts.add('下车 ${_fmt(r.exitTime!)}');
  if (r.transactionAmountFen != null) {
    parts.add('金额 ${_yuan(r.transactionAmountFen!)}');
  }
  if (r.mileage != null) parts.add('里程 ${r.mileage} 站');
  parts.add('方向 ${r.directionName}');
  return parts.join(' | ');
}

/// 金额分 → 元文本（保留两位小数）。
String _yuan(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';

/// 日期时间格式化：yyyy-MM-dd HH:mm:ss。
String _fmt(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}