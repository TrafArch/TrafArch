/// Decoded display fields from a Beijing TU 0x1E line/station field.
///
/// Raw codes are exact slices of the input, including leading zeros and case.
class BeijingBusDecodeResult {
  /// Four HEX characters at offsets [0, 4), before decimal route decoding.
  final String rawLineCode;

  /// All four HEX characters at offsets [4, 8), including the ordinal marker.
  final String rawStationCode;

  /// Four HEX characters at offsets [8, 12).
  final String rawOperatorCode;

  /// Simplified Chinese display text from the original Beijing bus rules.
  final String? lineLabel;

  /// A stop ordinal (e.g. 第10站), never an inferred station name.
  final String? stationLabel;

  const BeijingBusDecodeResult({
    required this.rawLineCode,
    required this.rawStationCode,
    required this.rawOperatorCode,
    this.lineLabel,
    this.stationLabel,
  });
}

final _beijingBusField = RegExp(r'^[0-9A-Fa-f]{14}$');

/// Decodes a complete seven-byte TU `txLine` / 0x1E `lineStationCode` field.
///
/// Only city `1000` and exactly 14 HEX characters are accepted. A zero line
/// code or malformed field returns null. A valid but unlabeled route retains
/// its raw segments with null labels. Unknown operators/categories retain the
/// original `其他N` fallback; that label is not a verified route name.
///
/// This is a bus display fallback: the caller must establish bus mode and apply
/// any exact station/BRT database match first. The final byte has no display
/// semantics in the original Beijing branch.
///
/// Sources in TripReader-bus-location-20261020/source:
/// - jadx-simple/sources/p031L0/AbstractC0299a0.java, m764r:1107–1123,
///   7564–8135 (simplified Chinese labels and the entire city 1000 branch).
/// - jadx/sources/p040O0/C0597u0.java:669–684 (station display gate).
/// String helpers are p015F/AbstractC0144e.java: m463g prefixes the number,
/// while m465i/m466j/m467k/m469m concatenate their arguments in order.
/// Unlike the original UI, a zero ordinal deliberately has no display label.
BeijingBusDecodeResult? decodeBeijingBus({
  required String cityCode,
  required String field,
}) {
  if (cityCode != '1000' ||
      field.length != 14 ||
      !_beijingBusField.hasMatch(field)) {
    return null;
  }

  final rawLineCode = field.substring(0, 4);
  final line = int.parse(rawLineCode, radix: 16);
  if (line == 0) return null;

  final rawStationCode = field.substring(4, 8);
  final rawOperatorCode = field.substring(8, 12);
  final lineLabel = _decodeLine(line, rawOperatorCode.toUpperCase());
  String? stationLabel;
  if (lineLabel != null && rawStationCode.startsWith('00')) {
    final ordinal = int.parse(rawStationCode.substring(2), radix: 16);
    if (ordinal > 0) stationLabel = '第$ordinal站';
  }

  return BeijingBusDecodeResult(
    rawLineCode: rawLineCode,
    rawStationCode: rawStationCode,
    rawOperatorCode: rawOperatorCode,
    lineLabel: lineLabel,
    stationLabel: stationLabel,
  );
}

String? _decodeLine(int line, String operatorCode) {
  final number = line % 1000;
  switch (operatorCode) {
    case '0001':
      return _decodeMainOperator(line);
    case '0012':
      return 'T$number';
    case '0013':
      return line ~/ 1000 == 24 ? '专$number' : '其他$number';
    case '0014':
      return '运通$number';
    case '001F':
    case '0020':
      return number >= 1 && number < 80 ? '密$number' : '郊$number';
    case '0021':
      return '昌$number';
    case '0023':
    case '0024':
      return switch (number) {
        1 || 2 => '兴航城$number',
        36 => '兴环一线',
        60 => '兴西环线',
        330 => '兴环二线',
        680 => '兴68',
        720 => '兴72内',
        721 => '兴72外',
        _ => '兴$number',
      };
    case '0027':
      return '通$number';
    case '002C':
      return switch (line) {
        21012 => '顺42',
        22074 => '国门智慧城专线',
        57566 => '顺73',
        _ => '顺$number',
      };
    case '002D':
      // Simple JADX omits the L7436 -> L7439 jump. The original
      // apktool/smali/L0/a0.smali:41473–41508 confirms 61 <= line < 100
      // reaches the subtraction below, after these five special cases.
      return switch (line) {
        71 => '空港10',
        72 => '空港15',
        74 => '空港11',
        75 => '空港5区间',
        83 => '空港3区间',
        >= 61 && < 100 => '空港${number - 60}',
        _ => '其他$number',
      };
    case '002E':
      return '平$number';
    case '002F':
      return line == 53090 ? '平谷–三河' : '郊$number';
    default:
      return '其他$number';
  }
}

String? _decodeMainOperator(int line) {
  final number = line % 1000;
  return switch (line ~/ 1000) {
    0 || 30 || 50 => '$number',
    2 => '$number区间',
    11 => switch (number) {
      1 => '雄安高铁巴士1线',
      2 => '雄安高铁巴士2线',
      52 => '雄安高铁巴士2线旅游专线',
      _ => null,
    },
    12 => '通医专线$number',
    13 => switch (number) {
      501 => '朝阳文旅公交专线',
      502 => '朝阳文旅公交专线区间',
      _ => '通游专线$number',
    },
    21 => 'C$number',
    22 => 'F$number',
    23 => 'X$number',
    24 => '专$number',
    28 => number == 101 ? 'S101' : '其他$number',
    29 => 'T$number',
    31 => '房$number',
    32 => 'Y$number',
    33 => 'M$number',
    34 => 'H$number',
    37 => _commuterLabels[number] ?? '$number通勤快车',
    // Unmapped 38xxx codes have a category label only in the original.
    38 => _quickDirectLabels[number] ?? '快速直达专线',
    40 => _specialLabels[number] ?? '其他$number',
    42 => '临$number',
    43 => '特$number',
    51 => '$number内',
    52 => '$number外',
    55 => '特$number内',
    56 => '特$number外',
    57 => '$number快内',
    58 => '$number快外',
    60 => '$number快',
    62 => '夜$number',
    _ => '其他$number',
  };
}

// Category 37, JADX L7764–L7782.
const _commuterLabels = <int, String>{
  100: '凤河营通勤班车',
  833: '通勤朱家坟',
  844: '通勤礼贤',
  848: '通勤海子角',
  890: '通勤苹果园',
  917: '通勤东湖港',
  918: '通勤关上',
  951: '通勤石花洞',
  955: '通勤东方太阳城',
  969: '通勤向阳',
};

// Category 38, JADX L7646–L7740: 44 numbered mappings and two named routes.
const _quickDirectLabels = <int, String>{
  21: '快速直达专线139',
  25: '快速直达专线25',
  52: '快速直达专线52',
  61: '快速直达专线61',
  81: '快速直达专线81',
  103: '快速直达专线21',
  104: '快速直达专线36',
  120: '快速直达专线141',
  153: '快速直达专线153',
  157: '快速直达专线157',
  159: '快速直达专线213',
  160: '快速直达专线160',
  161: '快速直达专线161',
  163: '快速直达专线163',
  165: '快速直达专线165',
  183: '快速直达专线183',
  202: '快速直达专线22',
  203: '快速直达专线23',
  207: '快速直达专线207',
  210: '快速直达专线91',
  211: '快速直达专线211',
  213: '快速直达专线109',
  215: '快速直达专线215',
  302: '快速直达专线24',
  305: '快速直达专线45',
  310: '快速直达专线97',
  315: '快速直达专线120',
  318: '快速直达专线131',
  325: '快速直达专线145',
  326: '快速直达专线146',
  329: '快速直达专线181',
  330: '快速直达专线182',
  403: '快速直达专线26',
  404: '快速直达专线39',
  412: '快速直达专线178',
  413: '快速直达专线179',
  503: '快速直达专线15',
  706: '快速直达专线54',
  806: '快速直达专线58',
  807: '快速直达专线59',
  903: '快速直达专线35',
  907: '快速直达专线94',
  908: '儿研所专线',
  911: '北京后花园临线',
  921: '快速直达专线201',
  923: '快速直达专线203',
};

// Category 40, JADX L7801–L7819.
const _specialLabels = <int, String>{
  1: '燕郊专线',
  113: '集体出行3',
  121: '北京密码通勤班车',
  122: '高家坡班车',
  404: '北京朝阳站地铁摆渡车',
  405: '北京丰台站夜间摆渡车',
  406: '副中心三大建筑摆渡车',
  903: '北京妇产医院东院专线',
  904: '少年宫专线',
};
