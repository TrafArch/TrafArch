import '../data/aid_registry.dart';
import '../models/emv_application.dart';
import '../models/emv_discovery_result.dart';
import '../parser/ber_tlv.dart';
import '../parser/fci_parser.dart';
import '../protocol/emv_apdu.dart';
import '../protocol/read_only_exchange.dart';
import '../transport.dart';
import '../../../iso7816/apdu_exchange_engine.dart';
import '../../../transport/transport_failure.dart';

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
    final supplemental = <String>{};
    var usedFallback = false;
    TransportFailure? transportFailure;
    EmvDiscoveryResult result() => EmvDiscoveryResult(
      applications: List.unmodifiable(apps),
      failures: List.unmodifiable(failures),
      diagnostics: List.unmodifiable(diagnostics),
      usedFallback: usedFallback,
      transportFailure: transportFailure,
    );

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
    } catch (e, stack) {
      diagnostics.add('PPSE 通信失败：$e');
      transportFailure = e is ApduTransportException
          ? e.result.failure
          : TransportFailure.from(e, stack);
      failures.add(
        EmvCandidateFailure(
          aidHex: kEmvPpseName,
          reason: 'io_error',
          message: 'PPSE 通信失败：$e',
        ),
      );
      return result();
    }

    // 2) 目录为空：回退到内置候选 AID（EMV Book 3 应用选择方式二）
    if (candidates.isEmpty) {
      candidates.addAll(kEmvCandidateAids);
      usedFallback = true;
      diagnostics.add('使用内置候选 AID 回退列表；该列表并非完整清单');
    } else if (!candidates.any(isPbocAid)) {
      // 2b) 一芯双应用卡：PPSE 只列出境外应用时，补充探测境内 PBOC AID。
      for (final aid in kPbocSupplementalAids) {
        if (candidates.contains(aid)) continue;
        candidates.add(aid);
        supplemental.add(aid);
      }
      if (supplemental.isNotEmpty) {
        diagnostics.add('PPSE 未列出 PBOC AID，补充探测 ${supplemental.join(', ')}');
      }
    }

    // 3) 逐个 SELECT 已知 / 目录 AID，解析 FCI
    for (final aid in candidates) {
      final isSupplemental = supplemental.contains(aid);
      try {
        final response = await _exchange(
          EmvApdu.selectByName(EmvTlvParser.fromHex(aid)),
        );
        if (!response.isSuccess) {
          // 补充探测的 AID 不在 PPSE 中，6A82 表示卡片未提供该应用，
          // 属于预期结果：保留诊断，不把整次读取标记为部分失败。
          if (isSupplemental && response.statusHex == '6A82') {
            diagnostics.add('补充探测 AID $aid 未找到（SW=6A82）');
            continue;
          }
          failures.add(
            EmvCandidateFailure(
              aidHex: aid,
              statusHex: response.statusHex,
              reason: 'select_rejected',
              message: 'AID $aid 选择失败，SW=${response.statusHex}',
            ),
          );
          continue;
        }
        try {
          final app = EmvFciParser.parse(response.data, requestedAid: aid);
          if (!apps.any((a) => a.aidHex == app.aidHex)) apps.add(app);
          diagnostics.add('AID $aid 选择成功');
        } catch (e) {
          // SELECT succeeded. Optional/malformed FCI must not hide this AID;
          // the application reader will reselect it and retain its own evidence.
          if (!apps.any((a) => a.aidHex == aid)) {
            apps.add(
              EmvApplication(
                aidHex: aid,
                requestedAid: aid,
                fciHex: EmvTlvParser.hex(response.data),
              ),
            );
          }
          failures.add(
            EmvCandidateFailure(
              aidHex: aid,
              reason: 'fci_error',
              message: 'AID $aid 已选择，但 FCI 解析失败：$e',
            ),
          );
        }
      } catch (e, stack) {
        failures.add(
          EmvCandidateFailure(
            aidHex: aid,
            reason: 'io_error',
            message: 'AID $aid 通信失败：$e',
          ),
        );
        transportFailure = e is ApduTransportException
            ? e.result.failure
            : TransportFailure.from(e, stack);
        break; // Preserve earlier applications; never probe after terminal I/O.
      }
    }

    return result();
  }

  Future<EmvApduResponse> _exchange(List<int> command) =>
      exchangeReadOnly(_transceive, command);
}
