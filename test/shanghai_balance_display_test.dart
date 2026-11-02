import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/transit_analysis/shanghai_balance_display.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';

void main() {
  group('ShanghaiBalanceDisplay 上海交通卡可透支余额', () {
    test('普通格式化默认不改变余额', () {
      const display = ShanghaiBalanceDisplay();
      expect(display.balanceFen(12550), 12550);
      expect(display.formatBalance(12550), '¥125.50');
    });

    test('上海交通联合专用解析器关闭开关时扣除800分', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(12550), 11750);
      expect(display.formatBalance(12550), '¥117.50');
    });

    test('上海交通联合档案卡型关闭开关时扣除800分', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        cardType: CardTypes.shanghaiTransitUnion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(11850), 11050);
    });

    test('上海城市一卡通解析器的余额已不含额度，不再扣8元', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.cityUnion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('上海城市一卡通档案余额已不含额度，不再扣8元', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        cardType: CardTypes.cityUnion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('普通TU即使有上海城市值也不套用上海额度', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.tunion,
        cardType: CardTypes.chinaTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('非上海CU不扣除上海额度', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.cityUnion,
        cardType: CardTypes.cityUnion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('缺少CU城市证据时不扣除上海额度', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.cityUnion,
        cardType: CardTypes.cityUnion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('仅有城市证据且身份未知时不调整余额', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('未确认人民币币种时保留原值', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
      );
      expect(display.balanceFen(2580), 2580);
    });

    test('港币卡不因上海身份字段扣除人民币额度', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'HKD',
      );
      expect(display.balanceFen(2580), 2580);
      expect(display.formatBalance(2580, symbol: 'HK\$'), 'HK\$25.80');
    });

    test('开启开关后包含额度并恢复原始余额', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: true,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(12550), 12550);
      expect(display.formatBalance(12550), '¥125.50');
    });

    test('零余额扣除额度后显示负八元，不截断为零', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(0), -800);
      expect(display.formatBalance(0), '¥-8.00');
    });

    test('负余额仍准确扣除八元', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(-125), -925);
      expect(display.formatBalance(-125), '¥-9.25');
    });

    test('未知余额保持未知，不生成负八元', () {
      final display = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(display.balanceFen(null), isNull);
      expect(display.formatBalance(null), isNull);
    });

    test('同一原始余额反复展示和切换设置不会累计扣减', () {
      const rawBalance = 12550;
      final excluded = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: false,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      final included = ShanghaiBalanceDisplay.forCard(
        includeShanghaiOverdraft: true,
        parserId: CardParserIds.shanghaiTunion,
        currencyCode: 'CNY',
      );
      expect(excluded.balanceFen(rawBalance), 11750);
      expect(excluded.balanceFen(rawBalance), 11750);
      expect(included.balanceFen(rawBalance), 12550);
      expect(excluded.balanceFen(rawBalance), 11750);
      expect(rawBalance, 12550);
    });
  });
}
