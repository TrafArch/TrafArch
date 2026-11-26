import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_record_count.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/protocols/felica/models/amusement_ic_data.dart';

import 'support/test_database.dart';

const _code = '50101234567890123456';
const _idm = '012E3A4B5C6D7E8F';
const _fingerprint = 'felica:amusement_ic:access-code:$_code';
const _identity = CardArchiveIdentity(
  cardType: 'amusement_ic',
  officialName: 'Amusement IC（Aime）',
  issuerName: 'Aime',
  identificationSource: CardIdentificationSources.parserOnly,
);
const _data = AmusementIcData(
  accessCode: _code,
  issuer: 'Aime',
  dataFormatCode: 0x0078,
  idBlockHex: '012E3A4B5C6D7E8F0078000000000000',
  spad0Hex: '893D691806ECCFEF90C8773D41EEE231',
);

String _snapshot({bool malformed = false, AmusementIcData data = _data}) =>
    CardSessionSnapshot(
      context: const ArchiveContext(
        systemId: 'felica_amusement_ic',
        applicationId: 'felica-system:88B4/service:000B',
        observedFields: {
          'cardNumber': false,
          'balanceFen': false,
          'transactionCount': false,
        },
      ),
      extensions: {
        'amusementIc': {
          'version': malformed ? 99 : 1,
          'identityKind': 'amusement-ic-access-code',
          'idm': _idm,
          'data': data.toJson(),
        },
      },
    ).encode();

Future<String> _save(
  CardRepository repository, {
  bool malformed = false,
  AmusementIcData data = _data,
  CardArchiveIdentity identity = _identity,
}) async {
  await repository.saveIdentity(
    fingerprint: _fingerprint,
    identity: identity,
    sessionDataJson: _snapshot(malformed: malformed, data: data),
    readAt: DateTime(2026, 11, 16, malformed ? 12 : 11),
  );
  return (await repository.getAllCards()).single.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AIC summaries compare projected identity by value and include batch-only brand changes', () async {
    final database = testDatabase();
    final repository = CardRepository(database);
    final cardId = await _save(repository);
    final first = (await watchArchiveCardSummaries(repository).first).single;
    final replay = (await watchArchiveCardSummaries(repository).first).single;
    expect(replay, first);
    expect(replay.hashCode, first.hashCode);
    await database
        .into(database.cardReadBatches)
        .insert(
          CardReadBatch(
            id: 'new-brand',
            cardId: cardId,
            cardFingerprint: _fingerprint,
            readAt: DateTime(2026, 11, 16, 13).millisecondsSinceEpoch,
            parseVersion: 1,
            payloadJson: _snapshot(
              data: const AmusementIcData(
                accessCode: _code,
                issuer: 'Banapassport',
              ),
            ),
          ),
        );
    final changed = (await watchArchiveCardSummaries(repository).first).single;
    expect(changed.card, first.card);
    expect(changed.recordCount, first.recordCount);
    expect(changed, isNot(first));
  });
}
