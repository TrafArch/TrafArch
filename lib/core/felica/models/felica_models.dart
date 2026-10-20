library;

import '../felica_hex.dart';
import 'cross_border_payment.dart';
import 'felica_card_type.dart';

/// 一次 FeliCa 读取阶段的总体状态。
enum FelicaReadState {
  success,
  partial,
  unsupported,
  accessDenied,
  tagLost,
  malformed,
  failed,
}

extension FelicaReadStateInfo on FelicaReadState {
  String get label => switch (this) {
        FelicaReadState.success => '成功',
        FelicaReadState.partial => '部分成功',
        FelicaReadState.unsupported => '不支持',
        FelicaReadState.accessDenied => '无访问权限',
        FelicaReadState.tagLost => '卡片已离开',
        FelicaReadState.malformed => '响应格式异常',
        FelicaReadState.failed => '读取失败',
      };

  /// 只有通道级错误使用失败样式：partial / unsupported 表示受限而非错误。
  bool get isFailure => switch (this) {
        FelicaReadState.success ||
        FelicaReadState.partial ||
        FelicaReadState.unsupported =>
          false,
        FelicaReadState.accessDenied ||
        FelicaReadState.tagLost ||
        FelicaReadState.malformed ||
        FelicaReadState.failed =>
          true,
      };
}

/// 单个读取阶段的结果（阶段名 + 状态 + 说明）。
class FelicaReadStatus {
  final String stage;
  final FelicaReadState state;
  final String message;

  const FelicaReadStatus({
    required this.stage,
    required this.state,
    required this.message,
  });
}

/// 一个原始数据块：读取失败时只保留错误原因，[hex] 为空。
class FelicaRawBlock {
  final String label;
  final List<int> bytes;
  final String? error;

  const FelicaRawBlock({
    required this.label,
    this.bytes = const [],
    this.error,
  });

  bool get isSuccess => error == null;

  String get hex => FelicaHex.bytesToHex(bytes);
}

/// 卡内一个独立钱包（Suica 电子货币 / 八达通港币 / 岭南通或深圳通人民币）。
///
/// [balanceMinorUnits] 为最小货币单位整数；[readState] 不是
/// [FelicaWalletReadState.success] 时表示余额尚未可靠确认，展示层必须
/// 显示「暂不可读取」而不是 0。
class FelicaWallet {
  final String walletId;
  final FelicaWalletKind kind;
  final String name;
  final int? balanceMinorUnits;
  final String currency;

  /// 货币小数位（JPY = 0，HKD / CNY = 2）。
  final int fractionDigits;

  final FelicaWalletReadState readState;
  final String? note;

  /// 读取失败原因（服务未公开、无权限、解析失败等）。
  final String? errorMessage;

  const FelicaWallet({
    required this.walletId,
    this.kind = FelicaWalletKind.unknown,
    required this.name,
    this.balanceMinorUnits,
    required this.currency,
    this.fractionDigits = 0,
    this.readState = FelicaWalletReadState.notDetected,
    this.note,
    this.errorMessage,
  });

  /// 只有读取成功且余额非空才算已验证。
  bool get balanceVerified =>
      readState == FelicaWalletReadState.success &&
      balanceMinorUnits != null;

  bool get hasBalance => balanceVerified;

  /// 余额展示文本；未验证或缺失时返回 null（调用方显示占位文案）。
  String? get balanceText {
    final value = balanceMinorUnits;
    if (!balanceVerified || value == null) return null;
    return formatAmount(value);
  }

  /// 按本钱包的币种与小数位格式化金额（交易记录同样复用）。
  String formatAmount(int value) {
    final digits = fractionDigits < 0
        ? 0
        : (fractionDigits > 6 ? 6 : fractionDigits);
    final sign = value < 0 ? '-' : '';
    final abs = value.abs();
    var unit = 1;
    for (var i = 0; i < digits; i++) {
      unit *= 10;
    }
    final whole = _groupThousands(abs ~/ unit);
    if (digits == 0) {
      return switch (currency) {
        'JPY' => '$sign¥$whole',
        'HKD' => '${sign}HK\$$whole',
        'CNY' => '${sign}¥$whole',
        _ => '$sign$whole${currency.isEmpty ? '' : ' $currency'}',
      };
    }
    final fraction = (abs % unit).toString().padLeft(digits, '0');
    return switch (currency) {
      'HKD' => '${sign}HK\$$whole.$fraction',
      'CNY' => '${sign}¥$whole.$fraction',
      _ => '$sign$whole.$fraction${currency.isEmpty ? '' : ' $currency'}',
    };
  }

  FelicaWallet copyWith({
    String? walletId,
    FelicaWalletKind? kind,
    String? name,
    int? balanceMinorUnits,
    String? currency,
    int? fractionDigits,
    FelicaWalletReadState? readState,
    String? note,
    String? errorMessage,
  }) =>
      FelicaWallet(
        walletId: walletId ?? this.walletId,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        balanceMinorUnits: balanceMinorUnits ?? this.balanceMinorUnits,
        currency: currency ?? this.currency,
        fractionDigits: fractionDigits ?? this.fractionDigits,
        readState: readState ?? this.readState,
        note: note ?? this.note,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  static String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// 一条 FeliCa 交易记录。
///
/// [decoded] 为 false 表示原始记录未完整解析：未通过校验的字段为 null，
/// 通过校验的字段仍可能单独可用，使用前必须逐字段判空，只保留 [rawHex]。
class FelicaTransaction {
  final DateTime? time;
  final int? amountMinorUnits;
  final String? type;
  final String? locationCode;
  final String rawHex;
  final bool decoded;

  /// 记录序号（通常为块号），便于对照原始块。
  final int? sequence;
  final String? note;

  /// 金额所属钱包；未知时不要用「第一个钱包」猜测币种。
  final FelicaWalletKind walletKind;

  /// 金额币种；记录解析器确认后填写，未确认保持 null。
  final String? currency;

  /// 是否为单钱包产品的跨境折算交易（如全国通卡内地消费）。
  /// 只有记录解析器能可靠确认时才置 true。
  final bool crossBorder;

  const FelicaTransaction({
    this.time,
    this.amountMinorUnits,
    this.type,
    this.locationCode,
    required this.rawHex,
    this.decoded = false,
    this.sequence,
    this.note,
    this.walletKind = FelicaWalletKind.unknown,
    this.currency,
    this.crossBorder = false,
  });
}

/// 一次 FeliCa 识读的完整结果。
class FelicaScanResult {
  final String cardType;
  final String displayName;

  /// 产品类型；仅识别到 FeliCa 卡时为 [FelicaCardType.unknown]。
  final FelicaCardType cardProductType;

  final String? idm;
  final List<FelicaWallet> wallets;
  final List<FelicaTransaction> transactions;
  final List<FelicaReadStatus> statuses;
  final List<FelicaRawBlock> rawBlocks;
  final List<int> systemCodes;
  final DateTime scannedAt;

  /// 产品对外交通功能摘要；未确认具体产品时为 null（不猜测）。
  final String? transitCapability;

  /// 单钱包产品的跨境折算口径（目前仅八达通－全国通卡）。
  final CrossBorderPaymentInfo? crossBorder;

  const FelicaScanResult({
    required this.cardType,
    required this.displayName,
    this.cardProductType = FelicaCardType.unknown,
    this.idm,
    this.wallets = const [],
    this.transactions = const [],
    this.statuses = const [],
    this.rawBlocks = const [],
    this.systemCodes = const [],
    this.transitCapability,
    this.crossBorder,
    required this.scannedAt,
  });

  /// 汇总状态：卡片离开 / 格式异常 / 失败优先，其次部分成功，
  /// 全部阶段成功才算 success；没有任何阶段信息时视为不支持。
  FelicaReadState get state {
    if (statuses.isEmpty) return FelicaReadState.unsupported;
    if (statuses.any((s) => s.state == FelicaReadState.tagLost)) {
      return FelicaReadState.tagLost;
    }
    if (statuses.any((s) => s.state == FelicaReadState.malformed)) {
      return FelicaReadState.malformed;
    }
    if (statuses.any((s) => s.state == FelicaReadState.failed)) {
      return FelicaReadState.failed;
    }
    if (statuses.any((s) => s.state == FelicaReadState.partial)) {
      return FelicaReadState.partial;
    }
    if (statuses.every((s) => s.state == FelicaReadState.success)) {
      return FelicaReadState.success;
    }
    return FelicaReadState.unsupported;
  }

  String get stateText => state.label;

  String get systemCodeText => FelicaHex.systemCodeText(systemCodes);

  /// 是否建立多个钱包（双钱包产品）；不表示两个钱包都已读取成功。
  bool get hasMultipleWallets => wallets.length > 1;

  /// 是否至少有一个钱包的余额已通过校验（不把占位余额当作已读取）。
  bool get hasVerifiedBalance =>
      wallets.any((w) => w.balanceVerified && w.balanceMinorUnits != null);

  FelicaScanResult copyWith({
    List<FelicaWallet>? wallets,
    List<FelicaTransaction>? transactions,
    List<FelicaReadStatus>? statuses,
    List<FelicaRawBlock>? rawBlocks,
    List<int>? systemCodes,
    FelicaCardType? cardProductType,
    String? transitCapability,
    CrossBorderPaymentInfo? crossBorder,
  }) =>
      FelicaScanResult(
        cardType: cardType,
        displayName: displayName,
        cardProductType: cardProductType ?? this.cardProductType,
        idm: idm,
        wallets: wallets ?? this.wallets,
        transactions: transactions ?? this.transactions,
        statuses: statuses ?? this.statuses,
        rawBlocks: rawBlocks ?? this.rawBlocks,
        systemCodes: systemCodes ?? this.systemCodes,
        transitCapability: transitCapability ?? this.transitCapability,
        crossBorder: crossBorder ?? this.crossBorder,
        scannedAt: scannedAt,
      );
}