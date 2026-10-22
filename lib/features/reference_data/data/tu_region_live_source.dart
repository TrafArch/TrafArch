import '../domain/station_codes.dart';
import '../domain/region_db_store.dart';
import 'tu_station_repository.dart';

/// 把原始地区表直查包装成 [LiveStationSource]：
/// 替换旧的 TU 派生索引，供 `StationCodeTable` 的 0x1A / 0x1E 通道使用。
class TuRegionLiveSource implements LiveStationSource, LiveRegionLines {
  TuRegionLiveSource(this.repository);

  final TuStationRepository repository;

  @override
  String get system => 'tu';

  @override
  String? get queryIssue => repository.queryIssue;

  @override
  StationCodeEntry? lookupEntry(String cityKey, String key) {
    final direct = repository.queryOverride(cityKey, key);
    final rows = repository.findByKey(cityKey, key);
    if (direct != null) {
      return direct.toEntry(
        original: rows.length == 1 ? rows.single.toEntry() : null,
      );
    }
    final entries = rows.map(repository.entryForRecord).toList();
    final identities = entries.map((r) => (r.line, r.station, r.kind)).toSet();
    return identities.length == 1 ? entries.first : null;
  }

  @override
  String? lookupLineNameDigits(String cityKey, String digits) =>
      repository.lookupLineName(cityKey, digits);

  @override
  List<StationCodeEntry> fragLineStation(
    String cityKey,
    String lineNum,
    String stationNum,
  ) => repository
      .fragLineStation(cityKey, lineNum, stationNum)
      .map(repository.entryForRecord)
      .toList();

  @override
  List<StationCodeEntry> fragStation(String cityKey, String stationNum) =>
      repository
          .fragStation(cityKey, stationNum)
          .map(repository.entryForRecord)
          .toList();

  @override
  List<StationCodeEntry> fragLine(String cityKey, String lineNum) => repository
      .fragLine(cityKey, lineNum)
      .map(repository.entryForRecord)
      .toList();

  @override
  Iterable<StationCodeEntry> lineNameEntryCandidates(String cityKey) =>
      repository.entriesOfRegion(cityKey).map(repository.entryForRecord);

  @override
  List<StationCodeEntry> lookupLineStationTail(
    String cityKey,
    String lineDigits,
    String stationTail,
  ) => repository
      .lineStationTail(cityKey, lineDigits, stationTail)
      .map(repository.entryForRecord)
      .toList();

  @override
  List<StationDataset> lazyDatasets() => [
    for (final o in repository.queryOverviews()) LiveRegionDataset(this, o),
  ];

  @override
  List<RegionOverview> queryOverviews() => repository.queryOverviews();

  @override
  Future<List<RegionLineCoverage>> linesForRegion(
    String cityKey,
    String system,
  ) async {
    final byLine = <String, Set<String>>{};
    for (final r in repository.entriesOfRegion(cityKey)) {
      final line = (r.lineName ?? '').trim();
      final key = line.isEmpty ? '未标注线路' : line;
      final station = (r.stationName ?? '').trim();
      if (station.isEmpty) continue;
      (byLine[key] ??= <String>{}).add(station);
    }
    final out = <RegionLineCoverage>[];
    byLine.forEach((line, stations) {
      final list = stations.toList()..sort();
      out.add(RegionLineCoverage(line, list));
    });
    out.sort((a, b) => _compareLine(a.line, b.line));
    return out;
  }

  @override
  int get totalEntryCount => repository.stationCount;

  @override
  int get datasetCount => repository.datasetCount;

  static int _compareLine(String a, String b) {
    const unlabeled = '未标注线路';
    if (a == unlabeled && b != unlabeled) return 1;
    if (b == unlabeled && a != unlabeled) return -1;
    final an = _lineNumber(a);
    final bn = _lineNumber(b);
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    if (an != null && bn == null) return -1;
    if (an == null && bn != null) return 1;
    return a.compareTo(b);
  }

  static int? _lineNumber(String line) {
    final m = RegExp(r'(\d+)').firstMatch(line);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}
