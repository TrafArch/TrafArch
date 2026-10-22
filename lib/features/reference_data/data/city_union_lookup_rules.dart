/// These transforms belong to positively recognized local-card profiles. A
/// public CU city code alone does not establish a Beijing/Suzhou/TFT profile.
enum CuLocalTerminalProfile { standard, beijing, suzhou, shenzhen, chengdu }

/// CU lookup semantics transcribed from TripReader 1.7.17 source dictionaries.
/// L0.n.a identifies carriers by longest prefix; N0.a.a and the four CU name
/// projections in N0.e.a supply historical names. Full evidence and boundaries
/// are recorded in ../work/upgrade-20261021/cu-city-coverage.json.
/// These rules do not infer the carrier required to authorize a terminal query.
abstract final class CityUnionLookupRules {
  static ({String terminal, String? regionCode, int? carrier})?
  identifyTerminal(
    String? raw, {
    String? cardCityCode,
    CuLocalTerminalProfile profile = CuLocalTerminalProfile.standard,
  }) {
    var key = (raw ?? '').replaceAll(' ', '').toUpperCase();
    if (key.isEmpty || !RegExp(r'^[0-9A-F]+$').hasMatch(key)) return null;
    String? region = switch (profile) {
      CuLocalTerminalProfile.beijing => '1000',
      CuLocalTerminalProfile.suzhou => '2150',
      CuLocalTerminalProfile.shenzhen => '5180',
      CuLocalTerminalProfile.chengdu => '6100',
      CuLocalTerminalProfile.standard => cardCityCode,
    };
    if (profile == CuLocalTerminalProfile.shenzhen) {
      if (key.length < 4) return null;
      key = '5180${key.substring(4)}';
    } else if (profile != CuLocalTerminalProfile.standard &&
        !(key.length >= 16 && key.startsWith(region!))) {
      key = '$region$key';
    }
    final carrier = carrierForKey(key);
    // Only a verified source carrier prefix identifies the raw CU namespace.
    // In particular raw3100 terminals can belong to Hangzhou, Shaoxing or
    // Jiaxing; inferring their region requires the original classification maps.
    if (carrier != null) region = key.substring(0, 4);
    return (terminal: key, regionCode: region, carrier: carrier);
  }

  /// The audited CU dictionaries cover mainland Chinese cities. Their local
  /// transaction time uses UTC+08, independent of the phone's time zone. Missing
  /// or malformed components stay unknown instead of becoming midnight/now.
  static DateTime? transactionTime(String? date, String? time) {
    if (date == null ||
        time == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        !RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(time)) {
      return null;
    }
    final value = DateTime.tryParse('${date}T${time}Z');
    if (value == null ||
        '${value.year.toString().padLeft(4, '0')}-'
                '${value.month.toString().padLeft(2, '0')}-'
                '${value.day.toString().padLeft(2, '0')}' !=
            date ||
        '${value.hour.toString().padLeft(2, '0')}:'
                '${value.minute.toString().padLeft(2, '0')}:'
                '${value.second.toString().padLeft(2, '0')}' !=
            time) {
      return null;
    }
    return value.subtract(const Duration(hours: 8));
  }

  static const carrierPrefixes = <String, int>{
    '2000110': 2,
    '2000111': 2,
    '2000112': 2,
    '20001122': 4,
    '2000114': 1,
    '2000115': 1,
    '20001151': 2,
    '2000116': 1,
    '2000116040': 7,
    '2000117': 1,
    '2000118': 1,
    '2000119': 1,
    '200012': 40,
    '200014': 41,
    '200022': 2,
    '20002222': 4,
    '2000260': 13,
    '2000261': 7,
    '200030': 3,
    '200032': 25,
    '200041': 6,
    '200051': 24,
    '200052': 22,
    '200062': 11,
    '200063': 23,
    '200064': 21,
    '200074': 5,
    '10000': 1,
    '100011': 25,
    '100011001910': 40,
    '1000300': 2,
    '100030079': 7,
    '100030082': 4,
    '100030083': 4,
    '100030084': 4,
    '100030085': 4,
    '100030089': 7,
    '100030091': 5,
    '10004000': 26,
    '10004004': 40,
    '51802': 1,
    '51803': 1,
    '518036': 7,
    '51804': 2,
    '51805': 1,
    '51806': 2,
    '518079': 7,
    '518084': 21,
    '518085': 21,
    '518096': 21,
    '215001': 1,
    '215002': 6,
    '215003': 2,
    '21500B': 25,
    '215010': 7,
    '215011': 40,
    '25500100': 1,
    '25500200': 1,
    '31200100': 1,
  };

  static int? carrierForKey(String key) {
    for (var length = key.length; length >= 5; length--) {
      final carrier = carrierPrefixes[key.substring(0, length)];
      if (carrier != null) return carrier;
    }
    return null;
  }

  static (String, String)? presentation(int? carrier) => switch (carrier) {
    1 => ('bus', '公交'),
    2 => ('metro', '地铁'),
    3 => ('ferry', '轮渡'),
    4 => ('rail', '铁路'),
    5 => ('maglev', '磁浮'),
    6 => ('taxi', '出租车'),
    7 => ('tram', '有轨电车'),
    11 => ('custom_bus', '定制公交'),
    13 => ('brt', 'BRT'),
    _ => null,
  };

  // UTC epoch milliseconds, exclusive upper bound. A missing transaction time
  // keeps the package's current name rather than guessing a historical name.
  static const historicalNames = <String, (int, String, String)>{
    '2000110234': (1726862400000, '2号线', '徐泾东'),
    '2000110248': (1726862400000, '2号线', '东昌路'),
    '2000110263': (1726862400000, '2号线', '浦东国际机场'),
    '2000110418': (1726862400000, '4号线', '浦电路'),
    '2000110918': (1726862400000, '9号线', '松江南站'),
    '2000111528': (1726862400000, '15号线', '华泾西'),
    '2000111722': (1726862400000, '17号线', '诸光路'),
    '2000749001': (1726862400000, '磁浮线', '浦东国际机场'),
    '331000060024': (1706731200000, '6号线', '之浦路'),
    '331000090054': (1643140800000, '9号线', '余杭高铁站'),
    '335000990001': (1643140800000, '杭海城际', '余杭高铁站'),
    '337000870031': (1735502400000, '2号线', '镜湖医院'),
  };

  static (String?, String?) labelsAt(
    String sourceKey,
    DateTime? time,
    String? line,
    String? station,
  ) {
    final rule = historicalNames[sourceKey];
    if (rule != null && time != null && time.millisecondsSinceEpoch < rule.$1) {
      return (rule.$2, rule.$3);
    }
    return (line, station);
  }
}
