import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/transit/local/cards/lingnan_tong.dart';
import '../../../protocols/transit/local/cards/macau_pass_card.dart';
import '../../../protocols/transit/local/cards/shenzhentong.dart';
import '../../../protocols/transit/local/cards/wuhan_tong_card.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/local/trips/trip_dedup.dart';
import '../../../protocols/transit/local/trips/trip_records.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../../../protocols/transit/tunion/tunion_cash_log.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transport/transport_failure.dart';
import 'beijing_df1001_scan.dart';
import 'mot_bmac_scan.dart';
import 'registered_local_wallets.dart';
import 'tu_cu_wallet_scan.dart';

abstract class LocalCardReaderCallback {
  void onProgress(int percent);
  void onError(String message);
}

class NoopLocalCardReaderCallback implements LocalCardReaderCallback {
  const NoopLocalCardReaderCallback();
  @override
  void onProgress(int percent) {}
  @override
  void onError(String message) {}
}

class LocalReadOutcome {
  const LocalReadOutcome.transit({
    required this.readResult,
    required this.parsedCard,
    required this.applications,
  });
  final ReadResult readResult;
  final ParsedCard parsedCard;
  final List<ApplicationEvidence> applications;
}

typedef IsoDepScan = ({
  LocalReadOutcome? result,
  List<ApplicationEvidence> applications,
  Object? terminalError,
});

const _walletNames = {
  'lingnan_appy': '岭南通资料（PAY.APPY）',
  'lingnan': '岭南通钱包（PAY.TICL）',
  'tu': '交通联合',
  'cu': '城市一卡通',
  'tuCash': '交通联合电子现金',
  'macau': MacauPassCard.moduleName,
  'shenzhen': Shenzhentong.moduleName,
  'wuhan': '武汉通（AP1.WHCTC）',
  BeijingDf1001Scan.id: BeijingDf1001Scan.directoryName,
  MotBmacScan.id: MotBmacScan.name,
  'suzhou_suxin': '苏州通（SUXIN）',
  'suzhou_cika': '苏州计次',
  'tft': '天府通',
};

/// One serial pass over known read-only transport applications. Recognition of
/// an issuer or product never controls which application is selected next.
class LocalCardReader {
  LocalCardReader(
    this._transceive, {
    this.callback = const NoopLocalCardReaderCallback(),
    this.onStage,
  });
  final LocalTransceive _transceive;
  final LocalCardReaderCallback callback;
  final void Function(String)? onStage;

  Future<LocalReadOutcome?> read() async {
    final scanResult = await scan();
    if (scanResult.result == null && scanResult.terminalError != null) {
      throw scanResult.terminalError!;
    }
    return scanResult.result;
  }

  Future<IsoDepScan> scan() async {
    final applications = <String, ApplicationEvidence>{};
    TransportFailure? stopped;
    Object? firstTerminalError;
    void record(ApplicationEvidence ev) {
      applications[ev.appId] = ev;
      if (ev.transportFailure case final failure? when failure.stopsSession) {
        stopped ??= failure;
        firstTerminalError ??= ev.readError ?? failure;
      }
    }

    Future<List<int>> send(List<int> command) async {
      if (stopped case final failure?) throw failure;
      try {
        return await _transceive(command);
      } catch (e, stack) {
        final failure = TransportFailure.from(e, stack);
        if (failure.stopsSession) stopped = failure;
        throw failure;
      }
    }

    final exchange = ApduExchange(transceive: send);
    Future<void> local(
      String id,
      Future<bool> Function(CardInfo, List<ApduRecord>, CardExtras) select,
      Future<void> Function(CardInfo, List<ApduRecord>, CardExtras)
      readWallet, {
      bool identityOnly = false,
    }) async {
      if (stopped != null) return;
      final name = _walletNames[id]!;
      onStage?.call(name);
      final info = CardInfo();
      final records = <ApduRecord>[];
      final extras = CardExtras();
      bool confirmed = false;
      Object? error;
      TransportFailure? failure;
      try {
        confirmed = await select(info, records, extras);
        if (!confirmed) {
          record(
            ApplicationEvidence(
              appId: id,
              displayName: name,
              state: ApplicationProbeState.selectRejected,
              probed: true,
              records: List.unmodifiable(records),
            ),
          );
          return;
        }
        await readWallet(info, records, extras);
      } on Exception catch (e) {
        error = e;
        failure = e is ApduTransportException
            ? e.failure
            : e is TransportFailure
            ? e
            : null;
        confirmed = confirmed || info.isLocalCard;
        callback.onError(e.toString());
      }
      if (!confirmed) {
        record(
          ApplicationEvidence(
            appId: id,
            displayName: name,
            state: ApplicationProbeState.failed,
            probed: true,
            records: List.unmodifiable(records),
            readError: error,
            transportFailure: failure,
          ),
        );
        return;
      }
      if (identityOnly) {
        if (info.cardNumber.isEmpty) error ??= '应用卡号未读取';
      } else if (info.observedBalance == null) {
        error ??= '钱包余额未读取';
      }
      final result = ReadResult(
        info: info,
        records: List.unmodifiable(records),
        extras: extras,
        readError: error,
        transportFailure: failure,
      );
      record(
        ApplicationEvidence.succeeded(
          id,
          name,
          cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
          balanceFen: info.observedBalance,
          recordCount: id == 'macau'
              ? records.where((r) => r.label == '澳门通交易记录').length
              : result.trips.length,
          records: result.records,
          readError: error,
          transportFailure: failure,
          payload: result,
        ),
      );
    }

    // APPY must be first. Once another DF is selected some cards lock TICL.
    final lnt = LingnanTong(exchange);
    await local(
      'lingnan_appy',
      (_, rows, extras) => lnt.selectAppy(rows, extras),
      lnt.readAppy,
      identityOnly: true,
    );
    final appy = applications['lingnan_appy']?.payload;
    await local(
      'lingnan',
      (_, rows, extras) => lnt.selectTicl(rows, extras),
      (info, rows, extras) => lnt.readTicl(
        info,
        rows,
        extras,
        appyStats: appy is ReadResult
            ? appy.extras.slots['lnt.statsRaw'] as List<int>?
            : null,
        issueDate: appy is ReadResult ? appy.info.issueDate : null,
      ),
    );
    callback.onProgress(10);

    TuCuWalletScanResult? standard;
    if (stopped == null) {
      standard = await TuCuWalletScan(exchange, onStage: onStage).read();
      record(standard.tu.evidence);
      record(standard.cu.evidence);
      if (stopped == null) {
        onStage?.call('交通联合电子现金（消费日志）');
        final log = await TUnionCashLogReader(exchange).read();
        final name = _walletNames['tuCash']!;
        record(
          log.confirmed
              ? ApplicationEvidence.succeeded(
                  'tuCash',
                  name,
                  recordCount: log.records.length,
                  readError: log.issue,
                  transportFailure: log.transportFailure,
                  payload: log,
                )
              : log.transportFailure != null
              ? ApplicationEvidence.failed(
                  'tuCash',
                  name,
                  readError: log.issue,
                  transportFailure: log.transportFailure,
                )
              : ApplicationEvidence.rejected('tuCash', name),
        );
      }
    }
    callback.onProgress(55);
    final macau = MacauPassCard(exchange);
    await local(
      'macau',
      (info, rows, _) => macau.select(info, rows),
      (info, rows, _) => macau.readBalanceAndRecords(info, rows),
    );
    final szt = Shenzhentong(exchange);
    await local('shenzhen', (info, rows, extras) async {
      extras.slots['szt.probed'] = true;
      final ok = await szt.select(info, rows);
      extras.slots['szt.confirmed'] = ok;
      return ok;
    }, szt.read);

    final wuhan = WuhanTongCard(exchange);
    final trips = TripRecordReader(exchange);
    await local('wuhan', (info, rows, _) => wuhan.probe(info, rows), (
      info,
      rows,
      _,
    ) async {
      await wuhan.readLogs(info, rows);
      await trips.reconstructBalances(info, rows);
      TripDeduper().process(info, rows);
    });
    if (stopped == null) {
      onStage?.call(BeijingDf1001Scan.directoryName);
      final evidence = await BeijingDf1001Scan(exchange).read();
      if (evidence.readError != null) {
        callback.onError(evidence.readError.toString());
      }
      record(evidence);
    }
    if (stopped == null) {
      onStage?.call(MotBmacScan.name);
      record(await MotBmacScan(exchange).read());
    }
    callback.onProgress(80);
    if (stopped == null) {
      for (final ev in await readRegisteredLocalWallets(
        send,
        onStage: onStage,
      )) {
        record(ev);
      }
    }
    final evidence = List<ApplicationEvidence>.unmodifiable([
      for (final entry in _walletNames.entries)
        applications[entry.key] ??
            ApplicationEvidence(appId: entry.key, displayName: entry.value),
    ]);
    final result = _project(
      standard,
      evidence,
      firstTerminalError ?? stopped,
      stopped,
    );
    callback.onProgress(100);
    return (
      result: result,
      applications: evidence,
      terminalError: firstTerminalError ?? stopped,
    );
  }

  LocalReadOutcome? _project(
    TuCuWalletScanResult? standard,
    List<ApplicationEvidence> apps,
    Object? error,
    TransportFailure? failure,
  ) {
    final appy = apps.firstWhere((a) => a.appId == 'lingnan_appy');
    final ticl = apps.firstWhere((a) => a.appId == 'lingnan');
    final lnt = _lingnanSummary(appy, ticl);
    final locals = {
      'lingnan': ?lnt,
      for (final a in apps)
        if (a.confirmed &&
            a.payload is ReadResult &&
            a.appId != 'lingnan_appy' &&
            a.appId != 'lingnan' &&
            a.appId != 'tu' &&
            a.appId != 'cu')
          a.appId: a.payload! as ReadResult,
    };
    final tu = standard?.tu.card;
    final cu = standard?.cu.card;
    final primary = tu != null
        ? standard!.tu
        : cu != null
        ? standard!.cu
        : null;
    final data =
        primary?.readResult ??
        locals.values.firstOrNull ??
        (standard?.tu.evidence.confirmed == true
            ? standard!.tu.readResult
            : standard?.cu.evidence.confirmed == true
            ? standard!.cu.readResult
            : null);
    if (data == null) {
      final app = apps
          .where(
            (a) =>
                a.confirmed && (a.appId == 'tuCash' || a.appId == 'mot_bmac'),
          )
          .firstOrNull;
      if (app == null) return null;
      final cash = app.appId == 'tuCash';
      return LocalReadOutcome.transit(
        readResult: ReadResult(
          info: CardInfo(),
          records: app.records,
          extras: CardExtras(),
          readError: error ?? app.readError,
          transportFailure: failure ?? app.transportFailure,
        ),
        parsedCard: ParsedCard(
          parserId: cash ? CardParserIds.tunionCash : CardParserIds.motBmac,
          parserName: app.displayName,
          info: const TUnionCardInfo(),
          transactions: const [],
          selectedAidHex: cash
              ? 'A000000632010106'
              : '91560000144D4F542E424D4143303031',
        ),
        applications: apps,
      );
    }
    final ReadResult? szt = locals['shenzhen'];
    final ParsedCard card;
    if (tu != null) {
      // These ids preserve existing display and archive projections. Product
      // labelling runs after acquisition and cannot send an APDU.
      final serial = tu.info.displayCardNumber;
      final lingnanLabel =
          lnt != null &&
          LingnanTong.matchesTuIdentity(confirmed: true, cardNumber: serial);
      final shenzhenLabel =
          szt != null &&
          Shenzhentong.matchesTuIdentity(confirmed: true, cardNumber: serial);
      card = ParsedCard(
        parserId: lingnanLabel
            ? CardParserIds.lingnanTunion
            : shenzhenLabel
            ? CardParserIds.shenzhenTunion
            : CardParserIds.tunion,
        parserName: lingnanLabel
            ? '岭南通（交通联合版）'
            : shenzhenLabel
            ? Shenzhentong.tuModuleName
            : tu.parserName,
        info: tu.info,
        transactions: tu.transactions,
        transactionFileObserved: tu.transactionFileObserved,
        transitProcessRecords: tu.transitProcessRecords,
        selectedAidHex: tu.selectedAidHex,
        dualApplication: cu != null,
        cityUnionFiles: cu?.cityUnionFiles ?? const [],
        cityUnionBalanceFen: cu?.info.balanceFen,
        localCard: shenzhenLabel ? szt : lnt ?? szt,
      );
    } else if (cu != null) {
      card = cu;
    } else if (locals.isEmpty && standard != null) {
      final isTu = standard.tu.evidence.confirmed;
      card = ParsedCard(
        parserId: isTu ? CardParserIds.tunion : CardParserIds.cityUnion,
        parserName: (isTu ? standard.tu : standard.cu).evidence.displayName,
        info: TUnionCardInfo(),
        transactions: const [],
      );
    } else {
      final info = data.info;
      card = ParsedCard(
        parserId: info.isBmac
            ? CardParserIds.beijingBmac
            : info.isLNT
            ? CardParserIds.lingnanTong
            : CardParserIds.localCard,
        parserName: '地方交通卡 · ${info.cardKindLabel}',
        info: TUnionCardInfo(
          applicationSerial: info.cardNumber.isEmpty ? null : info.cardNumber,
          issuerId: info.issuerCode.isEmpty ? null : info.issuerCode,
          effectiveDate: info.issueDate,
          expireDate: info.expiryDate,
          balanceFen: info.observedBalance,
        ),
        transactions: const [],
        localCard: data,
      );
    }
    final combined = tu != null && cu != null;
    final summary =
        !combined && (error == null || identical(error, data.readError))
        ? data
        : ReadResult(
            info: combined
                ? (data.info.copy()
                    ..isTU = true
                    ..isCU = true)
                : data.info,
            records: combined
                ? List.unmodifiable([
                    ...data.records,
                    ...standard!.cu.readResult.records,
                  ])
                : data.records,
            extras: data.extras,
            readError:
                error ?? data.readError ?? standard?.cu.readResult.readError,
            transportFailure: failure ?? data.transportFailure,
          );
    return LocalReadOutcome.transit(
      readResult: summary,
      parsedCard: card,
      applications: apps,
    );
  }

  /// Legacy product summaries combine the APPY identity with the TICL purse.
  /// The original per-directory observations above remain independently usable.
  ReadResult? _lingnanSummary(
    ApplicationEvidence appy,
    ApplicationEvidence ticl,
  ) {
    final identity = appy.payload as ReadResult?;
    final wallet = ticl.payload as ReadResult?;
    if (identity == null && wallet == null) return null;
    final info = (identity ?? wallet)!.info.copy();
    if (wallet?.info.observedBalance case final value?) info.balance = value;
    info.currencyCode = wallet?.info.currencyCode;
    final extras = CardExtras();
    extras.slots.addAll({
      ...?identity?.extras.slots,
      ...?wallet?.extras.slots,
      'lnt.appyConfirmed': appy.confirmed,
      'lnt.ticlConfirmed': ticl.confirmed,
    });
    return ReadResult(
      info: info,
      records: List.unmodifiable([...appy.records, ...ticl.records]),
      extras: extras,
      readError:
          ticl.readError ??
          appy.readError ??
          (wallet == null ? '钱包余额未读取' : null),
      transportFailure: ticl.transportFailure ?? appy.transportFailure,
    );
  }
}
