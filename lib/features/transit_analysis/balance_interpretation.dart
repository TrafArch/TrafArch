import 'dart:convert';

import '../../protocols/felica/models/cross_border_payment.dart';
import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/tunion/tunion_models.dart';

enum BalanceProduct { tunion, octopusTunion, unknown }

/// TU 侧观察不等于单港币账户余额，也不代表第二个人民币钱包。
enum BalanceSemantics { direct, tuObservation, unknown }

/// 调用方独立验证过的账户读数。此类型记录验证结果，不执行 NFC 或换算。
/// [evidenceSource] 应指向产生该读数的批次/协议证据，不能填前缀元数据。
final class VerifiedAccountBalance {
  final int amountMinor;
  final String currency;
  final String evidenceSource;
  final Map<String, dynamic> _extensions;

  VerifiedAccountBalance({
    required this.amountMinor,
    required this.currency,
    required this.evidenceSource,
    Map<String, dynamic> extensions = const {},
  }) : _extensions = _copyJson(extensions) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        evidenceSource.trim().isEmpty) {
      throw ArgumentError(
        'A verified balance needs a currency and evidence source',
      );
    }
  }

  factory VerifiedAccountBalance.fromJson(Map<String, dynamic> json) {
    if (json['verification'] != 'verified' ||
        json['amountMinor'] is! int ||
        json['currency'] is! String ||
        json['evidenceSource'] is! String) {
      throw const FormatException(
        'Missing independently verified balance evidence',
      );
    }
    return VerifiedAccountBalance(
      amountMinor: json['amountMinor'] as int,
      currency: json['currency'] as String,
      evidenceSource: json['evidenceSource'] as String,
      extensions: json,
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyJson(_extensions),
    'verification': 'verified',
    'amountMinor': amountMinor,
    'currency': currency,
    'evidenceSource': evidenceSource,
  };
}

/// 防止将 TU 整数观察误标为港币账户余额；不实现全国通 HKD/FX 读取。
///
/// 新采集从真实 [TUnionCardInfo.applicationSerial] 识别产品；历史恢复只
/// 使用本批次的序列号、parser/AID 和独立验证证据，不依赖当前前缀库。
/// 所有金额是百分之一货币单位的整数，零值有效，null 表示未读取。
/// JSON 解码保留原始对象及未知扩展；不认识的版本/语义只能显示未知。
final class BalanceInterpretation {
  static const int currentVersion = 1;
  static const String octopusPrefix = '31048500';

  final BalanceProduct product;
  final BalanceSemantics semantics;
  final String? matchedPrefix;
  final String? rawApplicationSerial;
  final String parserId;
  final String selectedAidHex;
  final int? observedAmountMinor;
  final String? observedCurrency;
  final String? accountCurrency;
  final int? accountBalanceMinor;
  final String? metadataCurrency;
  final VerifiedAccountBalance? verifiedAccountBalance;
  final Map<String, dynamic> _extensions;
  final Map<String, dynamic>? _originalJson;

  BalanceInterpretation._({
    required this.product,
    required this.semantics,
    required this.rawApplicationSerial,
    required this.parserId,
    required this.selectedAidHex,
    required this.observedAmountMinor,
    this.matchedPrefix,
    this.observedCurrency,
    this.accountCurrency,
    this.accountBalanceMinor,
    this.metadataCurrency,
    this.verifiedAccountBalance,
    Map<String, dynamic> extensions = const {},
    Map<String, dynamic>? originalJson,
  }) : _extensions = _copyJson(extensions),
       _originalJson = originalJson == null ? null : _copyJson(originalJson);

  factory BalanceInterpretation.fromParsedCard(
    ParsedCard card, {
    String? metadataCurrency,
    VerifiedAccountBalance? verifiedAccountBalance,
    Map<String, dynamic> extensions = const {},
  }) => BalanceInterpretation.fromCardInfo(
    card.info,
    parserId: card.parserId,
    selectedAidHex: card.selectedAidHex,
    metadataCurrency: metadataCurrency,
    verifiedAccountBalance: verifiedAccountBalance,
    extensions: extensions,
  );

  factory BalanceInterpretation.fromCardInfo(
    TUnionCardInfo info, {
    required String parserId,
    String selectedAidHex = '',
    String? metadataCurrency,
    VerifiedAccountBalance? verifiedAccountBalance,
    Map<String, dynamic> extensions = const {},
  }) {
    final serial = info.applicationSerial;
    // The reader preserves all 10 serial bytes as 20 BCD digits. Padding may
    // contain several zeroes; identity uses the existing display normalization.
    final fullSerial =
        serial != null && RegExp(r'^[0-9]{20}$').hasMatch(serial);
    final octopusCandidate =
        info.displayCardNumber?.startsWith(octopusPrefix) ?? false;
    final octopusIdentity = fullSerial && octopusCandidate;
    final aid = selectedAidHex.toUpperCase();
    final tuSource =
        CardParserIds.isTUnionFamily(parserId) &&
        (aid.isEmpty || aid == 'A000000632010105' || aid == 'A000000632010106');
    final octopus =
        tuSource && parserId == CardParserIds.tunion && octopusIdentity;
    // A truncated/invalid Octopus identity must not become a direct CNY account.
    final direct = tuSource && !octopusCandidate;
    final product = octopus
        ? BalanceProduct.octopusTunion
        : direct
        ? BalanceProduct.tunion
        : BalanceProduct.unknown;
    final semantics = octopus
        ? BalanceSemantics.tuObservation
        : direct
        ? BalanceSemantics.direct
        : BalanceSemantics.unknown;
    final accountCurrency = octopus
        ? 'HKD'
        : direct
        ? 'CNY'
        : null;
    if (verifiedAccountBalance != null &&
        verifiedAccountBalance.currency != accountCurrency) {
      throw ArgumentError(
        'Verified balance currency must match the identified account',
      );
    }
    return BalanceInterpretation._(
      product: product,
      semantics: semantics,
      matchedPrefix: octopus ? octopusPrefix : null,
      rawApplicationSerial: serial,
      parserId: parserId,
      selectedAidHex: selectedAidHex,
      observedAmountMinor: info.balanceFen,
      observedCurrency: octopus || direct ? 'CNY' : null,
      accountCurrency: accountCurrency,
      accountBalanceMinor:
          verifiedAccountBalance?.amountMinor ??
          (direct ? info.balanceFen : null),
      metadataCurrency: metadataCurrency,
      verifiedAccountBalance: verifiedAccountBalance,
      extensions: extensions,
    );
  }

  factory BalanceInterpretation.fromJson(Map<String, dynamic> json) {
    final original = _copyJson(json);
    final serial = _string(json['rawApplicationSerial']);
    final parser = _string(json['parserId']) ?? '';
    final aid = _string(json['selectedAidHex']) ?? '';
    final amount = json['observedAmountMinor'];
    final metadata = _string(json['metadataCurrency']);
    BalanceInterpretation unknown() => BalanceInterpretation._(
      product: BalanceProduct.unknown,
      semantics: BalanceSemantics.unknown,
      rawApplicationSerial: serial,
      parserId: parser,
      selectedAidHex: aid,
      observedAmountMinor: amount is int ? amount : null,
      metadataCurrency: metadata,
      extensions: original,
      originalJson: original,
    );
    final accountAmount = json['accountBalanceMinor'];
    if (json['version'] is! int ||
        json['version'] != currentVersion ||
        (amount != null && amount is! int) ||
        (accountAmount != null && accountAmount is! int)) {
      return unknown();
    }
    VerifiedAccountBalance? verified;
    final verification = json['verifiedAccountBalance'];
    if (verification is Map<String, dynamic>) {
      try {
        verified = VerifiedAccountBalance.fromJson(verification);
      } on FormatException {
        return unknown();
      } on ArgumentError {
        return unknown();
      }
    } else if (verification != null) {
      return unknown();
    }
    final BalanceInterpretation resolved;
    try {
      resolved = BalanceInterpretation.fromCardInfo(
        TUnionCardInfo(applicationSerial: serial, balanceFen: amount as int?),
        parserId: parser,
        selectedAidHex: aid,
        metadataCurrency: metadata,
        verifiedAccountBalance: verified,
      );
    } on ArgumentError {
      return unknown();
    }
    // Unknown or contradictory semantics must not become a known account balance.
    if (json['product'] != resolved.product.name ||
        json['semantics'] != resolved.semantics.name ||
        json['matchedPrefix'] != resolved.matchedPrefix ||
        json['observedCurrency'] != resolved.observedCurrency ||
        json['accountCurrency'] != resolved.accountCurrency ||
        accountAmount != resolved.accountBalanceMinor) {
      return unknown();
    }
    return BalanceInterpretation._(
      product: resolved.product,
      semantics: resolved.semantics,
      matchedPrefix: resolved.matchedPrefix,
      rawApplicationSerial: serial,
      parserId: parser,
      selectedAidHex: aid,
      observedAmountMinor: resolved.observedAmountMinor,
      observedCurrency: resolved.observedCurrency,
      accountCurrency: resolved.accountCurrency,
      accountBalanceMinor: resolved.accountBalanceMinor,
      metadataCurrency: metadata,
      verifiedAccountBalance: verified,
      extensions: original,
      originalJson: original,
    );
  }

  /// 返回副本，调用方不能通过修改嵌套扩展覆盖历史证据。
  Map<String, dynamic> get extensions => _copyJson(_extensions);

  bool get isOctopusTunion => product == BalanceProduct.octopusTunion;

  /// 产品模型可复用，但当前没有已验证的卡内 FX 解码器。
  CrossBorderPaymentInfo? get crossBorder =>
      isOctopusTunion ? const CrossBorderPaymentInfo.octopusTUnion() : null;

  /// 始终未知；未来归档中陌生的汇率字段仅保留，不参与金额解释。
  double? get exchangeRate => crossBorder?.exchangeRate;

  String get accountBalanceText {
    final amount = accountBalanceMinor;
    if (amount == null || accountCurrency == null) {
      return isOctopusTunion ? '港币余额未读取' : '余额未读取';
    }
    final symbol = accountCurrency == 'HKD' ? 'HK\$' : '¥';
    return '$symbol${_decimalAmount(amount)}';
  }

  String? get observedBalanceText {
    final amount = observedAmountMinor;
    if (amount == null) return null;
    if (observedCurrency == null) return '$amount 原始单位（币种未知）';
    return '¥${_decimalAmount(amount)}';
  }

  String get observationLabel => observedCurrency == 'CNY' ? 'TU侧金额' : '原始金额';

  String get safeDisplayText {
    final account = accountBalanceText;
    if (accountBalanceMinor != null || !isOctopusTunion) return account;
    final observed = observedBalanceText;
    return observed == null ? account : '$account（$observationLabel：$observed）';
  }

  /// 解码过的历史对象原样返回，不用当前解释覆盖当时的记录或未知扩展。
  Map<String, dynamic> toJson() => _originalJson != null
      ? _copyJson(_originalJson)
      : {
          ..._copyJson(_extensions),
          'version': currentVersion,
          'product': product.name,
          'semantics': semantics.name,
          'matchedPrefix': matchedPrefix,
          'rawApplicationSerial': rawApplicationSerial,
          'parserId': parserId,
          'selectedAidHex': selectedAidHex,
          'observedAmountMinor': observedAmountMinor,
          'observedCurrency': observedCurrency,
          'accountCurrency': accountCurrency,
          'accountBalanceMinor': accountBalanceMinor,
          'metadataCurrency': metadataCurrency,
          'verifiedAccountBalance': verifiedAccountBalance?.toJson(),
          'exchangeRate': null,
        };
}

String? _string(Object? value) => value is String ? value : null;

Map<String, dynamic> _copyJson(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

String _decimalAmount(int amount) {
  final digits = amount.toString().replaceFirst('-', '').padLeft(3, '0');
  return '${amount < 0 ? '-' : ''}'
      '${digits.substring(0, digits.length - 2)}.${digits.substring(digits.length - 2)}';
}
