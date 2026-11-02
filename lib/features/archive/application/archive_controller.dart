import 'package:drift/drift.dart' show Value;

import '../../../protocols/transit/card_parser.dart';
import '../../transit_analysis/balance_interpretation.dart';
import '../../transit_analysis/tunion_analysis_models.dart';
import '../../transit_analysis/process_journey_positions.dart';
import '../../../platform/storage/log_exporter.dart';
import '../../../platform/nfc/nfc_models.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_process_parser.dart';
import 'card_records_export.dart';
import 'cu_archive_projection.dart';
import '../domain/card_session_snapshot.dart';
import '../domain/pending_card_save.dart';
import '../data/card_repository.dart';
import '../data/app_database.dart';
import '../domain/archive_balance.dart';
import 'archive_history.dart';
import 'archive_application_display.dart';
import 'card_identification_service.dart';
import '../../../shared/application/owned_notifier.dart';
import '../../scan/domain/captured_frame.dart';
import '../../scan/domain/scan_presentation.dart';

/// Owns pending-save identity and archive side effects. A dialog can only act
/// on the exact read that was shown, even after the next NFC session starts.
class ArchiveController extends OwnedNotifier {
  ArchiveController(this.repository, this.exporter, this.log);
  final CardRepository repository;
  final LogExporter exporter;
  final void Function(String) log;
  PendingCardSave? pending;
  IdentifiedCard? identified;
  String? fingerprint;
  String? autoSaveNotice;
  int _generation = 0;
  final Set<Future<bool>> _writes = {};

  void clearSession() {
    ++_generation;
    pending = null;
    identified = null;
    fingerprint = null;
    autoSaveNotice = null;
    notifyListeners();
  }

  void stage(
    ScanPresentation view,
    String attemptId,
    DateTime readAt,
    List<CapturedFrame> frames, {
    List<NfcMetadataIssue> metadataIssues = const [],
  }) {
    if (disposed) return;
    final parsed = view.parsedCard;
    if (parsed == null) {
      return; // Bank/FeliCa archive policy is not invented here.
    }
    try {
      final identity = CardIdentificationService(view.knowledge)
          .identify(parsed, analysisIdentity: view.analysis?.identity);
      if (identity == null) return;
      final balance = view.balanceInterpretation;
      final separateObservation =
          CardParserIds.isTUnionFamily(parsed.parserId) &&
          balance?.semantics != BalanceSemantics.direct;
      // Ordinary cards retain their established currency policy. Unknown TU
      // identities keep the integer but cannot acquire a currency from metadata.
      final currency = separateObservation
          ? balance?.observedCurrency
          : view.cardCurrency.code;
      final packages = <String, dynamic>{
        for (final e in view.knowledge.packageVersions.entries)
          e.key: {
            'contentVersion': e.value,
            'sha256': view.knowledge.packageHashes[e.key],
          },
      };
      final trips = view.analysis?.trips ?? const <TransitTrip>[];
      // Archive protocol observations before the current-page presentation
      // suppresses a same-mode record from a different file.
      final railSources = <TUnionProcessRecord>[];
      final rails = <TransitRecord>[];
      final busSources = <TUnionProcessRecord>[];
      final buses = <BusTransitRecord>[];
      for (final record in parsed.transitProcessRecords) {
        if (record.sfi != 0x1A || record.isBlank) continue;
        final rail = record.railTransit;
        final bus = record.busTransit;
        if (rail != null) {
          rails.add(rail);
          railSources.add(record);
        }
        if (bus != null) {
          buses.add(bus);
          busSources.add(record);
        }
      }
      if (rails.isEmpty) {
        for (final record in parsed.transitProcessRecords) {
          if (record.sfi != 0x1A ||
              record.recordNumber != 0 ||
              record.isBlank) {
            continue;
          }
          final rail = const TUnionProcessParser().parseRailTransit(
            1,
            record.raw,
          );
          if (rail != null) {
            rails.add(rail);
            railSources.add(record);
          }
        }
      }
      final transactionsObserved =
          parsed.transactionFileObserved ||
          parsed.transactions.isNotEmpty ||
          (parsed.parserId == CardParserIds.cityUnion &&
              view.cityUnionTransactions.isNotEmpty);
      final processPositions = buildProcessJourneyPositions(
        parsed.transitProcessRecords,
      );
      final context = ArchiveContext(
        systemId: parsed.parserId,
        applicationId: parsed.selectedAidHex,
        currencyCode: currency,
        minorUnitDigits: 2,
        timeZoneOffsetMinutes: null,
        extensions: {
          'captureDeviceOffsetMinutes': readAt.timeZoneOffset.inMinutes,
          if (separateObservation) 'balanceInterpretation': balance!.toJson(),
        },
        clockBasis: 'device-local-card-time-unverified',
        referencePackages: Map.unmodifiable(packages),
        observedFields: {
          'cardNumber': identity.cardNumber != null,
          'balanceFen': parsed.info.balanceFen != null,
          'transactionCount': transactionsObserved,
        },
      );
      final snapshot = CardSessionSnapshot(
        parseVersion: kTripParseVersion,
        context: context,
        extensions: {
          'captureAttemptId': attemptId,
          if (parsed.localCard?.info.isBmac == true)
            'beijingBmac': {
              'cardNumber': parsed.localCard!.info.cardNumber,
              'balanceFen': parsed.localCard!.info.observedBalance,
              'readError': parsed.localCard!.readError?.toString(),
              'observations': parsed.localCard!.extras.slots,
            },
          if (parsed.localCard?.info.isLNT == true)
            'lingnanTong': {
              'cardNumber': parsed.localCard!.info.cardNumber,
              'issuerCode': parsed.localCard!.info.issuerCode,
              'balanceFen': parsed.localCard!.info.observedBalance,
              'readError': parsed.localCard!.readError?.toString(),
              'observations': parsed.localCard!.extras.slots,
            },
          if (parsed.parserId == CardParserIds.shenzhenTunion &&
              parsed.localCard != null)
            'shenzhenTong': {
              'cardNumber': parsed.localCard!.info.cardNumber,
              'balanceFen': parsed.localCard!.info.observedBalance,
              'rawInfo': parsed.localCard!.info.rawInfo,
              'readError': parsed.localCard!.readError?.toString(),
              'observations': parsed.localCard!.extras.slots,
              'records': [
                for (final record in parsed.localCard!.records)
                  {
                    'recordNumber': record.recordNumber,
                    'fileSelector': record.fileSelector,
                    'response': record.response,
                    'hasError': record.hasError,
                  },
              ],
            },
          if (view.cityUnionTransactions.isNotEmpty)
            'cuProjection': captureCuProjection(view.cityUnionTransactions),
        },
        cardCityCode: view.cardCityCode,
        trips: view.analysis?.trips ?? const [],
        rails: rails,
        buses: buses,
        processTrips: view.cycleProcessTrips,
        rawEvidence: [
          for (final issue in metadataIssues)
            {
              'kind': 'native_metadata_issue',
              'sessionId': attemptId,
              ...issue.toJson(),
            },
          for (final frame in frames) frame.toJson(),
          for (final file in parsed.cityUnionFiles)
            {'kind': 'cu_file', 'parserId': parsed.parserId, ...file.toJson()},
          for (final record in parsed.transitProcessRecords)
            {
              'kind': 'tu_process_record',
              'sfi': record.sfi,
              'recordNumber': record.recordNumber,
              'recordNumberIsReliable': record.recordNumberIsReliable,
              'rawHex': record.rawHex,
            },
          for (final transaction in parsed.transactions)
            {'kind': 'tu_transaction', 'rawHex': transaction.rawHex},
        ],
        recordProvenance: {
          'parserId': parsed.parserId,
          'parseVersion': kTripParseVersion,
          'referencePackages': packages,
          for (var i = 0; i < trips.length; i++)
            'trips[$i]': {
              'parseVersion': kTripParseVersion,
              'referencePackages': packages,
              'rawHex': trips[i].rawHex,
              'terminalId': trips[i].terminalId,
              'ruleId': trips[i].location?.ruleId,
              'lineCode': trips[i].location?.lineCode,
              'stationCode': trips[i].location?.stationCode,
              'stationConfidence': trips[i].stationConfidence?.name,
            },
          for (var i = 0; i < rails.length; i++)
            'rails[$i]': {
              'parseVersion': kTripParseVersion,
              'referencePackages': packages,
              'rawHex': rails[i].rawHex,
              'sfi': railSources[i].sfi,
              'recordNumber': railSources[i].recordNumber,
              'capturedDisplay': captureRailApplicationDisplay(
                view.knowledge,
                rails[i],
              ),
            },
          for (var i = 0; i < buses.length; i++)
            'buses[$i]': {
              'parseVersion': kTripParseVersion,
              'referencePackages': packages,
              'rawHex': buses[i].rawHex,
              'sfi': busSources[i].sfi,
              'recordNumber': busSources[i].recordNumber,
              'capturedDisplay': captureBusApplicationDisplay(
                view.knowledge,
                buses[i],
              ),
            },
          for (var i = 0; i < view.cycleProcessTrips.length; i++)
            'cycle[$i]': {
              'parseVersion': kTripParseVersion,
              'referencePackages': packages,
              'rawHex': view.cycleProcessTrips[i].rawHex,
              'capturedDisplay': captureProcessDisplay(
                view.knowledge,
                view.cycleProcessTrips[i],
              ),
              if (processPositions[view.cycleProcessTrips[i]]?['live']
                  case final position?) ...{
                'sfi': 0x1E,
                'recordNumber': position,
                'recordNumberIsReliable': true,
              },
            },
          'rawApplicationSerial': parsed.info.applicationSerial,
          'rawCityCode': parsed.info.cityCode,
          'tuBalanceFen': parsed.info.balanceFen,
          'cuBalanceFen': parsed.cityUnionBalanceFen,
        },
      );
      identified = identity;
      fingerprint = identity.fingerprint;
      pending = PendingCardSave(
        pendingSaveId: attemptId,
        readAt: readAt,
        fingerprint: identity.fingerprint,
        identity: identity.identity,
        cardNumber: identity.cardNumber,
        balanceFen: parsed.info.balanceFen,
        currencyCode: currency,
        transactionCount: transactionsObserved
            ? (parsed.parserId == CardParserIds.cityUnion
                  ? view.cityUnionTransactions.length
                  : parsed.transactions.length)
            : null,
        sessionDataJson: snapshot.encode(),
      );
      notifyListeners();
    } catch (e) {
      log('卡片归档准备失败：$e');
    }
  }

  Future<bool> accept(String id) async {
    final item = pending;
    if (disposed || item == null || item.pendingSaveId != id) return false;
    final generation = _generation;
    pending = null;
    notifyListeners();
    final operation = _save(item);
    _writes.add(operation);
    final ok = await operation;
    _writes.remove(operation);
    if (!ok && !disposed && generation == _generation && pending == null) {
      pending = item; // Allow retry without losing the captured read.
      notifyListeners();
    }
    return ok;
  }

  Future<bool> _save(PendingCardSave item) async {
    try {
      await repository.db.transaction(() async {
        final existing =
            await (repository.db.select(repository.db.savedCards)
                  ..where((t) => t.cardFingerprint.equals(item.fingerprint)))
                .getSingleOrNull();
        final previousSource = existing == null
            ? null
            : (await ArchiveHistory(repository).load(existing.id))
                  .balanceSource;
        var payload = item.sessionDataJson;
        if (item.balanceFen == null &&
            previousSource != null &&
            payload != null) {
          payload = withRetainedBalanceSource(payload, previousSource);
        }
        await repository.saveIdentity(
          fingerprint: item.fingerprint,
          identity: item.identity,
          cardNumber: item.cardNumber,
          balanceFen: item.balanceFen,
          currencyCode: item.currencyCode,
          transactionCount: item.transactionCount,
          sessionDataJson: payload,
          parseVersion: kTripParseVersion,
          readAt: item.readAt,
        );
        // A late full observation may update the retained balance while the
        // newest envelope remains partial. Refresh only its source extension;
        // original capture batches and their timestamps remain immutable.
        final saved =
            await (repository.db.select(repository.db.savedCards)
                  ..where((t) => t.cardFingerprint.equals(item.fingerprint)))
                .getSingle();
        final latest = saved.sessionDataJson;
        final snapshot = latest == null
            ? null
            : CardSessionSnapshot.decode(latest);
        if (latest != null &&
            snapshot?.formatVersion == 3 &&
            !snapshotObservesBalance(snapshot)) {
          final history = await ArchiveHistory(repository).load(saved.id);
          var source = history.balanceSource;
          final readAt = item.readAt?.millisecondsSinceEpoch;
          // Equal timestamps are accepted by the repository. The just-saved
          // attempt identifies the winner even when the old scalar was equal.
          if (item.balanceFen != null &&
              readAt != null &&
              history.balanceObservedAt == readAt) {
            final captures = history.batches.where(
              (batch) =>
                  batch.decoded.snapshot?.extensions['captureAttemptId'] ==
                      item.pendingSaveId &&
                  snapshotBalanceMatches(saved, batch.decoded.snapshot),
            );
            if (captures.length == 1) {
              final capture = captures.single;
              source = ArchiveBalanceSource(
                payloadJson: capture.decoded.rawJson,
                batchId: capture.id,
                observedAt: readAt,
              );
            } else {
              source = null;
            }
          }
          final updated = withRetainedBalanceSource(latest, source);
          if (updated != latest) {
            await (repository.db.update(repository.db.savedCards)
                  ..where((t) => t.id.equals(saved.id)))
                .write(SavedCardsCompanion(sessionDataJson: Value(updated)));
          }
        }
        await repository.refreshDocument(saved.id);
      });
      return true;
    } catch (e) {
      log('卡片档案保存失败：$e');
      return false;
    }
  }

  void decline(String id) {
    if (pending?.pendingSaveId != id) return;
    pending = null;
    notifyListeners();
  }

  Future<void> autoSave() async {
    final item = pending;
    if (item == null) return;
    final generation = _generation;
    final ok = await accept(item.pendingSaveId);
    if (disposed || generation != _generation) return;
    autoSaveNotice = ok
        ? '已自动保存：${item.displayName}'
        : '自动保存失败：${item.displayName}';
    notifyListeners();
  }

  void clearNotice() {
    autoSaveNotice = null;
    notifyListeners();
  }

  Future<void> finishWrites() async => Future.wait(_writes.toList());

  Future<String> exportCards() async {
    try {
      final histories = await ArchiveHistory(repository).loadAll();
      if (histories.isEmpty) return '暂无卡片记录可导出';
      final now = DateTime.now();
      final content = buildArchiveHistoryExport(histories, exportedAt: now);
      final stamp = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      final path = await exporter.saveToDownloads(
        'transit_card_records_$stamp.txt',
        content,
      );
      return '已导出 ${histories.length} 张卡片到下载目录：$path';
    } catch (e) {
      log('卡片导出失败：$e');
      return '导出失败：$e';
    }
  }
}
