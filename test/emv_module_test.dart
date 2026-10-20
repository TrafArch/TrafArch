// D:\iteam\TrafArch\test\emv_module_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/emv/discovery/application_enumerator.dart';
import 'package:transit_card_analyzer/core/emv/parser/ber_tlv.dart';

void main() {
  test('解析嵌套 FCI，提取 AID 与标签', () {
    // Visa FCI：6F(14) -> 84(07) A0000000031010 / A5(09){50(04)VISA,87(01)01}
    final bytes = EmvTlvParser.fromHex(
      '6F148407A0000000031010A509500456495341870101',
    );
    final flat = EmvTlvParser.flatten(EmvTlvParser.parse(bytes)).toList();
    expect(
      flat.any((n) => n.tag == '84' && n.valueHex == 'A0000000031010'),
      isTrue,
    );
    expect(flat.any((n) => n.tag == '50' && n.ascii == 'VISA'), isTrue);
  });

  test('截断的 TLV 抛 FormatException', () {
    expect(() => EmvTlvParser.parse([0x5A, 0x04, 0x01]), throwsFormatException);
  });

  test('FCI padding does not discard both directory applications', () async {
    final responses = [
      '6F2D840E325041592E5359532E4444463031A51BBF0C1861094F07A0000000041010610A4F08A000000333010101009000',
      '6F0A8407A0000000041010009000',
      '6F0B8408A000000333010101009000',
    ];
    var index = 0;
    final result = await EmvApplicationEnumerator((_) async {
      if (index >= responses.length) return [0x6A, 0x82];
      return EmvTlvParser.fromHex(responses[index++]);
    }).enumerate();
    expect(result.usedFallback, isFalse);
    expect(result.applications.map((a) => a.aidHex), [
      'A0000000041010',
      'A000000333010101',
    ]);
  });

  test('enumeration GET RESPONSE handles a corrected Le', () async {
    final commands = <String>[];
    final responses = [
      '6110',
      '6C22',
      '6F20840E325041592E5359532E4444463031A50EBF0C0B61094F07A00000000410109000',
      '6F098407A00000000410109000',
    ];
    var index = 0;
    final result = await EmvApplicationEnumerator((command) async {
      commands.add(EmvTlvParser.hex(command));
      if (index >= responses.length) return [0x6A, 0x82];
      return EmvTlvParser.fromHex(responses[index++]);
    }).enumerate();
    expect(result.usedFallback, isFalse);
    expect(result.applications, hasLength(1));
    expect(commands.take(3), [
      '00A404000E325041592E5359532E444446303100',
      '00C0000010',
      '00C0000022',
    ]);
  });

  test('PPSE 不可用时回退候选 AID 并解析 FCI', () async {
    // 银联借记 FCI：6F(1B) -> 84(08) A000000333010101 / A5(0F){50 PBOC DEBIT,87 01}
    final fciUnionPay = EmvTlvParser.fromHex(
      '6F1B8408A000000333010101A50F500A50424F43204445424954870101',
    );

    Future<List<int>> fake(List<int> cmd) async {
      final hex = EmvTlvParser.hex(cmd);
      if (hex.contains('325041592E5359532E4444463031')) {
        return [0x6A, 0x82]; // PPSE(2PAY.SYS.DDF01) 不支持 → 触发回退
      }
      if (hex.contains('A000000333010101')) {
        return [...fciUnionPay, 0x90, 0x00]; // 银联 AID 命中
      }
      return [0x6A, 0x82];
    }

    final result = await EmvApplicationEnumerator(fake).enumerate();
    expect(result.usedFallback, isTrue);
    expect(
      result.applications.any((a) => a.aidHex == 'A000000333010101'),
      isTrue,
    );
  });
}
