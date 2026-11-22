import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/application/card_provider_resolver.dart';
import 'package:transit_card_analyzer/features/reference_data/data/card_provider_registry_asset.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/card_provider_registry.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final registry = CardProviderRegistry.fromJson({
    'format_version': 1,
    'chip_providers': [
      {'code': '0004', 'name': '恩智浦半导体（上海）', 'source_row': 4},
      {'code': '0081', 'name': '北京中电华大电子设计', 'source_row': 16},
    ],
    'ic_card_providers': [
      {'code': '8631', 'name': '深圳市澄天伟业', 'source_row': 38},
      {'code': '8631', 'name': '芯昇科技', 'source_row': 39},
      {'code': '8660', 'name': '东信和平-EP', 'source_row': 64},
    ],
  });
  final resolver = CardProviderResolver(registry);

  test(
    'bundled registry preserves every source row and duplicate code',
    () async {
      final bundled = await CardProviderRegistryAsset.load(rootBundle);

      expect(bundled.sourceRows, 149);
      expect(bundled.chipProviderCount, 36);
      expect(bundled.icCardProviderCount, 113);
      expect(bundled.lookup(CardProviderKind.chip, '0081').names, [
        '北京中电华大电子设计',
      ]);
      expect(
        bundled.lookup(CardProviderKind.icCard, '8631').state,
        CardProviderLookupState.ambiguous,
      );
    },
  );

  NfcScanResult tag({String? historicalBytes, String? ats}) => NfcScanResult(
    uid: '0102030405060708',
    technologies: const ['IsoDep'],
    historicalBytes: historicalBytes,
    ats: ats,
    isoDepConnected: true,
    timestamp: DateTime(2026, 11, 22),
  );

  test('Android MT history yields both names from the bundled registry', () async {
    final bundled = CardProviderResolver(await CardProviderRegistryAsset.load(rootBundle));
    // Published Changchun card prefix. The serial in the tail is synthetic.
    const history = '4d 54 00 8c 00 30 86 65 12 34 56 78';
    final result = bundled.resolve(tag(historicalBytes: history));
    expect(result.chip.displayText, '北京清华同方微电子（008C）');
    expect(result.icCard.displayText, '金邦达（8665）');
    expect(bundled.resolve(tag(ats: history)).chip.code, '008C');
  });

  test('MT preserves each HEX code even when neither is registered', () {
    final missing = resolver.resolve(tag(historicalBytes: '4D5400FE002086EE12345678'));
    expect(missing.chip.displayText, '未知（00FE）');
    expect(missing.icCard.displayText, '未知（86EE）');
    final partial = resolver.resolve(tag(historicalBytes: '4D5400040000000012345678'));
    expect(partial.chip.state, CardProviderFieldState.found);
    expect(partial.icCard.displayText, '未知（0000）');
  });

  test('PC/SC wrapped MT history uses the positions inside the history', () {
    // Beijing transport card envelope from pcsc-tools/smartcard_list.txt.
    final result = resolver.resolve(tag(historicalBytes: '3B 8A 80 01 4D 54 00 05 00 20 86 64 00 01 D4'));
    expect(result.chip.code, '0005');
    expect(result.icCard.code, '8664');
  });

  test('unrelated, malformed and truncated histories cannot supply MT codes', () {
    for (final value in [
      '4D 54 43 4F 53 73 02 05 04', // MTCOS
      '4D 54 00 81 00 30 86',
      '4D 54 XX 00 81 00 30 86 60 00 00 00 00',
      '80 4D 54 00 81 00 30 86 60 00 00 00 00',
      '80 00 81 54 31 00 86 60',
    ]) {
      expect(resolver.resolve(tag(historicalBytes: value)).hasProviderCode, isFalse, reason: value);
    }
  });

  test('resolves both providers from the known ATR layout', () {
    final result = resolver.resolve(
      tag(
        historicalBytes: '3B 6D 00 00 00 81 54 31 00 86 60 11 08 16 00 00 00',
      ),
    );

    expect(result.chip.state, CardProviderFieldState.found);
    expect(result.chip.code, '0081');
    expect(result.chip.displayText, '北京中电华大电子设计（0081）');
    expect(result.icCard.state, CardProviderFieldState.found);
    expect(result.icCard.code, '8660');
    expect(result.icCard.displayText, '东信和平-EP（8660）');
  });

  test('resolves a historical block whose chip high byte was stripped', () {
    final result = resolver.resolve(
      tag(historicalBytes: '81 54 31 00 86 60 11 08 16'),
    );

    expect(result.chip.code, '0081');
    expect(result.icCard.code, '8660');
  });

  test('keeps duplicate registry codes explicitly ambiguous', () {
    final result = resolver.resolve(
      tag(
        historicalBytes: '3B 8D 80 01 00 81 54 31 00 86 31 11 08 16 00 00 00',
      ),
    );

    expect(result.icCard.state, CardProviderFieldState.ambiguous);
    expect(result.icCard.displayText, contains('深圳市澄天伟业 / 芯昇科技'));
    expect(result.icCard.displayText, contains('备案表重码'));
  });

  test('does not guess without a structural reset-information match', () {
    final result = resolver.resolve(
      tag(historicalBytes: '00 04 AA BB CC DD 86 60'),
    );

    expect(result.chip.displayText, '未提供');
    expect(result.icCard.displayText, '未提供');
  });
}
