import 'dart:typed_data';

/// JT/T 1179—2018 表18：发卡机构公钥证书。
///
/// 只负责解析和基本格式检查，不代表证书已通过 CA 验证；
/// 第 13 项数字签名不做解析，原始字节保留在 [raw] 中。
class JtT1179IssuerCertificate {
  final Uint8List raw;

  final int recordHeader;
  final Uint8List serviceId;
  final int caPublicKeyIndex;
  final int certificateFormat;
  final Uint8List issuerIdBytes;
  final int expiryMonth;
  final int expiryYear;
  final Uint8List serialNumberBytes;
  final int signatureAlgorithm;
  final int encryptionAlgorithm;
  final int publicKeyParameter;
  final int publicKeyLength;
  final Uint8List issuerPublicKey;

  const JtT1179IssuerCertificate({
    required this.raw,
    required this.recordHeader,
    required this.serviceId,
    required this.caPublicKeyIndex,
    required this.certificateFormat,
    required this.issuerIdBytes,
    required this.expiryMonth,
    required this.expiryYear,
    required this.serialNumberBytes,
    required this.signatureAlgorithm,
    required this.encryptionAlgorithm,
    required this.publicKeyParameter,
    required this.publicKeyLength,
    required this.issuerPublicKey,
  });

  /// 服务标识：交通电子现金应用为 01 01 00 00。
  bool get isTransportEcashService =>
      _sameBytes(serviceId, const [0x01, 0x01, 0x00, 0x00]);

  /// 表18记录头必须为 0x24。
  bool get hasValidRecordHeader => recordHeader == 0x24;

  /// 证书格式必须为 0x12。
  bool get hasValidCertificateFormat => certificateFormat == 0x12;

  /// 表18公钥签名算法标识：0x04 表示 SM2。
  bool get usesSm2Signature => signatureAlgorithm == 0x04;

  /// 表18公钥加密算法标识的说明注明为保留项。
  /// 此处只报告字段值，不据此推断实际加密能力。
  bool get reservedAlgorithmFieldIs04 => encryptionAlgorithm == 0x04;

  bool get hasValidPublicKeyLength =>
      publicKeyLength == 33 && issuerPublicKey.length == 33;

  /// 证书在该 MMYY 月份最后一天结束后失效。
  DateTime get expiryDateUtc => DateTime.utc(
    expiryYear,
    expiryMonth + 1,
    1,
  ).subtract(const Duration(days: 1));

  bool isExpired([DateTime? now]) {
    final current = (now ?? DateTime.now()).toUtc();
    final expiryEnd = DateTime.utc(expiryYear, expiryMonth + 1, 1);
    return !current.isBefore(expiryEnd);
  }

  /// cn8 为 8 位数字编码；这里按压缩 BCD 展示。
  /// 若原始值包含非十进制半字节，会抛出格式异常。
  String get issuerId {
    final result = StringBuffer();
    for (final byte in issuerIdBytes) {
      final high = (byte >> 4) & 0x0F;
      final low = byte & 0x0F;
      if (high > 9 || low > 9) {
        throw const FormatException('发卡机构标识不符合 BCD 数字编码');
      }
      result
        ..write(high)
        ..write(low);
    }
    return result.toString();
  }

  String get serviceIdHex => _hex(serviceId);
  String get serialNumberHex => _hex(serialNumberBytes);
  String get issuerPublicKeyHex => _hex(issuerPublicKey);

  Map<String, dynamic> toJson() => {
    'recordHeader': '0x${_byteHex(recordHeader)}',
    'serviceIdHex': serviceIdHex,
    'isTransportEcashService': isTransportEcashService,
    'caPublicKeyIndex': caPublicKeyIndex,
    'certificateFormat': '0x${_byteHex(certificateFormat)}',
    'issuerId': issuerId,
    'expiryMonth': expiryMonth,
    'expiryYear': expiryYear,
    'expiryDateUtc': expiryDateUtc.toIso8601String(),
    'isExpired': isExpired(),
    'serialNumberHex': serialNumberHex,
    'signatureAlgorithm': '0x${_byteHex(signatureAlgorithm)}',
    'encryptionAlgorithm': '0x${_byteHex(encryptionAlgorithm)}',
    'publicKeyParameter': '0x${_byteHex(publicKeyParameter)}',
    'publicKeyLength': publicKeyLength,
    'issuerPublicKeyHex': issuerPublicKeyHex,
  };

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hex(List<int> bytes) =>
      bytes.map(_byteHex).join().toUpperCase();

  static String _byteHex(int b) =>
      b.toRadixString(16).padLeft(2, '0').toUpperCase();
}

class JtT1179CertificateParser {
  static const int certificateLength = 117;

  static JtT1179IssuerCertificate parse(List<int> input) {
    if (input.length != certificateLength) {
      throw FormatException('证书长度错误：预期 117 字节，实际 ${input.length} 字节');
    }

    if (input.any((b) => b < 0 || b > 255)) {
      throw const FormatException('证书包含无效字节');
    }

    final data = Uint8List.fromList(input);
    var p = 0;

    int readByte() => data[p++];

    Uint8List readBytes(int n) {
      final value = Uint8List.fromList(data.sublist(p, p + n));
      p += n;
      return value;
    }

    // 1. 记录头
    final recordHeader = readByte();

    // 2. 服务标识
    final serviceId = readBytes(4);

    // 3. 中心 CA 公钥索引
    final caPublicKeyIndex = readByte();

    // 4. 证书格式
    final certificateFormat = readByte();

    // 5. 发卡机构标识（cn8）
    final issuerIdBytes = readBytes(4);

    // 6. 证书失效日期：n4，MMYY，按 BCD 解码。
    final expiryBytes = readBytes(2);
    final month = _decodeBcdByte(expiryBytes[0]);
    final shortYear = _decodeBcdByte(expiryBytes[1]);

    if (month < 1 || month > 12) {
      throw FormatException('证书失效月份无效：$month');
    }

    // 两位年份的世纪解释应与证书管理规则保持一致。
    // 此处采用 2000–2099 的项目约定，必要时应调整。
    final expiryYear = 2000 + shortYear;

    // 7. 证书序列号
    final serialNumberBytes = readBytes(3);

    // 8. 公钥签名算法标识
    final signatureAlgorithm = readByte();

    // 9. 公钥加密算法标识（表中注明保留项）
    final encryptionAlgorithm = readByte();

    // 10. 公钥参数标识
    final publicKeyParameter = readByte();

    // 11. 公钥长度
    final publicKeyLength = readByte();

    // 12. 发卡机构公钥
    final issuerPublicKey = readBytes(33);

    // 13. 数字签名（64 字节）：不解析，仅按长度跳过
    readBytes(64);

    if (p != data.length) {
      throw FormatException('证书字段长度计算异常：$p/${data.length}');
    }

    if (recordHeader != 0x24) {
      throw FormatException('记录头错误：应为 0x24，实际为 0x${_hexByte(recordHeader)}');
    }

    if (certificateFormat != 0x12) {
      throw FormatException(
        '证书格式错误：应为 0x12，实际为 0x${_hexByte(certificateFormat)}',
      );
    }

    if (publicKeyLength != 0x21) {
      throw FormatException(
        '公钥长度标识错误：应为 0x21，实际为 0x${_hexByte(publicKeyLength)}',
      );
    }

    if (publicKeyParameter != 0x00) {
      throw FormatException('未知公钥参数标识：0x${_hexByte(publicKeyParameter)}');
    }

    return JtT1179IssuerCertificate(
      raw: data,
      recordHeader: recordHeader,
      serviceId: serviceId,
      caPublicKeyIndex: caPublicKeyIndex,
      certificateFormat: certificateFormat,
      issuerIdBytes: issuerIdBytes,
      expiryMonth: month,
      expiryYear: expiryYear,
      serialNumberBytes: serialNumberBytes,
      signatureAlgorithm: signatureAlgorithm,
      encryptionAlgorithm: encryptionAlgorithm,
      publicKeyParameter: publicKeyParameter,
      publicKeyLength: publicKeyLength,
      issuerPublicKey: issuerPublicKey,
    );
  }

  static int _decodeBcdByte(int value) {
    final high = (value >> 4) & 0x0F;
    final low = value & 0x0F;

    if (high > 9 || low > 9) {
      throw FormatException('无效 BCD 日期字节：0x${_hexByte(value)}');
    }

    return high * 10 + low;
  }

  static String _hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
}
