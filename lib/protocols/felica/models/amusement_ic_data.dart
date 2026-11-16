library;

/// Frozen Amusement IC identification evidence, without network account data.
///
/// Access Code may be absent even when the card's DFC or raw blocks were read.
/// Restoring an archive never derives a code from its IDm or reinterprets raw
/// SPAD0 with a newer decoder.
class AmusementIcData {
  final String? accessCode;
  final String? issuer;
  final int? dataFormatCode;
  final String? spad0Hex;
  final String? idBlockHex;
  final String? note;

  const AmusementIcData({
    this.accessCode,
    this.issuer,
    this.dataFormatCode,
    this.spad0Hex,
    this.idBlockHex,
    this.note,
  });

  String? get formattedAccessCode {
    final code = accessCode;
    if (code == null || !_isAccessCode(code)) return null;
    return [
      for (var index = 0; index < code.length; index += 4)
        code.substring(index, index + 4),
    ].join(' ');
  }

  Map<String, Object?> toJson() => {
    'accessCode': accessCode,
    'issuer': issuer,
    'dataFormatCode': dataFormatCode,
    'spad0Hex': spad0Hex,
    'idBlockHex': idBlockHex,
    'note': note,
  };

  /// Missing optional fields are retained as unknown. Corrupt known fields
  /// invalidate the object rather than becoming plausible display values.
  static AmusementIcData? fromJson(Object? value) {
    if (value is! Map) return null;

    final accessCode = value['accessCode'];
    final issuer = value['issuer'];
    final dataFormatCode = value['dataFormatCode'];
    final spad0Hex = value['spad0Hex'];
    final idBlockHex = value['idBlockHex'];
    final note = value['note'];

    if (accessCode != null &&
        (accessCode is! String || !_isAccessCode(accessCode))) {
      return null;
    }
    if (issuer != null && issuer is! String) return null;
    if (note != null && note is! String) return null;
    if (dataFormatCode != null &&
        (dataFormatCode is! int ||
            dataFormatCode < 0 ||
            dataFormatCode > 0xFFFF)) {
      return null;
    }
    if (spad0Hex != null && (spad0Hex is! String || !_isBlockHex(spad0Hex))) {
      return null;
    }
    if (idBlockHex != null &&
        (idBlockHex is! String || !_isBlockHex(idBlockHex))) {
      return null;
    }
    if (accessCode == null &&
        issuer == null &&
        dataFormatCode == null &&
        spad0Hex == null &&
        idBlockHex == null &&
        note == null) {
      return null;
    }

    return AmusementIcData(
      accessCode: accessCode as String?,
      issuer: issuer as String?,
      dataFormatCode: dataFormatCode as int?,
      spad0Hex: spad0Hex as String?,
      idBlockHex: idBlockHex as String?,
      note: note as String?,
    );
  }

  static bool _isAccessCode(String value) =>
      value.length == 20 && _accessCodePattern.hasMatch(value);

  static bool _isBlockHex(String value) =>
      value.length == 32 && _blockHexPattern.hasMatch(value);

  static final _accessCodePattern = RegExp(r'^[0-9]{20}$');
  static final _blockHexPattern = RegExp(r'^[0-9A-Fa-f]{32}$');
}
