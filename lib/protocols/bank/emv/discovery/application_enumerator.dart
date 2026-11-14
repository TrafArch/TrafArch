import '../../../iso7816/apdu_exchange_engine.dart';
import '../../../transport/transport_failure.dart';
import '../../data/apdu/apdu_command.dart';
import '../data/aid_registry.dart';
import '../models/emv_application.dart';
import '../models/emv_discovery_result.dart';
import '../parser/ber_tlv.dart';
import '../parser/fci_parser.dart';
import '../protocol/emv_apdu.dart';
import '../protocol/read_only_exchange.dart';
import '../transport.dart';

/// EMV 应用发现枚举器：PPSE → PSE 目录记录 → 内置候选 AID。
/// 仅选择目录及应用，PSE 的 READ RECORD 由目录 FCI 指定 SFI。
class EmvApplicationEnumerator {
  EmvApplicationEnumerator(this._transceive);
  final EmvTransceive _transceive;

  static const int _maxDirectoryRecords = 254;

  Future<EmvDiscoveryResult> enumerate() async {
    final apps = <EmvApplication>[];
    final failures = <EmvCandidateFailure>[];
    final diagnostics = <String>[];
    final candidates = <String>[];
    final directoryAids = <String>{};
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

    void addDirectoryAid(EmvTlv node) {
      final aid = node.valueHex;
      if (!directoryAids.add(aid)) return;
      if (node.value.length < 5 || node.value.length > 16) {
        failures.add(
          EmvCandidateFailure(
            aidHex: aid,
            reason: 'invalid_aid',
            message:
                '目录候选 AID ${aid.isEmpty ? '（空）' : aid} 无效，'
                '长度应为 5–16 字节',
          ),
        );
        return;
      }
      candidates.add(aid);
    }

    var directoryName = kEmvPpseName;
    // 1) PPSE 目录选择
    try {
      final ppse = await _exchange(
        EmvApdu.selectByName(kEmvPpseName.codeUnits),
      );
      if (ppse.isSuccess) {
        try {
          final tree = EmvTlvParser.parse(ppse.data);
          for (final node in EmvTlvParser.flatten(tree)) {
            if (node.tag == '4F') addDirectoryAid(node);
          }
          diagnostics.add('PPSE 选择成功，发现 ${candidates.length} 个候选 AID');
        } catch (e) {
          diagnostics.add('PPSE 响应 TLV 解析失败：$e');
        }
      } else {
        diagnostics.add('PPSE SELECT 未成功，状态字 ${ppse.statusHex}');
      }

      // PSE 将候选 AID 存在独立目录记录，不能只看 SELECT 的 FCI。
      if (candidates.isEmpty) {
        directoryName = kEmvPseName;
        await _readPseDirectory(diagnostics, addDirectoryAid);
        diagnostics.add('PSE 目录发现 ${candidates.length} 个候选 AID');
      }
    } catch (e, stack) {
      final message = '$directoryName 目录通信失败：$e';
      diagnostics.add(message);
      transportFailure = e is ApduTransportException
          ? e.result.failure
          : TransportFailure.from(e, stack);
      failures.add(
        EmvCandidateFailure(
          aidHex: directoryName,
          reason: 'io_error',
          message: message,
        ),
      );
      return result();
    }

    void addBuiltInCandidates() {
      final seen = candidates.toSet();
      final remaining = kEmvCandidateAids.where((aid) => !seen.contains(aid));
      candidates.addAll(remaining);
      usedFallback = true;
      diagnostics.add('使用内置候选 AID 回退列表；该列表并非完整清单');
    }

    // 2) 目录没有有效 AID：回退到内置候选 AID。
    if (candidates.isEmpty) {
      addBuiltInCandidates();
    } else if (!candidates.any(isPbocAid)) {
      // 2b) 一芯双应用卡：目录只列出境外应用时，补充探测境内 PBOC AID。
      for (final aid in kPbocSupplementalAids) {
        if (candidates.contains(aid)) continue;
        candidates.add(aid);
        supplemental.add(aid);
      }
      if (supplemental.isNotEmpty) {
        diagnostics.add('目录未列出 PBOC AID，补充探测 ${supplemental.join(', ')}');
      }
    }

    // 3) 逐个 SELECT 已知 / 目录 AID，解析 FCI。
    // 新增的 PSE 路径无法选中应用时保留原有的内置候选探测。
    var index = 0;
    while (index < candidates.length ||
        (!usedFallback && directoryName == kEmvPseName && apps.isEmpty)) {
      if (index == candidates.length) {
        addBuiltInCandidates();
        if (index == candidates.length) break;
      }
      final aid = candidates[index++];
      final isSupplemental = supplemental.contains(aid);
      final List<int> aidBytes;
      try {
        aidBytes = EmvTlvParser.fromHex(aid);
        if (aidBytes.length < 5 || aidBytes.length > 16) {
          throw const FormatException('AID 长度应为 5–16 字节');
        }
      } on FormatException catch (error) {
        // 静态候选表中的无效 AID 同样不能中断应用探测。
        failures.add(
          EmvCandidateFailure(
            aidHex: aid,
            reason: 'invalid_aid',
            message: '候选 AID 格式无效：$aid（$error）',
          ),
        );
        continue;
      }
      try {
        final response = await _exchange(EmvApdu.selectByName(aidBytes));
        if (!response.isSuccess) {
          // 补充探测的 AID 未被目录列出，6A82 表示卡片未提供该应用，
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
              advertisedByDirectory: !usedFallback && !isSupplemental,
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

  Future<void> _readPseDirectory(
    List<String> diagnostics,
    void Function(EmvTlv) addDirectoryAid,
  ) async {
    final pse = await _exchange(EmvApdu.selectByName(kEmvPseName.codeUnits));
    if (!pse.isSuccess) {
      diagnostics.add('PSE SELECT 未成功，状态字 ${pse.statusHex}');
      return;
    }

    final int sfi;
    try {
      final sfiNodes = [
        for (final fci in EmvTlvParser.parse(
          pse.data,
        ).where((n) => n.tag == '6F'))
          for (final a5 in fci.children.where((n) => n.tag == 'A5'))
            ...a5.children.where((n) => n.tag == '88'),
      ];
      if (sfiNodes.length != 1 || sfiNodes.single.value.length != 1) {
        diagnostics.add('PSE FCI 未提供有效的目录 SFI（标签 88）');
        return;
      }
      sfi = sfiNodes.single.value.single;
      if (sfi < 1 || sfi > 10) {
        diagnostics.add('PSE FCI 目录 SFI 超出 1–10 范围');
        return;
      }
    } on FormatException catch (e) {
      diagnostics.add('PSE 响应 TLV 解析失败：$e');
      return;
    }

    for (var record = 1; record <= _maxDirectoryRecords; record++) {
      final response = await _exchange(ApduCommand.readRecord(sfi, record));
      if (!response.isSuccess) {
        if (response.statusWord != 0x6A83) {
          diagnostics.add('PSE 目录记录 $record 读取失败，SW=${response.statusHex}');
        }
        return;
      }
      try {
        for (final root in EmvTlvParser.parse(response.data)) {
          if (root.tag != '70') continue;
          for (final entry in root.children.where((n) => n.tag == '61')) {
            for (final node in entry.children.where((n) => n.tag == '4F')) {
              addDirectoryAid(node);
            }
          }
        }
      } on FormatException catch (e) {
        diagnostics.add('PSE 目录记录 $record TLV 解析失败：$e');
      }
    }
    diagnostics.add('达到 PSE 目录记录读取上限 $_maxDirectoryRecords');
  }

  Future<EmvApduResponse> _exchange(List<int> command) =>
      exchangeReadOnly(_transceive, command);
}
