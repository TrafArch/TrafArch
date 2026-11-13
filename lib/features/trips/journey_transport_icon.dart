import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'trip_filters.dart';

/// Uses the journey's resolved city, never the card issuer or a station-name guess.
class JourneyTransportIcon extends StatelessWidget {
  const JourneyTransportIcon({
    super.key,
    required this.mode,
    required this.cityLabel,
    required this.isCrossCity,
  });

  final TripModeFilter mode;
  final String? cityLabel;
  final bool isCrossCity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(
      mode == TripModeFilter.bus
          ? Icons.directions_bus_outlined
          : Icons.subway_outlined,
      color: scheme.primary,
      size: 21,
    );
    final city = _canonicalCity(cityLabel);
    final logo = mode == TripModeFilter.rail && !isCrossCity
        ? _metroLogos[city]
        : null;
    if (logo == null) return fallback;
    return SvgPicture.asset(
      'assets/metro/metro_logo_$logo.svg',
      width: 21,
      height: 21,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      placeholderBuilder: (_) => fallback,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

String? _canonicalCity(String? label) {
  var city = label?.trim();
  if (city == null || city.isEmpty) return null;
  if (city.endsWith('市')) city = city.substring(0, city.length - 1);
  return switch (city) {
    '臺北' => '台北',
    '臺中' => '台中',
    '桃園' => '桃园',
    '澳門' || '澳门特别行政区' || '澳門特別行政區' => '澳门',
    '香港特别行政区' || '香港特別行政區' => '香港',
    _ => city,
  };
}

// Explicit names avoid homophone matches (e.g. 台州/泰州 and 苏州/宿州).
// Values retain the supplied filenames, including urumqi, huhhot and newtaipei.
const _metroLogos = <String, String>{
  '北京': 'beijing',
  '长春': 'changchun',
  '长沙': 'changsha',
  '常州': 'changzhou',
  '成都': 'chengdu',
  '重庆': 'chongqing',
  '大连': 'dalian',
  '东莞': 'dongguan',
  '佛山': 'foshan',
  '福州': 'fuzhou',
  '广州': 'guangzhou',
  '贵阳': 'guiyang',
  '海宁': 'haining',
  '杭州': 'hangzhou',
  '哈尔滨': 'harbin',
  '合肥': 'hefei',
  '香港': 'hongkong',
  '呼和浩特': 'huhhot',
  '济南': 'jinan',
  '金华': 'jinhua',
  '高雄': 'kaohsiung',
  '昆明': 'kunming',
  '兰州': 'lanzhou',
  '柳州': 'liuzhou',
  '洛阳': 'luoyang',
  '澳门': 'macau',
  '南昌': 'nanchang',
  '南京': 'nanjing',
  '南宁': 'nanning',
  '南通': 'nantong',
  '新北': 'newtaipei',
  '宁波': 'ningbo',
  '青岛': 'qingdao',
  '上海': 'shanghai',
  '绍兴': 'shaoxing',
  '沈阳': 'shenyang',
  '深圳': 'shenzhen',
  '石家庄': 'shijiazhuang',
  '苏州': 'suzhou',
  '台中': 'taichung',
  '台北': 'taipei',
  '太原': 'taiyuan',
  '台州': 'taizhou',
  '桃园': 'taoyuan',
  '天津': 'tianjin',
  '乌鲁木齐': 'urumqi',
  '温州': 'wenzhou',
  '芜湖': 'wuhu',
  '无锡': 'wuxi',
  '厦门': 'xiamen',
  '西安': 'xian',
  '徐州': 'xuzhou',
  '郑州': 'zhengzhou',
  '武汉': 'wuhan',
};
