import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_journey_identity.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';

void main() {
  test('legacy TU identity matches the current generic parser', () {
    expect(
      archiveJourneySystemId(const ArchiveContext(systemId: 'TU')),
      CardParserIds.tunion,
    );
    expect(
      archiveJourneySystemId(
        const ArchiveContext(systemId: CardParserIds.tunion),
      ),
      CardParserIds.tunion,
    );
  });

  test('distinct parsers and unknown identities remain distinct', () {
    for (final id in [
      null,
      '',
      'unknown',
      CardParserIds.shanghaiTunion,
      CardParserIds.lingnanTunion,
      CardParserIds.cityUnion,
    ]) {
      expect(archiveJourneySystemId(ArchiveContext(systemId: id)), id);
    }
  });
}
