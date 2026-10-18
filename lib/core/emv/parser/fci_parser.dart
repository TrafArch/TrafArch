// D:\iteam\TrafArch\lib\core\emv\parser\fci_parser.dart
import '../models/emv_application.dart';
import 'ber_tlv.dart';

/// FCI（选择响应）解析：提取 AID(84)、应用标签(50)、优先名称(9F12)、优先级(87)。
class EmvFciParser {
  static EmvApplication parse(List<int> fci, {required String requestedAid}) {
    final nodes = EmvTlvParser.parse(fci);
    final all = EmvTlvParser.flatten(nodes).toList();

    String? first(String tag) {
      for (final node in all) {
        if (node.tag == tag && node.value.isNotEmpty) return node.ascii;
      }
      return null;
    }

    int? priority;
    for (final node in all) {
      if (node.tag == '87' && node.value.isNotEmpty) {
        priority = node.value.first & 0x0F;
        break;
      }
    }

    String? aid;
    for (final node in all) {
      if (node.tag == '84' && node.value.isNotEmpty) {
        aid = node.valueHex;
        break;
      }
    }

    return EmvApplication(
      aidHex: aid ?? requestedAid,
      label: first('50'),
      preferredName: first('9F12'),
      priority: priority,
      fciHex: EmvTlvParser.hex(fci),
    );
  }
}