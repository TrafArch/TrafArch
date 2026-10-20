import 'dart:typed_data';

import '../../../core/emv/discovery/application_enumerator.dart';
import '../../../core/emv/models/emv_application.dart';
import '../data/transport/recording_card_transport.dart';
import '../domain/interfaces/card_parser.dart';
import '../domain/interfaces/card_transport.dart';
import '../domain/models/bank_card_result.dart';
import '../domain/models/card_application.dart';
import '../domain/models/parse_issue.dart';

// 结果模型随协调器一并导出：页面引用本文件即可使用，无需逐层深入 domain。
export '../domain/models/bank_card_result.dart';
export '../domain/models/card_application.dart';

/// 银行卡只读分析协调器：控制流程、枚举应用、按证据选择解析器、汇总异常。
/// 页面不直接发送 APDU，统一经由本协调器。
/// 应用发现（PPSE / 候选 AID / FCI）委托独立模块 `core/emv`；
/// EMV / PBOC 的读取适配（PDOL 组包、83 00 回退、77 / 80 模板、AFL 定位）
/// 由解析器内部共享流程完成，本协调器只负责协议族选择。
class BankCardAnalyzer {
  final List<CardParser> parsers;
  final String parserVersion;

  BankCardAnalyzer(this.parsers, {this.parserVersion = '0.2.0'});

  Future<BankCardResult> analyze(CardTransport transport) async {
    final recording = RecordingCardTransport(transport);
    final issues = <ParseIssue>[];

    // 1. 应用枚举：委托独立 EMV 发现模块（经记录型通道，保留 APDU 轨迹）
    final List<EmvApplication> discovered;
    final bool usedFallback;
    try {
      Future<List<int>> emvTransceive(List<int> cmd) async =>
          recording.transceive(Uint8List.fromList(cmd));
      final result = await EmvApplicationEnumerator(emvTransceive).enumerate();
      discovered = result.applications;
      usedFallback = result.usedFallback;
      for (final failure in result.failures) {
        // An absent AID in the fallback list is expected, unlike a failed AID
        // explicitly advertised by PPSE. Retain all other failure evidence.
        if (usedFallback &&
            failure.reason == 'select_rejected' &&
            failure.statusHex == '6A82') {
          continue;
        }
        issues.add(
          ParseIssue(
            stage: 'enumeration',
            code: failure.reason,
            message: failure.message,
          ),
        );
      }
    } catch (e) {
      // NFC 通信异常单独归为 nfc_io_error，不与「卡片不支持」混为一谈。
      issues.add(
        ParseIssue(
          stage: 'enumeration',
          code: 'nfc_io_error',
          message: 'NFC 通信异常，未能完成应用枚举：$e',
        ),
      );
      return BankCardResult(
        protocolFamily: BankCardProtocolFamily.emv,
        analyzedAt: DateTime.now(),
        parserVersion: parserVersion,
        status: BankCardStatus.enumerationFailed,
        traces: recording.traces,
        issues: issues,
      );
    }

    if (usedFallback) {
      issues.add(
        const ParseIssue(
          stage: 'ppse',
          code: 'fallback_used',
          message: 'PPSE 不可用，已回退到候选 AID 枚举',
        ),
      );
    }

    final applications = discovered.map(_toCardApplication).toList();
    final selected = applications.isNotEmpty;
    if (!selected) {
      issues.add(
        const ParseIssue(
          stage: 'enumeration',
          code: 'no_candidate_aid',
          message: 'PPSE 与候选 AID 均未匹配到任何应用',
        ),
      );
    }

    final parsed = <ParsedApplication>[];
    if (selected) {
      // 2/3/4. 逐应用按证据选择解析器并读取（GPO / 记录读取由解析器完成）
      for (final app in applications) {
        final parser = _chooseParser(app);
        if (parser == null) {
          issues.add(
            ParseIssue(
              stage: 'dispatch',
              code: 'no_parser',
              message: '应用 ${app.aidHex} 无适用解析器',
            ),
          );
          continue;
        }
        try {
          final result = await parser.parse(app, recording);
          parsed.add(result);
        } catch (e) {
          issues.add(
            ParseIssue(
              stage: 'parse',
              code: 'exception',
              message: '${parser.parserId} 解析异常：$e',
            ),
          );
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

  /// 发现模块产物 → 特性层应用模型：下游解析器会重新 SELECT + 读取记录。
  CardApplication _toCardApplication(EmvApplication a) => CardApplication(
    aidHex: a.aidHex,
    label: a.displayName == a.aidHex ? null : a.displayName,
    selected: true,
  );

  CardParser? _chooseParser(CardApplication app) {
    // Specific application rules win independently of registration order.
    // EMV remains the fallback for an application without a more specific rule.
    for (final p in parsers) {
      if (p.parserId != 'emv' && p.supports(app)) return p;
    }
    for (final p in parsers) {
      if (p.supports(app)) return p;
    }
    return null;
  }

  String _dominantFamily(List<ParsedApplication> parsed) {
    final hasPboc = parsed.any((p) => p.parserId == 'pboc');
    final hasEmv = parsed.any((p) => p.parserId == 'emv');
    if (hasPboc && hasEmv) return BankCardProtocolFamily.mixed;
    if (hasPboc) {
      return BankCardProtocolFamily.pboc;
    }
    return BankCardProtocolFamily.emv;
  }
}
