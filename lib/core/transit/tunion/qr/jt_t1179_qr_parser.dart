import 'dart:typed_data';

import 'jt_t1179_certificate_parser.dart';

/// JT/T 1179 表 2：交通一卡通二维码数据结构解析器。
///
/// 解析整个二维码数据体，并把第 3 项的 117 字节发卡机构公钥证书
/// 交给 [JtT1179CertificateParser] 解析，因此解析完成后可同时拿到
/// 证书原始字节与证书内部字段。
///
/// 表 2 的 17 项布局（长度单位：字节）：
/// 1. 二维码版本 1；2. 二维码长度 2；3. 发卡机构公钥证书 117；
/// 4. 支付账户号 16；5. 用户账户号 10；6. 发卡机构代码 4；
/// 7. 发码平台代码 4；8. 用户账户类型 1；9. 单次消费金额上限 3；
/// 10. 支付账户用户公钥 33（压缩公钥）；11. 支付账户系统授权过期时间 4；
/// 12. 二维码有效时间 2；13. 发卡机构自定义域长度 1；14. 发卡机构自定义域 变长；
/// 15. 发卡机构授权签名 65；16. 二维码生成时间 4；17. 支付账户用户私钥签名 65。
///
/// 第 15、17 项签名字段不做解析（不校验格式、不切分签名原文），
/// 仅按长度跳过以保持字段偏移正确；原始字节可从 [JtT1179QrData.raw] 查看。
class JtT1179QrParser {
  JtT1179QrParser._();

  /// 表 2 第 1 项：二维码版本标准范围 0x80～0xFF，当前标准值为 0x80。
  static const int minVersion = 0x80;

  /// 表 2 第 2 项：二维码长度字段自身的字节数。
  static const int declaredLengthBytes = 2;

  /// 表 2 第 15、17 项签名字段长度（含 1 字节格式标识），仅用于跳过。
  static const int signatureLength = 65;

  /// 解析整个二维码数据体。
  ///
  /// [input] 为二维码去除纠错编码后的二进制数据（8 bit byte 模式）。
  /// 长度不符、固定值错误或读取越界时抛 [FormatException]；
  /// 本方法不做任何密码学验证。
  static JtT1179QrData parse(List<int> input) {
    if (input.isEmpty) {
      throw const FormatException('二维码数据为空');
    }

    if (input.any((b) => b < 0 || b > 255)) {
      throw const FormatException('二维码数据包含无效字节');
    }

    final data = Uint8List.fromList(input);
    var p = 0;

    int readByte() {
      if (p >= data.length) {
        throw FormatException(
          '二维码数据不完整：偏移 $p 处读取超出 ${data.length} 字节',
        );
      }
      return data[p++];
    }

    Uint8List readBytes(int n) {
      if (p + n > data.length) {
        throw FormatException(
          '二维码数据不完整：偏移 $p 处需要 $n 字节，仅剩 ${data.length - p} 字节',
        );
      }
      final value = Uint8List.fromList(data.sublist(p, p + n));
      p += n;
      return value;
    }

    int readUint16() => (readByte() << 8) | readByte();

    int readUint32() =>
        (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();

    // 1. 二维码版本
    final version = readByte();
    if (version < minVersion) {
      throw FormatException(
        '二维码版本错误：应不小于 0x${_hexByte(minVersion)}，'
        '实际为 0x${_hexByte(version)}',
      );
    }

    // 2. 二维码长度：数据体长度，自第 3 项起算至数据末尾。
    final declaredLength = readUint16();

    // 3. 发卡机构公钥证书（117 字节，保留原始数据并接入证书解析器）
    final certificate = readBytes(JtT1179CertificateParser.certificateLength);
    final issuerCertificate = JtT1179CertificateParser.parse(certificate);

    // 4. 支付账户号（16 字节，Cn 编码，右补十六进制 'F'）
    final paymentAccountNumber = readBytes(16);

    // 5. 用户账户号（10 字节）
    final userAccountNumber = readBytes(10);

    // 6. 发卡机构代码（4 字节）
    final issuerCode = readBytes(4);

    // 7. 发码平台代码（4 字节）
    final platformCode = readBytes(4);

    // 8. 用户账户类型（1 字节）
    final userAccountType = readByte();

    // 9. 单次消费金额上限（3 字节大端整数，单位：分）
    final consumptionLimitBytes = readBytes(3);
    final singleConsumptionLimitFen =
        (consumptionLimitBytes[0] << 16) |
        (consumptionLimitBytes[1] << 8) |
        consumptionLimitBytes[2];

    // 10. 支付账户用户公钥（33 字节压缩公钥）
    final userPublicKey = readBytes(33);

    // 11. 支付账户系统授权过期时间（4 字节 Unix 时间戳，UTC）
    final authorizationExpiryEpoch = readUint32();

    // 12. 二维码有效时间（2 字节，单位：秒）
    final qrValiditySeconds = readUint16();

    // 13. 发卡机构自定义域长度（1 字节）
    final issuerDefinedLength = readByte();

    // 14. 发卡机构自定义域（变长）
    final issuerDefinedData = readBytes(issuerDefinedLength);

    // 15. 发卡机构授权签名（65 字节）：不解析，仅按长度跳过
    readBytes(signatureLength);

    // 16. 二维码生成时间（4 字节 Unix 时间戳，UTC）
    final generationEpoch = readUint32();

    // 17. 支付账户用户私钥签名（65 字节）：不解析，仅按长度跳过
    readBytes(signatureLength);

    if (p != data.length) {
      throw FormatException('二维码字段长度计算异常：$p/${data.length}');
    }

    // 二维码长度校验：声明值应为数据总长减去版本（1 字节）与长度（2 字节）。
    final bodyLength = data.length - 1 - declaredLengthBytes;
    if (declaredLength != bodyLength) {
      throw FormatException(
        '二维码长度错误：声明 $declaredLength 字节，'
        '数据体实际 $bodyLength 字节',
      );
    }

    return JtT1179QrData(
      raw: data,
      version: version,
      declaredLength: declaredLength,
      certificate: certificate,
      issuerCertificate: issuerCertificate,
      paymentAccountNumber: paymentAccountNumber,
      userAccountNumber: userAccountNumber,
      issuerCode: issuerCode,
      platformCode: platformCode,
      userAccountType: userAccountType,
      singleConsumptionLimitFen: singleConsumptionLimitFen,
      userPublicKey: userPublicKey,
      authorizationExpiryEpoch: authorizationExpiryEpoch,
      qrValiditySeconds: qrValiditySeconds,
      issuerDefinedLength: issuerDefinedLength,
      issuerDefinedData: issuerDefinedData,
      generationEpoch: generationEpoch,
    );
  }

  static String _hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
}

/// JT/T 1179 表 2 二维码数据的解析结果。
///
/// 同时保留 [certificate] 原始 117 字节与解析后的 [issuerCertificate]；
/// 第 15、17 项签名字段不做解析，原始字节可从 [raw] 中查看。
class JtT1179QrData {
  final Uint8List raw;

  /// 表 2 第 1 项：二维码版本。
  final int version;

  /// 表 2 第 2 项：二维码长度（数据体长度，不含版本与长度字段本身）。
  final int declaredLength;

  /// 表 2 第 3 项：发卡机构公钥证书原始 117 字节。
  final Uint8List certificate;

  /// 表 2 第 3 项：解析后的证书对象。
  final JtT1179IssuerCertificate issuerCertificate;

  /// 表 2 第 4 项：支付账户号（16 字节）。
  final Uint8List paymentAccountNumber;

  /// 表 2 第 5 项：用户账户号（10 字节）。
  final Uint8List userAccountNumber;

  /// 表 2 第 6 项：发卡机构代码（4 字节）。
  final Uint8List issuerCode;

  /// 表 2 第 7 项：发码平台代码（4 字节）。
  final Uint8List platformCode;

  /// 表 2 第 8 项：用户账户类型（1 字节）。
  final int userAccountType;

  /// 表 2 第 9 项：单次消费金额上限（单位：分）。
  final int singleConsumptionLimitFen;

  /// 表 2 第 10 项：支付账户用户公钥（33 字节压缩公钥）。
  final Uint8List userPublicKey;

  /// 表 2 第 11 项：授权过期时间（Unix 时间戳，UTC）。
  final int authorizationExpiryEpoch;

  /// 表 2 第 12 项：二维码有效时间（单位：秒）。
  final int qrValiditySeconds;

  /// 表 2 第 13 项：发卡机构自定义域长度。
  final int issuerDefinedLength;

  /// 表 2 第 14 项：发卡机构自定义域。
  final Uint8List issuerDefinedData;

  /// 表 2 第 16 项：二维码生成时间（Unix 时间戳，UTC）。
  final int generationEpoch;

  const JtT1179QrData({
    required this.raw,
    required this.version,
    required this.declaredLength,
    required this.certificate,
    required this.issuerCertificate,
    required this.paymentAccountNumber,
    required this.userAccountNumber,
    required this.issuerCode,
    required this.platformCode,
    required this.userAccountType,
    required this.singleConsumptionLimitFen,
    required this.userPublicKey,
    required this.authorizationExpiryEpoch,
    required this.qrValiditySeconds,
    required this.issuerDefinedLength,
    required this.issuerDefinedData,
    required this.generationEpoch,
  });

  /// 第 11 项授权过期时间（UTC）。
  DateTime get authorizationExpiryUtc => DateTime.fromMillisecondsSinceEpoch(
    authorizationExpiryEpoch * 1000,
    isUtc: true,
  );

  /// 第 16 项二维码生成时间（UTC）。
  DateTime get generationTimeUtc => DateTime.fromMillisecondsSinceEpoch(
    generationEpoch * 1000,
    isUtc: true,
  );

  /// 生成时间与第 12 项有效时间共同决定的失效时刻（UTC）。
  DateTime get qrValidUntilUtc =>
      generationTimeUtc.add(Duration(seconds: qrValiditySeconds));

  /// 授权是否已过期（第 11 项为 UTC 时间，过期时刻起失效）。
  bool isAuthorizationExpired([DateTime? now]) {
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(authorizationExpiryUtc);
  }

  /// 二维码是否已超出生效窗口（生成时间 + 有效秒数）。
  bool isQrExpired([DateTime? now]) {
    final current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(qrValidUntilUtc);
  }

  String get versionHex => '0x${_hexByte(version)}';
  String get paymentAccountNumberHex => _hex(paymentAccountNumber);
  String get userAccountNumberHex => _hex(userAccountNumber);
  String get issuerCodeHex => _hex(issuerCode);
  String get platformCodeHex => _hex(platformCode);
  String get userPublicKeyHex => _hex(userPublicKey);
  String get issuerDefinedDataHex => _hex(issuerDefinedData);

  /// 用户账户号的可读文本（公开实现样本为 ASCII）；无法解释时返回 null。
  String? get userAccountNumberText => _asciiText(userAccountNumber);

  /// 发卡机构代码的可读文本（公开实现样本为 ASCII）；无法解释时返回 null。
  String? get issuerCodeText => _asciiText(issuerCode);

  /// 发码平台代码的可读文本（公开实现样本为 ASCII）；无法解释时返回 null。
  String? get platformCodeText => _asciiText(platformCode);

  Map<String, dynamic> toJson() => {
    'version': versionHex,
    'declaredLength': declaredLength,
    'certificateHex': _hex(certificate),
    'issuerCertificate': issuerCertificate.toJson(),
    'paymentAccountNumberHex': paymentAccountNumberHex,
    'userAccountNumberHex': userAccountNumberHex,
    'userAccountNumberText': userAccountNumberText,
    'issuerCodeHex': issuerCodeHex,
    'issuerCodeText': issuerCodeText,
    'platformCodeHex': platformCodeHex,
    'platformCodeText': platformCodeText,
    'userAccountType': userAccountType,
    'singleConsumptionLimitFen': singleConsumptionLimitFen,
    'userPublicKeyHex': userPublicKeyHex,
    'authorizationExpiryEpoch': authorizationExpiryEpoch,
    'authorizationExpiryUtc': authorizationExpiryUtc.toIso8601String(),
    'isAuthorizationExpired': isAuthorizationExpired(),
    'qrValiditySeconds': qrValiditySeconds,
    'qrValidUntilUtc': qrValidUntilUtc.toIso8601String(),
    'isQrExpired': isQrExpired(),
    'issuerDefinedLength': issuerDefinedLength,
    'issuerDefinedDataHex': issuerDefinedDataHex,
    'generationEpoch': generationEpoch,
    'generationTimeUtc': generationTimeUtc.toIso8601String(),
  };

  static String _hex(List<int> bytes) =>
      bytes.map(_hexByte).join().toUpperCase();

  static String _hexByte(int b) =>
      b.toRadixString(16).padLeft(2, '0').toUpperCase();

  /// 按 ASCII 解释字节；遇 0x00/0xFF 填充截断，遇不可打印字节返回 null。
  static String? _asciiText(Uint8List bytes) {
    final result = StringBuffer();
    for (final b in bytes) {
      if (b == 0x00 || b == 0xFF) break;
      if (b < 0x20 || b > 0x7E) return null;
      result.writeCharCode(b);
    }
    final text = result.toString().trimRight();
    return text.isEmpty ? null : text;
  }
}