import '../domain/station_codes.dart';
import 'tu_region_live_source.dart';

/// Adds lossless prefix/history queries without changing the legacy exact-key
/// and fragment interfaces used by the knowledge-base browser.
class TuLookupLiveSource extends TuRegionLiveSource
    implements TuRailPrefixSource {
  TuLookupLiveSource(super.repository);

  @override
  StationMatch matchTuRailKey({
    required String cityCode,
    required String key,
    DateTime? time,
  }) => repository.matchRailPrefix(city: cityCode, key: key, time: time);
}
