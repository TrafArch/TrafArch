import '../../../protocols/transit/card_parser.dart';
import '../domain/archive_context.dart';

String? archiveJourneySystemId(ArchiveContext context) =>
    context.systemId == 'TU' ? CardParserIds.tunion : context.systemId;
