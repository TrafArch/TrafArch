import 'station_codes.dart';
export 'station_codes.dart' show RegionLineCoverage;

/// 地区覆盖概况（知识库页地区列表一行）。
class RegionOverview {
  final String system;
  final String code;
  final String name;
  final String? province;
  final int lineCount;
  final int stationCount;

  const RegionOverview({
    this.system = 'tu',
    required this.code,
    required this.name,
    this.province,
    required this.lineCount,
    required this.stationCount,
  });
}

/// 地区线路覆盖查询契约：知识库页的惰性瓦片只依赖这两个方法。
/// TU 走原始地区表直查，CU 走独立包原始表，互不耦合。
abstract class LiveRegionLines {
  List<RegionOverview> queryOverviews();

  Future<List<RegionLineCoverage>> linesForRegion(
    String cityKey,
    String system,
  );
}

class LiveRegionDataset extends StationDataset {
  LiveRegionDataset(LiveRegionLines db, RegionOverview overview)
    : _db = db,
      _overview = overview,
      super(
        file: '${overview.system}:${overview.code}',
        cityCode: overview.code,
        cityName: overview.name,
        province: overview.province,
        system: overview.system,
        kind: 'mixed',
        codes: const {},
      );

  final LiveRegionLines _db;
  final RegionOverview _overview;

  RegionOverview get overview => _overview;

  @override
  bool get isLazy => true;

  @override
  int get entryCountOverride => _overview.stationCount;

  @override
  int get lineCountOverride => _overview.lineCount;

  Future<List<RegionLineCoverage>>? _linesFuture;

  @override
  Future<List<RegionLineCoverage>> linesForDisplay() => linesOnce();

  Future<List<RegionLineCoverage>> linesOnce() {
    final city = cityCode;
    if (city == null || city.isEmpty) {
      return Future<List<RegionLineCoverage>>.value(const []);
    }
    return _linesFuture ??= _db.linesForRegion(city, _overview.system);
  }

  @override
  Future<List<StationCodeEntry>> lazyEntries() async {
    final lines = await linesOnce();
    return [
      for (final l in lines)
        for (final s in l.stations)
          StationCodeEntry(
            code: '',
            line: l.line == '未标注线路' ? null : l.line,
            station: s,
            system: _overview.system,
          ),
    ];
  }
}
