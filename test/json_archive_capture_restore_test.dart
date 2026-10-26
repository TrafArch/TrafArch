import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_balance.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';

void main() {
  test(
    'full import restores TU CU and retained balance with remapped card ID',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      await repository.saveIdentity(
        fingerprint: 'fingerprint-source',
        identity: const CardArchiveIdentity(cardType: 'china_tunion'),
        balanceFen: 100,
        currencyCode: 'CNY',
        readAt: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
      );
      final localId = (await repository.getAllCards()).single.id;
      final cu = CuTransactionView(
        record: CityUnionFileParser.parseWalletRecord(
          0x06,
          [
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            6,
            0x20,
            0,
            0x11,
            0x0A,
            1,
            0,
            0x20,
            0x24,
            9,
            0x20,
            0x12,
            0,
            0,
          ],
          kind: CityUnionTransactionKind.foreignConsumption,
          recordNumber: 5,
        ),
        transactionTime: DateTime.utc(2024, 9, 20, 4),
        regionCode: '2000',
        carrier: 2,
        location: ReferenceMatch(ReferenceMatchStatus.matched, const [
          StationCodeEntry(
            code: '000A',
            type: '地铁',
            line: '冻结线路',
            station: '冻结站名',
            system: 'cu',
            lineCode: '0010',
            stationCode: '0002',
          ),
        ]),
      );
      final captured = CardSessionSnapshot(
        context: const ArchiveContext(
          currencyCode: 'CNY',
          minorUnitDigits: 2,
          observedFields: {'balanceFen': true},
        ),
        trips: [
          TransitTrip(
            time: DateTime(2024, 9, 20, 12),
            amountFen: 300,
            overdraftLimitFen: 0,
            isConsume: true,
            typeName: '消费',
            sequence: 9,
            terminalId: '000123',
            lineLabel: '读取时线路',
            stationLabel: '读取时站点',
          ),
        ],
        extensions: {
          'observations': {'balanceFen': 500, 'currencyCode': 'CNY'},
          'cuProjection': captureCuProjection([cu]),
        },
      ).encode();
      final partial = withRetainedBalanceSource(
        const CardSessionSnapshot(
          context: ArchiveContext(observedFields: {'balanceFen': false}),
        ).encode(),
        ArchiveBalanceSource(
          payloadJson: captured,
          observedAt: 200,
          batchId: 'preserved-batch-id',
        ),
      );
      final source = CardArchiveDocument(
        card: SavedCard(
          id: 'source',
          cardFingerprint: 'fingerprint-source',
          cardType: 'china_tunion',
          identificationSource: 'unknown',
          balanceFen: 500,
          currencyCode: 'CNY',
          sessionDataJson: partial,
          createdAt: 100,
          updatedAt: 400,
          lastReadAt: 400,
        ),
        batches: [
          CardReadBatch(
            id: 'preserved-batch-id',
            cardId: 'source',
            cardFingerprint: 'fingerprint-source',
            readAt: 200,
            parseVersion: 1,
            payloadJson: captured,
          ),
        ],
        fieldObservationTimes: {'balanceFen': 200},
      );
      final decoded = CardArchiveBundle.decode(
        CardArchiveBundle(
          cards: [source],
          exportedAt: DateTime.utc(2026),
        ).encode(),
      );
      await repository.importDocuments(decoded.cards);
      final history = await ArchiveHistory(repository).load(localId);
      expect(history.card!.id, localId);
      expect(history.balanceSource!.batchId, 'preserved-batch-id');
      expect(history.balanceSource!.payloadJson, captured);
      expect(history.records.single.fields['stationLabel'], '读取时站点');
      final cuHistory = projectCuArchive(history);
      expect(cuHistory.issues, isEmpty);
      expect(cuHistory.transactions.single.location.value!.station, '冻结站名');
      expect(cuHistory.transactions.single.location.value!.stationCode, '0002');
      expect(cuHistory.transactions.single.record.recordNumber, 5);
      expect(cuHistory.transactions.single.record.rawHex, cu.record.rawHex);
      final exported = (await repository.exportDocuments()).single;
      expect(exported.card.sessionDataJson, partial);
      final restoredBatch = exported.batches.singleWhere(
        (batch) => batch.id == 'preserved-batch-id',
      );
      expect(restoredBatch.cardId, localId);
      expect(restoredBatch.payloadJson, captured);
    },
  );
}
