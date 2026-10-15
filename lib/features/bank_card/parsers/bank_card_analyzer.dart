import 'dart:typed_data';

import '../data/apdu/apdu_command.dart';
import '../data/apdu/apdu_response.dart';
import '../data/tlv/ber_tlv_decoder.dart';
import '../data/tlv/hex_codec.dart';
import '../data/transport/recording_card_transport.dart';
import '../domain/interfaces/card_parser.dart';
import '../domain/interfaces/card_transport.dart';
import '../domain/models/apdu_trace.dart';
import '../domain/models/bank_card_result.dart';
import '../domain/models/card_application.dart';
import '../domain/models/parse_issue.dart';
import '../domain/models/tlv_node.dart';

// 结果模型随协调器一并导出：页面引用本文件即可使用，无需逐层深入 domain。
export '../domain/models/bank_card_result.dart';
export '../domain/models/card_application.dart';

/// PPSE（支付系统目录，2PAY.SYS.DDF01）AID。
final Uint8List _ppseAid = Uint8List.fromList(
  '2PAY.SYS.DDF01'.codeUnits,
);

/// 银行卡只读分析协调器：控制流程、枚举应用、按证据选择解析器、汇总异常。
/// 页面不直接发送 APDU，统一经由本协调器。
/// EMV / PBOC 的读取逻辑适配（PDOL 组包、83 00 回退、77 / 80 响应模板、
/// AFL 定位）由解析器内部的共享流程自动完成，本协调器只负责协议族选择。
class BankCardAnalyzer {
  /// PBOC 优先于 EMV（更具体的规则先判定）。
  final List<CardParser> parsers;
  final String parserVersion;

  BankCardAnalyzer(this.parsers, {this.parserVersion = '0.2.0'});

  Future<BankCardResult> analyze(CardTransport transport) async {
    final recording = RecordingCardTransport(transport);
    final issues = <ParseIssue>[];
    final applications = <CardApplication>[];

    // 1. 枚举应用（SELECT PPSE → 目录）
    final selected = await _enumerate(recording, applications, issues);

    final parsed = <ParsedApplication>[];
    if (selected) {
      // 2/3/4. 逐应用按证据选择解析器并读取
      for (final app in applications) {
        final parser = _chooseParser(app);
        if (parser == null) {
          issues.add(ParseIssue(
            stage: 'dispatch',
            code: 'no_parser',
            message: '应用 ${app.aidHex} 无适用解析器',
          ));
          continue;
        }
        try {
          final result = await parser.parse(app, recording);
          parsed.add(result);
        } catch (e) {
          issues.add(ParseIssue(
            stage: 'parse',
            code: 'exception',
            message: '${parser.parserId} 解析异常：$e',
          ));
        }
      }
    }

    final hasData = parsed.any((p) => p.hasData);
    final BankCardStatus status;
    if (!selected) {
      status = BankCardStatus.enumerationFailed;
    } else if (!hasData) {
      status = BankCardStatus.noCard;
    } else if (issues.isEmpty && parsed.every((p) => p.issues.isEmpty)) {
      status = BankCardStatus.success;
    } else {
      status = BankCardStatus.partial;
    }

    return BankCardResult(
      protocolFamily: _dominantFamily(parsed),
      analyzedAt: DateTime.now(),
      parserVersion: parserVersion,
      status: status,
      applications: parsed,
      traces: recording.traces,
      issues: issues,
    );
  }

  /// SELECT PPSE 并解析目录，得到应用列表；成功返回 true。
  Future<bool> _enumerate(
    RecordingCardTransport transport,
    List<CardApplication> out,
    List<ParseIssue> issues,
  ) async {
    final resp = await _exchange(transport, ApduCommand.select(_ppseAid));
    if (resp.data.isEmpty && !resp.isSuccess) {
      issues.add(ParseIssue(
        stage: 'ppse',
        code: resp.statusWord == 0 ? 'no_response' : _sw(resp),
        message: 'PPSE 目录枚举未成功（卡片可能不支持或访问受限）',
      ));
      return false;
    }
    final roots = BerTlvDecoder.decode(resp.data);
    // 目录条目：tag 61（EMV）/ 70 容器内的 61
    for (final entry in BerTlvDecoder.findAll(roots, '61')) {
      final aid = BerTlvDecoder.findFirst(entry.children, '4F');
      if (aid == null) continue;
      final label = BerTlvDecoder.findFirst(entry.children, '50');
      out.add(CardApplication(
        aidHex: HexCodec.encode(aid.value),
        label: label == null ? null : _ascii(label.value),
        directoryTags: entry.children.map(_toNodeShallow).toList(),
      ));
    }
    if (out.isEmpty) {
      issues.add(const ParseIssue(
        stage: 'ppse',
        code: 'empty_directory',
        message: 'PPSE 返回目录为空',
      ));
      return false;
    }
    return true;
  }

  CardParser? _chooseParser(CardApplication app) {
    for (final p in parsers) {
      if (p.supports(app)) return p;
    }
    return null;
  }

  String _dominantFamily(List<ParsedApplication> parsed) {
    if (parsed.any((p) => p.parserId == 'pboc')) {
      return BankCardProtocolFamily.pboc;
    }
    return BankCardProtocolFamily.emv;
  }

  TlvNode _toNodeShallow(RawTlv r) => TlvNode(
        tagHex: r.tagHex,
        length: r.length,
        rawValue: r.value,
        children: r.children.map(_toNodeShallow).toList(),
      );

  Future<ApduResponse> _exchange(
    RecordingCardTransport transport,
    Uint8List apdu,
  ) async {
    final bytes = await transport.transceive(apdu);
    if (bytes.length < 2) {
      return ApduResponse(data: Uint8List(0), sw1: 0, sw2: 0);
    }
    return ApduResponse.fromBytes(bytes);
  }

  /// 目录标签（ANS 文本）转可读字符串：空 / 全不可打印时返回 null（不猜测）。
  static String? _ascii(Uint8List b) {
    final s = String.fromCharCodes(
      b.where((c) => c >= 0x20 && c < 0x7F),
    ).trim();
    return s.isEmpty ? null : s;
  }

  static String _sw(ApduResponse r) =>
      r.statusWord.toRadixString(16).padLeft(4, '0').toUpperCase();
}
