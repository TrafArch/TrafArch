import 'journey_presentation.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

class TripCardPresentation<S extends Enum> {
  const TripCardPresentation({
    required this.info,
    required this.source,
    required this.mode,
    required this.dateText,
    required this.remote,
    this.onDiagnostics,
    this.journeyEvent,
  });

  final TripEntryInfo info;
  final S source;
  final TripModeFilter mode;
  final String dateText;
  final bool remote;
  final void Function()? onDiagnostics;
  final JourneyEvent<TripEntryInfo>? journeyEvent;
}
