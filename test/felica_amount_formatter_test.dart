import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';

void main() {
  test('yen wallet always formats integer yen with an unambiguous prefix', () {
    const wallet = FelicaWallet(
      walletId: 'suica.sf',
      name: 'Suica',
      currency: 'JPY',
      // Captured metadata must not turn whole yen into cents.
      fractionDigits: 2,
      balanceMinorUnits: 12345,
      readState: FelicaWalletReadState.success,
    );
    expect(wallet.balanceText, 'JP￥12,345');
    expect(wallet.formatAmount(0), 'JP￥0');
    expect(wallet.formatAmount(1), 'JP￥1');
    expect(wallet.formatAmount(-500), '-JP￥500');
    expect(wallet.formatAmount(1234567), 'JP￥1,234,567');
  });

  test('yen formatting preserves an imported minimum signed integer', () {
    const wallet = FelicaWallet(
      walletId: 'suica.sf',
      name: 'Suica',
      currency: 'JPY',
    );
    expect(
      wallet.formatAmount(-9223372036854775807 - 1),
      '-JP￥9,223,372,036,854,775,808',
    );
  });

  test('yuan and Hong Kong dollar wallets retain their decimal units', () {
    const yuan = FelicaWallet(
      walletId: 'lingnan.rmb',
      name: '岭南通',
      currency: 'CNY',
      fractionDigits: 2,
    );
    const hongKongDollar = FelicaWallet(
      walletId: 'octopus.main',
      name: '八达通',
      currency: 'HKD',
      fractionDigits: 2,
    );
    expect(yuan.formatAmount(12345), '¥123.45');
    expect(yuan.formatAmount(-500), '-¥5.00');
    expect(hongKongDollar.formatAmount(12345), 'HK\$123.45');
    expect(hongKongDollar.formatAmount(-500), '-HK\$5.00');
  });
}
