import 'dart:typed_data';

import '../data/apdu/apdu_command.dart';
import '../data/apdu/apdu_response.dart';
import '../data/dictionary/json_tag_dictionary.dart';
import '../data/pdol/pdol_data_builder.dart';
import '../data/tlv/ber_tlv_decoder.dart';
import '../data/tlv/hex_codec.dart';
import '../domain/interfaces/card_parser.dart';
import '../domain/interfaces/card_transport.dart';
import '../domain/interfaces/tag_dictionary.dart';
import '../domain/models/card_application.dart';
import '../domain/models/card_field_summary.dart';
import '../domain/models/card_record.dart';
import '../domain/models/parse_issue.dart';
import '../domain/models/tlv_node.dart';

/// 非接触式只读流程基类：实现允许的安全读取步骤，
/// 子类只提供协议族标识、适用判定与标签字典。
///
/// EMV / PBOC 自动切换点：
/// 1. GPO 按卡片 PDOL（9F38）自动组包；未提供 PDOL 或组包形式未被接受时
///    自动切换为 83 00 形式重试；
/// 2. GPO 响应同时兼容 77（TLV 模板）与 80（AIP+AFL 裸拼接）两种格式；
/// 3. AFL 按 EMV Book 3 语义（SFI / 首记录 / 末记录 / ODA 数）定位记录。
abstract class ContactlessReadParser implements CardParser {
  TagDictionary get dictionary;

  /// 单次读取记录数上限（协议边界，防止异常卡忽略记录号导致无界读取）。
  static const int _maxRecords = 0xFE;

  /// 单条 AFL 引用最多读取的记录数（规范内充分覆盖；防御异常卡）。
  static const int _maxRecordsPerRef = 32;

  @override
  Future<ParsedApplication> parse(
    CardApplication application,
    CardTransport transport,
  ) async {
    final aid = HexCodec.decode(application.aidHex);
    final issues = <ParseIssue>[];

    // 1. 应用选择（携带 FCI 证据；选择响应可解析时优先，失败回退目录标签）
    final selectResp = await _exchange(transport, ApduCommand.select(aid));
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
      issues.add(ParseIssue(
        stage: 'select',
        code: _swText(selectResp),
        message: '应用选择未成功，跳过后续读取',
      ));
      return ParsedApplication(
        application: application,
        parserId: parserId,
        fciTags: fciTags,
        issues: issues,
      );
    }

    // 2. GET PROCESSING OPTIONS：按卡片 PDOL（9F38）自动组包；
    //    无 PDOL 时发送 83 00；组包形式未被接受时自动切换 83 00 重试一次。
    final pdol = selectRoots == null
        ? null
        : BerTlvDecoder.findFirst(selectRoots, '9F38');
    final pdolData =
        pdol == null ? const <int>[] : PdolDataBuilder.build(pdol.value);
    var gpoResp = await _exchange(
      transport,
      ApduCommand.getProcessingOptions(pdolData: pdolData),
    );
    var gpoSwitched = false;
    if (!_isOk(gpoResp) && pdolData.isNotEmpty) {
      gpoSwitched = true;
      issues.add(ParseIssue(
        stage: 'gpo',
        code: 'switch_empty_pdol',
        message: 'PDOL 组包 GPO 未成功（${_swText(gpoResp)}），'
            '自动切换为 83 00 形式重试',
      ));
      gpoResp = await _exchange(transport, ApduCommand.getProcessingOptions());
    }
    List<TlvNode> gpoTags = const [];
    List<int>? afl;
    String gpoHex = '';
    if (_isOk(gpoResp)) {
      gpoHex = HexCodec.encode(gpoResp.data);
      final roots = _safeDecode(gpoResp.data);
      if (roots != null) {
        gpoTags = _toNodes(roots);
        afl = _extractAfl(roots);
      } else {
        issues.add(const ParseIssue(
          stage: 'gpo',
          code: 'bad_tlv',
          message: 'GPO 响应非合法 TLV 结构，保留原始 HEX',
        ));
      }
    } else {
      issues.add(ParseIssue(
        stage: 'gpo',
        code: _swText(gpoResp),
        message: gpoSwitched ? 'GPO 两种形式（PDOL 组包 / 83 00）均未成功' : 'GPO 未成功',
      ));
    }

    // 3. 依据 AFL 读取记录（以记录数上限防御异常卡驱动的无界读取）
    final records = <CardRecord>[];
    if (afl != null) {
      for (final ref in _parseAfl(afl)) {
        final count =
            ref.count > _maxRecordsPerRef ? _maxRecordsPerRef : ref.count;
        for (var r = ref.firstRecord; r < ref.firstRecord + count; r++) {
          if (records.length >= _maxRecords) break;
          final rec = await _readRecord(transport, ref.sfi, r, issues);
          if (rec != null) records.add(rec);
        }
        if (records.length >= _maxRecords) break;
      }
    } else {
      issues.add(const ParseIssue(
        stage: 'afl',
        code: 'no_afl',
        message: '未取得 AFL，无法定位可读记录',
      ));
    }

    return ParsedApplication(
      application: CardApplication(
        aidHex: application.aidHex,
        label: application.label,
        directoryTags: application.directoryTags,
        selected: true,
      ),
      parserId: parserId,
      fciTags: fciTags,
      gpoTags: gpoTags,
      gpoHex: gpoHex,
      records: records,
      issues: issues,
      summary: _buildSummary([
        ...fciTags,
        ...gpoTags,
        for (final r in records) ...r.tags,
      ]),
    );
  }

  Future<CardRecord?> _readRecord(
    CardTransport transport,
    int sfi,
    int record,
    List<ParseIssue> issues,
  ) async {
    final resp = await _exchange(transport, ApduCommand.readRecord(sfi, record));
    if (!_isOk(resp)) {
      issues.add(ParseIssue(
        stage: 'read_record',
        code: _swText(resp),
        message: 'SFI 0x${sfi.toRadixString(16)} 记录 $record 读取被拒或未找到',
      ));
      return null;
    }
    final roots = _safeDecode(resp.data);
    return CardRecord(
      sfi: sfi,
      recordNumber: record,
      rawHex: HexCodec.encode(resp.data),
      tags: roots == null
          ? const []
          : _toNodes(roots),
      parseError: roots == null ? '记录内容非合法 TLV 结构，保留原始 HEX' : null,
    );
  }

  /// 记录内可能存在多条同类标签（如 5A 与 9F 系列），逐个转成 TlvNode。
  List<TlvNode> _toNodes(List<RawTlv> roots) =>
      roots.map((r) => _toNode(r)).toList();

  TlvNode _toNode(RawTlv r) {
    final decoded = dictionary.decodeValue(r.tagHex, r.value);
    final maskedValue = JsonTagDictionary.decodeForDisplay(dictionary, r.tagHex, r.value);
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

  /// FCI 标签：优先复用目录已解析标签，否则从选择响应解析。
  List<TlvNode> _tagsFrom(Uint8List data, List<TlvNode> fallback) {
    if (fallback.isNotEmpty) return fallback;
    final roots = _safeDecode(data);
    return roots == null ? const [] : _toNodes(roots);
  }

  /// 从 GPO 响应提取 AFL：
  /// 优先 77 模板内 tag 94；否则兼容 80 模板（Format 1：AIP + AFL 裸拼接）。
  List<int>? _extractAfl(List<RawTlv> roots) {
    final afl = BerTlvDecoder.findFirst(roots, '94');
    if (afl != null) return afl.value;
    for (final root in roots) {
      if (root.tagHex == '80') {
        return root.value.length > 2 ? root.value.sublist(2).toList() : null;
      }
    }
    return null;
  }

  /// EMV Book 3 AFL：每 4 字节一组
  /// [SFI（高 5 位）/ 首记录号 / 末记录号 / 参与认证的记录数]。
  List<_AflRef> _parseAfl(List<int> afl) {
    final refs = <_AflRef>[];
    for (var i = 0; i + 3 < afl.length; i += 4) {
      final sfi = afl[i] >> 3;
      final first = afl[i + 1];
      final last = afl[i + 2];
      if (sfi == 0 || first == 0 || last < first) continue;
      refs.add(_AflRef(sfi: sfi, firstRecord: first, count: last - first + 1));
    }
    return refs;
  }

  List<RawTlv>? _safeDecode(Uint8List data) {
    try {
      return BerTlvDecoder.decode(data);
    } on FormatException {
      return null;
    }
  }

  /// 收发 + 6CXX / 61XX 链式处理（策略与交通卡解析器一致）。
  Future<ApduResponse> _exchange(CardTransport transport, Uint8List apdu) async {
    var bytes = await transport.transceive(apdu);
    if (apdu.isNotEmpty &&
        bytes.length >= 2 &&
        bytes[bytes.length - 2] == 0x6C &&
        bytes.last != 0) {
      bytes = await transport.transceive(
        Uint8List.fromList([...apdu.sublist(0, apdu.length - 1), bytes.last]),
      );
    }
    var guard = 0;
    while (bytes.length >= 2 &&
        bytes[bytes.length - 2] == 0x61 &&
        bytes.last != 0 &&
        guard++ < 32) {
      final tail = bytes.sublist(0, bytes.length - 2);
      final chain = await transport.transceive(
        ApduCommand.getResponse(apdu.isEmpty ? 0x00 : apdu.first, bytes.last),
      );
      bytes = Uint8List.fromList([...tail, ...chain]);
      if (chain.isEmpty) break;
    }
    if (bytes.length < 2) {
      return ApduResponse(data: _empty, sw1: 0, sw2: 0);
    }
    return ApduResponse.fromBytes(bytes);
  }

  /// [_exchange] 已处理 61XX / 6CXX 链式响应，此处仅按最终状态字判断。
  bool _isOk(ApduResponse r) => r.isSuccess;

  String _swText(ApduResponse r) => r.statusWord == 0
      ? 'no_response'
      : r.statusWord.toRadixString(16).padLeft(4, '0').toUpperCase();

  static final Uint8List _empty = Uint8List(0);

  /// 需提炼展示的关键标签（按 UI 优先顺序）：卡面身份 + 交易信息。
  static const List<String> _summaryTags = [
    '5A', '5F20', '5F24', '5F25', '5F30', '57',
    '50', '9F12', '9F08',
    '9F36', '9A', '9F21', '9F02', '9F03', '5F2A', '9C',
    '9F27', '9F26', '9F17', '9F4C',
  ];

  /// 遍历 FCI/GPO/记录标签树，命中关键标签即解码出值（解码失败回退原始 HEX）。
  CardFieldSummary _buildSummary(List<TlvNode> trees) {
    final fields = <CardField>[];
    for (final tag in _summaryTags) {
      final node = findTag(trees, tag);
      if (node == null) continue;
      final decoded = dictionary.decodeValue(tag, node.rawValue);
      final value = (decoded != null && decoded.trim().isNotEmpty)
          ? decoded.trim()
          : node.rawValueHex;
      fields.add(CardField(
        tag: tag,
        label: dictionary.lookup(tag)?.nameZh ?? tag,
        value: value,
        sensitive: dictionary.shouldMask(tag),
      ));
    }
    return CardFieldSummary(fields);
  }
}

class _AflRef {
  final int sfi;
  final int firstRecord;
  final int count;
  const _AflRef({required this.sfi, required this.firstRecord, required this.count});
}