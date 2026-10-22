import '../data/app_database.dart';
import 'card_session_snapshot.dart';
import 'card_types.dart';
import 'archive_balance.dart';

/// 卡片档案展示规则（唯一来源，页面不得各自判断）：
/// - 名称：用户自定义名称优先，回退自动识别的正式卡名，再回退卡型
///   通用名称（不猜测具体卡名）；
/// - 卡号 / 余额 / 交易条数 / 最近读取时间：按存档快照生成展示文本。
extension SavedCardDisplayName on SavedCard {
  /// 主名称：自定义名称 > 正式卡名 > 卡型兜底名称。
  String get displayName {
    final custom = customName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    final official = officialName?.trim();
    if (official != null && official.isNotEmpty) return official;

    return cardTypeLabel(cardType);
  }

  /// 副标题：改名后仍保留展示正式卡名（正式名称不因改名丢失）；
  /// 其余按 发行方 / 城市 顺序拼接；均为空时回退卡型通用名称。
  String get subtitle {
    final parts = <String>[];
    final custom = customName?.trim();
    final official = officialName?.trim();
    if (custom != null &&
        custom.isNotEmpty &&
        official != null &&
        official.isNotEmpty) {
      parts.add(official);
    }

    final issuer = issuerName?.trim();
    if (issuer != null && issuer.isNotEmpty) parts.add(issuer);

    final city = cityName?.trim();
    if (city != null && city.isNotEmpty) parts.add(city);

    return parts.isEmpty ? cardTypeLabel(cardType) : parts.join(' · ');
  }

  /// 卡号展示文本（完整卡号，不脱敏）；未读取到时为「卡号未提供」。
  String get cardNumberText => cardNumber ?? '卡号未提供';

  /// 余额快照展示文本（如「¥ 2.00」/「HK$ 2.00」）；未读到余额时为 null。
  String? get balanceText {
    final interpretation = capturedBalanceInterpretation(this, sessionSnapshot);
    if (interpretation != null) return interpretation.accountBalanceText;
    if (isOctopusArchiveCard(this)) return unknownHistoricalOctopusBalance;
    final fen = balanceFen;
    if (fen == null) return null;
    final source = retainedBalanceSnapshot(this, sessionSnapshot);
    return (source?.context.minorUnitDigits != null
            ? source!.context
            : ArchiveContext(currencyCode: currencyCode, minorUnitDigits: 2))
        .formatAmount(fen);
  }

  /// 交易记录条数展示文本（如「41条」）；未记录时为 null。
  String? get transactionCountText {
    final count = transactionCount;
    return count == null ? null : '$count条';
  }

  /// 最近读取时间短文本（如「10月14日 21:40」）；未记录时为 null。
  String? get lastReadShortText {
    final at = lastReadAt;
    if (at == null) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    return '${t.month}月${t.day}日 ${_two(t.hour)}:${_two(t.minute)}';
  }

  /// 最近读取时间完整文本（如「2026-10-14 21:40:00」）；未记录时为 null。
  String? get lastReadFullText {
    final at = lastReadAt;
    if (at == null) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    return '${t.year}-${_two(t.month)}-${_two(t.day)} '
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  /// 最近一次保存到档案的行程记录快照；无快照（未保存过行程数据）或
  /// 数据损坏时为 null（详情页不展示行程区块）。
  CardSessionSnapshot? get sessionSnapshot {
    final json = sessionDataJson;
    if (json == null || json.isEmpty) return null;
    return CardSessionSnapshot.decode(json);
  }
}

/// 数值两位补零（如 9 → 09）。
String _two(int v) => v.toString().padLeft(2, '0');
