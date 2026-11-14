import 'dart:typed_data';

import '../emv/protocol/read_only_exchange.dart';
import '../data/apdu/apdu_command.dart';
import '../data/apdu/apdu_response.dart';
import '../data/dictionary/json_tag_dictionary.dart';
import '../data/tlv/ber_tlv_decoder.dart';
import '../data/tlv/hex_codec.dart';
import '../domain/interfaces/card_parser.dart';
import '../domain/interfaces/card_transport.dart';
import '../domain/interfaces/tag_dictionary.dart';
import '../domain/models/card_application.dart';
import '../domain/models/card_field_summary.dart';
import '../domain/models/card_record.dart';
import '../domain/models/emv_date_codec.dart';
import '../domain/models/parse_issue.dart';
import '../domain/models/tlv_node.dart';

/// EMV / PBOC 严格只读：SELECT → GET DATA（ATC）→ 有界 READ RECORD。
/// 不发送 GPO 或构建 PDOL，不通过启动交易取得 AFL 或补齐受保护字段。
abstract class ContactlessReadParser implements CardParser {
  TagDictionary get dictionary;

  /// 单应用读取尝试数上限（资源保护，失败尝试同样计数）。
  static const int _maxRecords = 0xFE;

  @override
  Future<ParsedApplication> parse(
    CardApplication application,
    CardTransport transport,
  ) async {
    final aid = HexCodec.decode(application.aidHex);
    final issues = <ParseIssue>[];

    // 1. 应用选择（携带 FCI 证据；选择响应可解析时优先，失败回退目录标签）
    final selectResp = await _exchange(
      transport,
      ApduCommand.select(aid),
      issues,
      'select',
    );
    final selected = _isOk(selectResp);
    final selectRoots = selected ? _safeDecode(selectResp.data) : null;
    final List<TlvNode> fciTags;
    if (!selected) {
      fciTags = const [];
    } else if (selectRoots == null) {
      fciTags = application.directoryTags;
    } else {
      fciTags = _toNodes(selectRoots);
    }
    if (!selected) {
      issues.add(
        ParseIssue(
          stage: 'select',
          code: _swText(selectResp),
          message: '应用选择未成功，跳过后续读取',
        ),
      );
      return ParsedApplication(
        application: application.withSelected(false),
        parserId: parserId,
        fciTags: fciTags,
        issues: issues,
      );
    }

    // 2. GET DATA 直接读取 ATC。拒绝或不支持时保留缺失，绝不回退 GPO。
    final dataTags = <TlvNode>[];
    final atcResponse = await _exchange(
      transport,
      ApduCommand.getApplicationTransactionCounter(),
      issues,
      'get_data',
    );
    if (_isOk(atcResponse)) {
      final roots = _safeDecode(atcResponse.data);
      final atc = roots == null ? null : BerTlvDecoder.findFirst(roots, '9F36');
      if (atc != null && atc.value.length == 2) {
        dataTags.add(_toNode(atc));
      } else {
        issues.add(
          const ParseIssue(
            stage: 'get_data',
            code: 'invalid_atc',
            message: 'GET DATA 响应未包含有效的两字节 9F36，不推断计数器',
          ),
        );
      }
    } else if (atcResponse.statusWord != 0) {
      issues.add(
        ParseIssue(
          stage: 'get_data',
          code: _swText(atcResponse),
          message: '卡片未开放 ATC 的直接读取，保留未知',
        ),
      );
    }

    // 3. 无 AFL 时仅枚举公开可读记录：SFI 1..30，每文件从记录 1 开始。
    // 遇拒绝即结束该文件；所有成功及失败尝试共用单应用 254 次预算。
    // 没有交易上下文的卡片可能拒绝全部记录，这不触发任何交易或认证。
    final records = <CardRecord>[];
    var attempts = 0;
    recordsLoop:
    for (var sfi = 1; sfi <= 30; sfi++) {
      for (var record = 1; record <= 254; record++) {
        if (_hasTransportFailure(issues)) break recordsLoop;
        if (attempts >= _maxRecords) {
          issues.add(
            const ParseIssue(
              stage: 'read_record',
              code: 'record_limit',
              message: '已达到单应用记录读取次数上限，保留已读数据',
            ),
          );
          break recordsLoop;
        }
        attempts++;
        final response = await _exchange(
          transport,
          ApduCommand.readRecord(sfi, record),
          issues,
          'read_record',
        );
        if (!_isOk(response)) {
          if (response.statusWord != 0 &&
              response.statusWord != 0x6A82 &&
              response.statusWord != 0x6A83) {
            issues.add(
              ParseIssue(
                stage: 'read_record',
                code: _swText(response),
                message: 'SFI $sfi 记录 $record 未开放读取，停止该文件',
              ),
            );
          }
          break;
        }
        final roots = _safeDecode(response.data);
        records.add(
          CardRecord(
            sfi: sfi,
            recordNumber: record,
            rawHex: HexCodec.encode(response.data),
            tags: roots == null ? const [] : _toNodes(roots),
            parseError: roots == null ? '记录内容非合法 TLV 结构，保留原始 HEX' : null,
          ),
        );
      }
    }
    issues.add(
      const ParseIssue(
        stage: 'read_only',
        code: 'transaction_processing_skipped',
        message: '严格只读：未启动交易，仅保留直接可读数据；受保护字段及记录完整性未知',
      ),
    );

    return ParsedApplication(
      application: application.withSelected(true),
      parserId: parserId,
      fciTags: fciTags,
      dataTags: dataTags,
      records: records,
      issues: issues,
      summary: _buildSummary([
        // GET DATA 是本次直接观察值，优先于 FCI 或记录中同名标签。
        ...dataTags,
        ...fciTags,
        for (final r in records) ...r.tags,
      ]),
    );
  }

  bool _hasTransportFailure(List<ParseIssue> issues) => issues.any(
    (issue) => issue.code == 'nfc_io_error' || issue.code == 'invalid_response',
  );

  /// 记录内可能存在多条同类标签（如 5A 与 9F 系列），逐个转成 TlvNode。
  List<TlvNode> _toNodes(List<RawTlv> roots) =>
      roots.map((r) => _toNode(r)).toList();

  TlvNode _toNode(RawTlv r) {
    final decoded = dictionary.decodeValue(r.tagHex, r.value);
    final maskedValue = JsonTagDictionary.decodeForDisplay(
      dictionary,
      r.tagHex,
      r.value,
    );
    return TlvNode(
      tagHex: r.tagHex,
      length: r.length,
      rawValue: r.value,
      description: dictionary.describe(r.tagHex),
      decodedValue: maskedValue ?? decoded,
      masked: dictionary.shouldMask(r.tagHex),
      children: r.children.map(_toNode).toList(),
    );
  }

  List<RawTlv>? _safeDecode(Uint8List data) {
    try {
      return BerTlvDecoder.decode(data);
    } on FormatException {
      return null;
    }
  }

  /// 单阶段错误仅标记本阶段，避免后续失败丢弃已读到的 FCI / PAN。
  Future<ApduResponse> _exchange(
    CardTransport transport,
    Uint8List apdu,
    List<ParseIssue> issues,
    String stage,
  ) async {
    try {
      final response = await exchangeReadOnly(
        (cmd) => transport.transceive(Uint8List.fromList(cmd)),
        apdu,
      );
      return ApduResponse(
        data: Uint8List.fromList(response.data),
        sw1: response.sw1,
        sw2: response.sw2,
      );
    } on FormatException {
      issues.add(
        ParseIssue(
          stage: stage,
          code: 'invalid_response',
          message: 'APDU 响应不完整或续传超限，保留已读数据',
        ),
      );
    } catch (_) {
      issues.add(
        ParseIssue(
          stage: stage,
          code: 'nfc_io_error',
          message: 'NFC 通信异常，保留已读数据',
        ),
      );
    }
    return ApduResponse(data: _empty, sw1: 0, sw2: 0);
  }

  /// [_exchange] 已处理 61XX / 6CXX 链式响应，此处仅按最终状态字判断。
  bool _isOk(ApduResponse r) => r.isSuccess;

  String _swText(ApduResponse r) => r.statusWord == 0
      ? 'no_response'
      : r.statusWord.toRadixString(16).padLeft(4, '0').toUpperCase();

  static final Uint8List _empty = Uint8List(0);

  /// 需提炼展示的关键标签（按 UI 优先顺序）：卡面身份 + 交易信息。
  static const List<String> _summaryTags = [
    '5A',
    '5F20',
    '5F24',
    '5F25',
    '5F30',
    '57',
    '9F6B',
    '50',
    '9F12',
    '9F08',
    '9F36',
    '9A',
    '9F21',
    '9F02',
    '9F03',
    '5F2A',
    '9C',
    '9F27',
    '9F26',
    '9F17',
    '9F4C',
  ];

  /// 遍历 FCI/GET DATA/记录标签树，命中关键标签即解码出值（解码失败回退原始 HEX）。
  CardFieldSummary _buildSummary(List<TlvNode> trees) {
    final fields = <CardField>[];
    for (final tag in _summaryTags) {
      final node =
          switch (tag) {
            '5A' => findTag(
              trees,
              tag,
              accepts: (node) =>
                  CardFieldSummary.extractPan(tag, node.rawValueHex) != null,
            ),
            '5F24' => findTag(
              trees,
              tag,
              accepts: (node) =>
                  EmvDateCodec.decodeHex(node.rawValueHex) != null,
            ),
            _ => null,
          } ??
          findTag(trees, tag);
      if (node == null) continue;
      final decoded = dictionary.decodeValue(tag, node.rawValue);
      final value = tag == '5A'
          ? CardFieldSummary.extractPan(tag, node.rawValueHex) ??
                node.rawValueHex
          : (decoded != null && decoded.trim().isNotEmpty)
          ? decoded.trim()
          : node.rawValueHex;
      fields.add(
        CardField(
          tag: tag,
          label: dictionary.lookup(tag)?.nameZh ?? tag,
          value: value,
          rawValueHex: node.rawValueHex,
          sensitive:
              dictionary.shouldMask(tag) ||
              tag == '5A' ||
              tag == '57' ||
              tag == '9F6B',
        ),
      );
    }
    return CardFieldSummary(fields);
  }
}
