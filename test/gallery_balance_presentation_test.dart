import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_balance_presentation.dart';

void main() {
  test('explicit currencies use the requested code and symbol', () {
    for (final (code, amount, expected) in [
      ('CNY', '¥31.20', 'CNY ¥31.20'),
      ('JPY', '1,240 JPY', 'JPY ¥1,240'),
      ('HKD', r'HK$52.00', r'HKD $52.00'),
      ('USD', r'$0.00', r'USD $0.00'),
      ('MOP', '18.50', 'MOP ¥18.50'),
    ]) {
      final value = GalleryBalancePresentation.parse(
        amount,
        currencyCode: code,
      );
      expect(value.known, isTrue, reason: code);
      expect(value.displayText, expected, reason: code);
      expect(value.prefix, value.currencyLabel);
      expect(value.suffix, isEmpty);
    }
  });

  test('explicit codes in original text also identify all five currencies', () {
    for (final (original, expected) in [
      ('CNY 31.20', 'CNY ¥31.20'),
      ('1,240 JPY', 'JPY ¥1,240'),
      (r'HKD $52.00', r'HKD $52.00'),
      ('0.00 usd', r'USD $0.00'),
      ('mop 18.50', 'MOP ¥18.50'),
    ]) {
      final value = GalleryBalancePresentation.parse(original);
      expect(value.known, isTrue);
      expect(value.displayText, expected);
    }
  });

  test(
    'the supplied currency distinguishes identical yen and dollar symbols',
    () {
      expect(
        GalleryBalancePresentation.parse(
          '¥120',
          currencyCode: 'JPY',
        ).displayText,
        'JPY ¥120',
      );
      expect(
        GalleryBalancePresentation.parse(
          '¥120',
          currencyCode: 'CNY',
        ).displayText,
        'CNY ¥120',
      );
      expect(
        GalleryBalancePresentation.parse(
          r'$52.00',
          currencyCode: 'HKD',
        ).displayText,
        r'HKD $52.00',
      );
      expect(
        GalleryBalancePresentation.parse(
          r'$52.00',
          currencyCode: 'USD',
        ).displayText,
        r'USD $52.00',
      );
    },
  );

  test('zero, precision, grouping and negative signs are preserved', () {
    for (final (original, expectedNumber, expectedText) in [
      ('¥0.00', '0.00', 'CNY ¥0.00'),
      ('¥-31.20', '-31.20', 'CNY ¥-31.20'),
      ('−¥31.20', '−31.20', 'CNY ¥−31.20'),
      ('CNY ¥ − 31.20', '−31.20', 'CNY ¥−31.20'),
      ('+¥1,234,567.890', '+1,234,567.890', 'CNY ¥+1,234,567.890'),
    ]) {
      final value = GalleryBalancePresentation.parse(
        original,
        currencyCode: 'CNY',
      );
      expect(value.known, isTrue);
      expect(value.number, expectedNumber);
      expect(value.displayText, expectedText);
    }
  });

  test(
    'ambiguous symbols and unrecognized units retain their original text',
    () {
      for (final original in ['¥31.20', r'$52.00', '31.20', '12.30 EUR']) {
        final value = GalleryBalancePresentation.parse(original);
        expect(value.known, isTrue);
        expect(value.displayText, original);
        expect(value.currencyLabel, isNot(contains('CNY')));
        expect(value.currencyLabel, isNot(contains('USD')));
      }
      final yen = GalleryBalancePresentation.parse('¥31.20');
      expect(yen.currencyLabel, '¥');
      expect(yen.prefix, '¥');
      expect(yen.suffix, isEmpty);
      final euro = GalleryBalancePresentation.parse('12.30 EUR');
      expect(euro.prefix, isEmpty);
      expect(euro.suffix, 'EUR');
      expect(
        GalleryBalancePresentation.parse(
          '1,240 JPY',
          currencyCode: 'EUR',
        ).displayText,
        '1,240 JPY',
      );
    },
  );

  test('unavailable balances stay unavailable even with known currency', () {
    for (final original in ['暂不可用', '—', '', '余额未知']) {
      final value = GalleryBalancePresentation.parse(
        original,
        currencyCode: 'CNY',
      );
      expect(value.known, isFalse);
      expect(value.number, isEmpty);
      expect(value.currencyLabel, isEmpty);
      expect(value.displayText, original);
    }
  });
}
