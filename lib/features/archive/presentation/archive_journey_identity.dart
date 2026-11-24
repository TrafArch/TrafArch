import '../../../protocols/transit/card_parser.dart';
import '../domain/archive_context.dart';

String? archiveJourneySystemId(
  ArchiveContext context, {
  bool shanghaiRecharge = false,
}) => shanghaiRecharge
    ? CardParserIds.shanghaiTunion
    : context.systemId == 'TU'
    ? CardParserIds.tunion
    : context.systemId;
