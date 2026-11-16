/// 稳定的本地卡片指纹构建（关联同一张卡的历次读取）。
///
/// - 通用 [build] 基于已授权读取的卡应用标识（应用序列号 + 发卡方标识）构建，
///   不使用 NFC UID：UID 稳定性不可假定，也不作为公开卡号展示；
/// - 指纹按解析器级系统标识构建（而非细化卡型）：卡种目录新增细化
///   规则（如八达通细化）时指纹保持不变，避免规则升级产生重复档案；
/// - 关键标识（卡号）缺失或为全 0（未写入）时无法构建（返回 null，
///   调用方跳过建档，不猜测）。
/// - Suica 使用独立 [buildSuica] 的 FeliCa IDm 命名空间；不作为卡号展示。
abstract final class CardFingerprint {
  /// Application identity is independent of the card's RF IDm. Keep this
  /// namespace separate from logical transit card numbers and Suica captures.
  static String? buildAmusementIc(String? accessCode) {
    if (accessCode == null ||
        accessCode.length != 20 ||
        !RegExp(r'^(500|501|510|520|530)[0-9]{17}$').hasMatch(accessCode)) {
      return null;
    }
    return 'felica:amusement_ic:access-code:$accessCode';
  }

  /// Explicit FeliCa namespace: IDm links local Suica captures only. It is not
  /// an application card number and must never populate the cardNumber field.
  static String? buildSuica(String? idm) {
    if (idm == null || !RegExp(r'^[0-9a-fA-F :\-]+$').hasMatch(idm)) {
      return null;
    }
    final value = idm.replaceAll(RegExp(r'[ :\-]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{16}$').hasMatch(value) || _isUnwritten(value)) {
      return null;
    }
    return 'felica:suica:idm:$value';
  }

  /// 构建指纹：`系统:发卡方:卡号`（[issuerId] 缺失 / 未写入时留空段）。
  static String? build({
    required String system,
    String? issuerId,
    String? cardNumber,
  }) {
    final number = _normalize(cardNumber);
    if (number == null || _isUnwritten(number)) return null;
    var issuer = _normalize(issuerId);
    if (issuer != null && _isUnwritten(issuer)) issuer = null;
    return '$system:${issuer ?? ''}:$number';
  }

  /// 规范化：去除分隔符（空格 / 冒号 / 连字符等）并大写。
  static String? _normalize(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// 全 0（未写入 / 擦除态）视为无效标识。
  static bool _isUnwritten(String value) => value.replaceAll('0', '').isEmpty;
}
