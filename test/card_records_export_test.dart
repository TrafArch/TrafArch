// 新建文件：test/card_records_export_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/core/app_info.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/database/app_database.dart';
import 'package:transit_card_analyzer/features/card_archive/card_records_export.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_types.dart';

/// 卡片记录导出文本构建测试：验证导出头部、卡片基础字段、行程记录
/// （行程明细 / 城市轨道进出站 / 公共汽电车上下车）与异地用卡标记。
void main() {
  final exportedAt = DateTime(2026, 10, 15, 9, 30);

  group('buildCardRecordsExport 导出头部', () {
    test('包含应用名 / 版本 / 导出时间 / 卡片数量', () {
      final text = buildCardRecordsExport(
        [_savedCard()],
        exportedAt: exportedAt,
      );
      expect(text, contains('${AppInfo.appName} 卡片记录导出'));
      expect(
        text,
        contains('应用版本：${AppInfo.version}（Build ${AppInfo.buildNumber}）'),
      );
      expect(text, contains('导出时间：2026-10-15 09:30:00.000'));
      expect(text, contains('卡片数量：1'));
    });

    test('空列表：数量为 0 并提示暂无卡片', () {
      final text = buildCardRecordsExport(const [], exportedAt: exportedAt);
      expect(text, contains('卡片数量：0'));
      expect(text, contains('（暂无已保存的卡片）'));
    });

    test('未注入 exportedAt 时回退当前时间（不抛异常且含导出时间行）', () {
      final text = buildCardRecordsExport([_savedCard()]);
      expect(text, contains('导出时间：'));
    });
  });

  group('buildCardRecordsExport 卡片基础字段', () {
    test('输出名称 / 卡型 / 卡号 / 余额 / 交易条数 / 最近读取', () {
      final card = _savedCard(
        officialName: '福路通·榕城通',
        cardNumber: '3105060012345678900',
        balanceFen: 200,
        currencyCode: 'CNY',
        transactionCount: 41,
        lastReadAt: DateTime(2026, 10, 14, 21, 40).millisecondsSinceEpoch,
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('【1】福路通·榕城通'));
      expect(text, contains('卡型：交通联合卡'));
      expect(text, contains('卡号：3105060012345678900'));
      expect(text, contains('余额：¥ 2.00'));
      expect(text, contains('交易记录：41条'));
      expect(text, contains('最近读取：2026-10-14 21:40:00'));
    });

    test('自定义名称优先展示，副标题保留正式卡名', () {
      final card = _savedCard(
        officialName: '福路通·榕城通',
        customName: '上学用的卡',
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('【1】上学用的卡'));
      expect(text, contains('识别信息：福路通·榕城通 · 示例运营方 · 福州市'));
    });

    test('未读取到余额 / 交易 / 时间时使用兜底文案', () {
      final card = _savedCard(
        balanceFen: null,
        transactionCount: null,
        lastReadAt: null,
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('余额：未读取到'));
      expect(text, contains('交易记录：未记录'));
      expect(text, contains('最近读取：未记录'));
    });

    test('无行程快照：标注行程记录为无', () {
      final text = buildCardRecordsExport(
        [_savedCard()],
        exportedAt: exportedAt,
      );
      expect(text, contains('行程记录：（无）'));
    });

    test('多张卡片按顺序编号', () {
      final text = buildCardRecordsExport(
        [
          _savedCard(id: 'card-1', officialName: '甲卡'),
          _savedCard(id: 'card-2', officialName: '乙卡'),
        ],
        exportedAt: exportedAt,
      );
      expect(text, contains('卡片数量：2'));
      expect(text, contains('【1】甲卡'));
      expect(text, contains('【2】乙卡'));
    });
  });

  group('buildCardRecordsExport 行程记录', () {
    test('行程明细：时间 / 状态 / 序号 / 金额 / 余额 / 站点 / 城市', () {
      final card = _savedCard(
        sessionDataJson: CardSessionSnapshot(
          cardCityCode: '3910',
          trips: [
            TransitTrip(
              time: DateTime(2024, 5, 1, 8, 30),
              amountFen: 4660,
              overdraftLimitFen: 0,
              isConsume: true,
              typeName: '复合消费',
              sequence: 1,
              terminalId: '123456789012',
              cityName: '福州市',
              cityCode: '3910',
              lineLabel: '2号线',
              stationLabel: '苏洋',
              balanceAfterFen: 5340,
              rideStatusName: '出站',
            ),
          ],
        ).encode(),
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('行程记录（1 条）：'));
      expect(text, contains('2024-05-01 08:30:00'));
      expect(text, contains('出站'));
      expect(text, contains('序号 1'));
      expect(text, contains('-¥46.60'));
      expect(text, contains('余额 ¥53.40'));
      expect(text, contains('2号线 苏洋'));
      expect(text, contains('福州市'));
      // 同城用卡不标注异地
      expect(text, isNot(contains('福州市（异地用卡）')));
    });

    test('异地用卡：城市与发卡地不同时追加标记', () {
      final card = _savedCard(
        sessionDataJson: CardSessionSnapshot(
          cardCityCode: '3910',
          trips: [
            TransitTrip(
              time: DateTime(2024, 5, 1, 8, 30),
              amountFen: 300,
              overdraftLimitFen: 0,
              isConsume: true,
              typeName: '消费',
              sequence: 2,
              terminalId: '123456789012',
              cityName: '厦门市',
              cityCode: '3502',
            ),
          ],
        ).encode(),
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('厦门市（异地用卡）'));
    });

    test('城市轨道进出站记录：状态 / 时间 / 站点 / 余额 / 金额', () {
      final card = _savedCard(
        sessionDataJson: CardSessionSnapshot(
          railRecord: TransitRecord(
            statusCode: 0x02,
            entryStationId: '0800190030000123',
            exitStationId: '0800190030000456',
            entryTime: DateTime(2026, 8, 8, 9, 6, 2),
            exitTime: DateTime(2026, 8, 8, 9, 12, 31),
            entryBalanceFen: 2500,
            exitAmountFen: 300,
          ),
        ).encode(),
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('城市轨道交通 · 进出站记录：'));
      expect(text, contains('状态 出闸'));
      expect(text, contains('进站 2026-08-08 09:06:02'));
      expect(text, contains('出站 2026-08-08 09:12:31'));
      expect(text, contains('进站站点 0800190030000123'));
      expect(text, contains('出站站点 0800190030000456'));
      expect(text, contains('进站余额 ¥25.00'));
      expect(text, contains('出站金额 ¥3.00'));
    });

    test('公共汽电车上下车记录：状态 / 时间 / 金额 / 里程 / 方向', () {
      final card = _savedCard(
        sessionDataJson: CardSessionSnapshot(
          busRecord: BusTransitRecord(
            statusCode: 0x00,
            entryTime: DateTime(2026, 8, 8, 9, 6, 2),
            exitTime: DateTime(2026, 8, 8, 9, 12, 31),
            transactionAmountFen: 300,
            mileage: 5,
            directionCode: 0x00,
          ),
        ).encode(),
      );
      final text = buildCardRecordsExport([card], exportedAt: exportedAt);
      expect(text, contains('公共汽电车 · 上下车记录：'));
      expect(text, contains('状态 初始值'));
      expect(text, contains('上车 2026-08-08 09:06:02'));
      expect(text, contains('下车 2026-08-08 09:12:31'));
      expect(text, contains('金额 ¥3.00'));
      expect(text, contains('里程 5 站'));
      expect(text, contains('方向 未知方向'));
    });
  });
}

SavedCard _savedCard({
  String id = 'card-1',
  String cardType = CardTypes.chinaTunion,
  String? officialName = '福路通·榕城通',
  String? customName,
  String? issuerName = '示例运营方',
  String? cityName = '福州市',
  String? cardNumber = '3105060012345678900',
  int? balanceFen,
  String? currencyCode,
  int? transactionCount,
  String? sessionDataJson,
  int? lastReadAt = 1000,
}) =>
    SavedCard(
      id: id,
      cardFingerprint: 'tunion:1:2',
      cardType: cardType,
      officialName: officialName,
      customName: customName,
      issuerName: issuerName,
      cityName: cityName,
      identificationSource: CardIdentificationSources.cardCatalog,
      identificationConfidence: 0.85,
      cardNumber: cardNumber,
      balanceFen: balanceFen,
      currencyCode: currencyCode,
      transactionCount: transactionCount,
      sessionDataJson: sessionDataJson,
      cardImagePath: null,
      lastReadAt: lastReadAt,
      createdAt: 900,
      updatedAt: 1000,
    );
