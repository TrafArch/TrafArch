// D:\iteam\TrafArch\lib\core\emv\discovery\application_enumerator.dart
import '../data/aid_registry.dart';
import '../models/emv_application.dart';
import '../models/emv_discovery_result.dart';
import '../parser/ber_tlv.dart';
import '../parser/fci_parser.dart';
import '../protocol/emv_apdu.dart';
import '../transport.dart';

/// EMV 应用发现枚举器：PPSE 目录 → 候选 AID 回退 → 逐个 SELECT 解析 FCI。
/// 只读，不执行 GPO / READ RECORD；传输经 [EmvTransceive] 注入，模块无状态、
/// 可独立复用与测试。
class EmvApplicationEnumerator {
  EmvApplicationEnumerator(this._transceive);
  final EmvTransceive _transceive;

  Future<EmvDiscoveryResult> enumerate() async {
    final apps = <EmvApplication>[];
    final failures = <EmvCandidateFailure>[];
    final diagnostics = <String>[];
    final candidates = <String>[];
    var usedFallback = false;

    // 1) PPSE 目录选择
    try {
      final ppse = await _exchange(
        EmvApdu.selectByName(kEmvPpseName.codeUnits),
      );
      if (ppse.isSuccess) {
        try {
          final tree = EmvTlvParser.parse(ppse.data);
          for (final node in EmvTlvParser.flatten(tree)) {
            if (node.tag == '4F' && node.value.isNotEmpty) {
              final aid = node.valueHex;
              if (!candidates.contains(aid)) candidates.add(aid);
            }
          }
          diagnostics.add('PPSE 选择成功，发现 ${candidates.length} 个候选 AID');
        } catch (e) {
          diagnostics.add('PPSE 响应 TLV 解析失败：$e');
        }
      } else {
        diagnostics.add('PPSE SELECT 未成功，状态字 ${ppse.statusHex}');
      }
    } catch (e) {
      diagnostics.add('PPSE 通信失败：$e');
    }

    // 2) 目录为空：回退到内置候选 AID（EMV Book 3 应用选择方式二）
    if (candidates.isEmpty) {
      candidates.addAll(kEmvCandidateAids);
      usedFallback = true;
      diagnostics.add('使用内置候选 AID 回退列表；该列表并非完整清单');
    }

    // 3) 逐个 SELECT 已知 / 目录 AID，解析 FCI
    for (final aid in candidates) {
      try {
        final response =
            await _exchange(EmvApdu.selectByName(EmvTlvParser.fromHex(aid)));
        if (!response.isSuccess) {
          failures.add(EmvCandidateFailure(
            aidHex: aid,
            statusHex: response.statusHex,
            reason: 'select_rejected',
            message: 'AID $aid 选择失败，SW=${response.statusHex}',
          ));
          continue;
        }
        try {
          final app = EmvFciParser.parse(response.data, requestedAid: aid);
          if (!apps.any((a) => a.aidHex == app.aidHex)) apps.add(app);
          diagnostics.add('AID $aid 选择成功');
        } catch (e) {
          failures.add(EmvCandidateFailure(
            aidHex: aid,
            reason: 'fci_error',
            message: 'AID $aid 已选择，但 FCI 解析失败：$e',
          ));
        }
      } catch (e) {
        failures.add(EmvCandidateFailure(
          aidHex: aid,
          reason: 'io_error',
          message: 'AID $aid 通信失败：$e',
        ));
      }
    }

    return EmvDiscoveryResult(
      applications: apps,
      failures: failures,
      diagnostics: diagnostics,
      usedFallback: usedFallback,
    );
  }

  /// 单条 APDU 收发：6C（错误 Le 重发）+ 61XX（GET RESPONSE 链式，上限 8）。
  Future<EmvApduResponse> _exchange(List<int> command) async {
    var response = EmvApduResponse.parse(await _transceive(command));
    if (response.wrongLe) {
      final corrected = List<int>.from(command);
      if (corrected.isNotEmpty) corrected[corrected.length - 1] = response.sw2;
      response = EmvApduResponse.parse(await _transceive(corrected));
    }

    final data = <int>[...response.data];
    var current = response;
    var loops = 0;
    while (current.hasMoreData && loops++ < 8) {
      current = EmvApduResponse.parse(
        await _transceive(EmvApdu.getResponse(current.sw2)),
      );
      data.addAll(current.data);
    }
    if (current.hasMoreData) {
      throw StateError('GET RESPONSE 次数超过限制');
    }
    return EmvApduResponse(data, current.sw1, current.sw2);
  }
}