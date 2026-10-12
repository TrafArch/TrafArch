import 'knowledge_base.dart';

/// 终端编号二次解码结果。
class TerminalLocation {
  final String ruleId;
  final String? ruleNote;
  final String? cityCode;
  final String? operatorCode;
  final String? lineCode;
  final String? stationCode;

  const TerminalLocation({
    required this.ruleId,
    this.ruleNote,
    this.cityCode,
    this.operatorCode,
    this.lineCode,
    this.stationCode,
  });

  bool get hasLocation => lineCode != null || stationCode != null;
}

/// 终端编号解码器：按规则集把 12 位终端号切分为城市/线路/站点编码。
/// 无匹配规则或终端号非 12 位十进制时返回 null（保持"未知"，不猜测）。
class TerminalDecoder {
  final TerminalRuleSet rules;
  TerminalDecoder(this.rules);

  static final _twelveDigits = RegExp(r'^\d{12}$');

  TerminalLocation? decode(
    String terminalId, {
    String? cityCode,
    String? issuerId,
  }) {
    if (!_twelveDigits.hasMatch(terminalId)) return null;
    final rule = rules.match(terminalId, cityCode: cityCode, issuerId: issuerId);
    if (rule == null) return null;

    String? slice(String field) {
      final range = rule.layout[field];
      if (range == null || range.length < 2) return null;
      final start = range[0];
      final end = range[1];
      if (start < 0 || end > terminalId.length || start >= end) return null;
      return terminalId.substring(start, end);
    }

    return TerminalLocation(
      ruleId: rule.id,
      ruleNote: rule.note,
      cityCode: slice('cityCode'),
      operatorCode: slice('operatorCode'),
      lineCode: slice('lineCode'),
      stationCode: slice('stationCode'),
    );
  }
}