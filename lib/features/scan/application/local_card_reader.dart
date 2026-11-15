library;

import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/city_union/city_union_reader.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_reader.dart';
import '../../../protocols/transit/local/apdu_exchange.dart';
import 'bank_card_probe.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../../protocols/transit/local/cards/beijing_local_card.dart';
import '../../../protocols/transit/local/cards/beijing_bmac.dart';
import '../../../protocols/transit/local/cards/common_card_info.dart';
import '../../../protocols/transit/local/cards/macau_pass_card.dart';
import '../../../protocols/transit/local/cards/shenzhentong.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_card.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../../protocols/transit/local/cards/suzhou_card.dart';
import '../../../protocols/transit/local/cards/suzhou_cika.dart';
import '../../../protocols/transit/local/cards/tft_local_card.dart';
import '../../../protocols/transit/local/cards/wuhan_tong_card.dart';
import '../../../protocols/transit/local/cards/lingnan_tong.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../../../protocols/transit/local/trips/trip_dedup.dart';
import '../../../protocols/transit/local/trips/trip_extras.dart';
import '../../../protocols/transit/local/trips/trip_records.dart';
import '../../../protocols/transport/transport_failure.dart';
import '../../../protocols/bank/emv/data/aid_registry.dart';
import '../../../protocols/bank/emv/protocol/emv_apdu.dart';

/// 进度 / 错误回调（轻量抽象，对应原重写工程的 CardReaderCallback）。
/// 会话 APDU 日志由上层 [LocalTransceive]（ScanController._exchange）统一记录，
/// 这里仅承载“读取阶段进度 / 失败原因”信号。
abstract class LocalCardReaderCallback {
  void onProgress(int percent);
  void onError(String message);
}

/// 空实现回调（上层不关心进度时的默认值）。
class NoopLocalCardReaderCallback implements LocalCardReaderCallback {
  const NoopLocalCardReaderCallback();
  @override
  void onProgress(int percent) {}
  @override
  void onError(String message) {}
}

/// 一次识读的统一结果：既可能是交通卡（新架构汇总 + 对应卡型 [ParsedCard]），
/// 也可能是银行卡（[BankCardResult]）。[parsedCard] 的 parserId 为
/// tunion / cityUnion / localCard，供上层展示与分析链路按其分派；
/// [bank] 非空时表示本次识读命中银行卡（EMV / PBOC）只读流程。
class LocalReadOutcome {
  const LocalReadOutcome.transit({
    required this.readResult,
    required this.parsedCard,
    this.shanghai,
    this.applications = const [],
  }) : bank = null;

  const LocalReadOutcome.bankCard(
    BankCardResult outcome, {
    this.applications = const [],
  })
    : readResult = null,
      parsedCard = null,
      bank = outcome,
      shanghai = null;

  final ReadResult? readResult;
  final ParsedCard? parsedCard;
  final BankCardResult? bank;

  /// 逐应用探测证据（一芯多应用组合按应用并列保留）。
  final List<ApplicationEvidence> applications;

  /// 上海交通卡（交通联合版）双路识读详情：仅命中该独立卡种时非空，
  /// 携带 TU / CU 两路各自的应用确认 / 读取成功 / 数据完整状态、原始
  /// 记录与解析错误。
  final ShanghaiTransitUnionResult? shanghai;

  /// 是否为银行卡识读产物（交通应用链路未命中时的一等阶段结果）。
  bool get isBankCard => bank != null;

  /// 以最终证据列表重建结果（读卡完成后由编排层统一回填）。
  LocalReadOutcome withApplications(List<ApplicationEvidence> applications) {
    final bank = this.bank;
    if (bank != null) {
      return LocalReadOutcome.bankCard(bank, applications: applications);
    }
    return LocalReadOutcome.transit(
      readResult: readResult!,
      parsedCard: parsedCard!,
      shanghai: shanghai,
      applications: applications,
    );
  }
}

/// 交通卡 / 银行卡统一识读编排主体（新模块为主）：按优先级串联各读法，
/// 命中即返回。
/// 0) 首次 APDU 只读选择 PAY.APPY（带 Le，状态拒绝可一次无 Le 兼容），
///    确认后先读完 LNT 信息/统计/TICL/余额/交易，再探 TU，绝不切回 LNT；
///    LNT 已确认时 TU 目标前缀合并双侧，否则保留地方结果，不再 CU/银行；
/// 1) 非 LNT 由 [ShanghaiTransitUnionCardParser] 读 TU，上海及哈尔滨城市通 TU 再探 CU；
/// 2) 普通确认 TU 也纳入默认目录探测：继续探测普通 CU 与澳门通钱包，
///    TU+PBOC / TU+CU / 澳门通+TU 组合按逐应用证据并列保留；
/// 3) TU 无可返回结果时独立回退普通 CU，不冒认上海 TU、不重复探测；
/// 4) 地方交通卡逐城市探测（武汉通 / 北京 / 羊城通 / 深圳通 /
///    苏州(苏薪·计次) / 天府通），命中后读取共用卡信息与行程 / 扩展记录，
///    最后余额重建 + 换乘去重；
/// 5) 银行卡（EMV / PBOC）只读探测 [BankCardProbe]：交通应用未命中时为
///    一等阶段兜底；TU / CU 已确认时经支付目录门控后在同一会话继续探测，
///    与交通应用并存于一芯多应用卡。
/// 全部阶段均不命中时返回 null。
/// 传输经 [LocalTransceive] 注入（与 NfcChannel.transceive 同签名），
/// 模块不依赖任何上层状态，可独立复用与测试。
class LocalCardReader {
  LocalCardReader(
    this._transceive, {
    this.callback = const NoopLocalCardReaderCallback(),
    this.onStage,
    this.bankProbe,
  });

  final LocalTransceive _transceive;
  final LocalCardReaderCallback callback;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  /// 银行卡（EMV / PBOC）探测抽象；为空时流程只做交通卡识读。
  final BankCardProbe? bankProbe;

  Future<LocalReadOutcome?> read() async {
    final probes = <ApplicationEvidence>[];
    final transit = await _readTransit(probes);
    // TU / CU 已确认时银行应用是同一芯片上的独立应用，一并只读探测；
    // 终止性传输失败后不得继续任何物理 I/O。
    final bankable =
        transit != null &&
        probes
            .where((p) => p.isTransitGeneralUnit)
            .any((p) => p.confirmed) &&
        probes.every((p) => p.transportFailure?.stopsSession != true);
    if (transit != null && bankable) {
      await _probeBank(probes, directoryLimited: true);
      return transit.withApplications(List.unmodifiable(probes));
    }
    if (transit == null) {
      // 交通应用链路未命中：作为统一识读流程的一等阶段执行银行卡只读探测。
      final bank = await _probeBank(probes, directoryLimited: false);
      if (bank != null) return bank;
      return null;
    }
    return transit.withApplications(List.unmodifiable(probes));
  }

  /// 银行卡（EMV / PBOC）只读探测；[directoryLimited] 为 true 时只允许
  /// 目录披露的银行应用被继续枚举，避免对已确认交通卡无条件尝试全部
  /// 内置候选 AID。
  Future<LocalReadOutcome?> _probeBank(
    List<ApplicationEvidence> probes, {
    required bool directoryLimited,
  }) async {
    final probe = bankProbe;
    if (probe == null) return null;
    try {
      if (directoryLimited && !await _bankDirectoryPresent()) {
        probes.add(
          ApplicationEvidence.rejected(
            'bank',
            '银行卡（EMV / PBOC）',
            reason: 'PPSE / PSE 支付目录未披露银行应用',
          ),
        );
        return null;
      }
      onStage?.call('银行卡（EMV / PBOC）');
      callback.onProgress(30);
      final outcome = await probe.probe(_transceive);
      if (outcome == null) {
        probes.add(
          ApplicationEvidence.rejected(
            'bank',
            '银行卡（EMV / PBOC）',
            reason: '应用目录与内置候选均未匹配到银行应用',
          ),
        );
        return null;
      }
      callback.onProgress(95);
      probes.add(
        ApplicationEvidence.succeeded(
          'bank',
          '银行卡（EMV / PBOC）',
          recordCount: outcome.applications.length,
          readError: outcome.transportFailure,
          transportFailure: outcome.transportFailure,
          payload: outcome,
          notes: [
            'status=${outcome.status.name}',
            if (outcome.discoveredApplications.isNotEmpty)
              'discovered=${outcome.discoveredApplications.length}',
          ],
        ),
      );
      return LocalReadOutcome.bankCard(
        outcome,
        applications: List.unmodifiable(probes),
      );
    } catch (e) {
      callback.onError(_mapError(e));
      probes.add(
        ApplicationEvidence.failed(
          'bank',
          '银行卡（EMV / PBOC）',
          readError: e,
          transportFailure: _transportFailureOf(e),
        ),
      );
      return null;
    }
  }

  /// 轻量目录探测：2PAY / 1PAY 任一成功即认为存在银行应用候选。
  Future<bool> _bankDirectoryPresent() async {
    final exchange = ApduExchange(transceive: _transceive);
    for (final name in [kEmvPpseName, kEmvPseName]) {
      final response = await exchange.call(
        EmvApdu.selectByName(name.codeUnits),
        '银行卡支付目录探测',
      );
      if (response != null) return true;
    }
    return false;
  }

  Future<LocalReadOutcome?> _readTransit(
    List<ApplicationEvidence> probes,
  ) async {
    final info = CardInfo();
    final records = <ApduRecord>[];
    final extras = CardExtras();
    final apdu = ApduExchange(transceive: _transceive);
    final extrasReader = CardExtrasReader(apdu);
    final tripReader = TripRecordReader(apdu);

    try {
      callback.onProgress(5);

      // 0) APPY 必须是首次 APDU；先完整读取 LNT，再探 TU，绝不切回。
      final lntInfo = CardInfo();
      final lntRecords = <ApduRecord>[];
      final lntExtras = CardExtras();
      Object? lntError;
      var appyConfirmed = false;
      onStage?.call(LingnanTong.moduleName);
      final lnt = LingnanTong(apdu);
      try {
        appyConfirmed = await lnt.selectAppy(lntRecords, lntExtras);
        if (appyConfirmed) {
          lntInfo.isLNT = lntInfo.isYCT = true;
          await lnt.read(lntInfo, lntRecords, lntExtras);
        }
      } on Exception catch (e) {
        lntError = e;
        callback.onError(_mapError(e));
      }
      final local = ReadResult(
        info: lntInfo,
        records: lntRecords,
        extras: lntExtras,
        readError: lntError,
        transportFailure: _transportFailureOf(lntError),
      );
      if (appyConfirmed) {
        probes.add(
          ApplicationEvidence.succeeded(
            'lingnan',
            LingnanTong.moduleName,
            cardNumber: lntInfo.cardNumber.isEmpty
                ? null
                : lntInfo.cardNumber,
            balanceFen: lntInfo.observedBalance,
            recordCount: lntRecords
                .where((r) => r.type == 2)
                .length,
            records: lntRecords,
            readError: lntError,
            transportFailure: _transportFailureOf(lntError),
            payload: lntInfo.rawInfo == null
                ? null
                : List<int>.of(lntInfo.rawInfo!),
          ),
        );
      } else {
        probes.add(
          ApplicationEvidence.rejected(
            'lingnan',
            LingnanTong.moduleName,
            reason: lntError?.toString() ?? 'PAY.APPY 未确认',
          ),
        );
      }
      if (local.transportFailure?.stopsSession == true) {
        if (appyConfirmed) return _localOutcome(local);
        throw lntError!;
      }

      // 1) LNT 已确认时只探 TU，不混入城市 CU 或其他地方/银行读法。
      callback.onProgress(10);
      final shanghai = await ShanghaiTransitUnionCardParser(
        _transceive,
        onStage: onStage,
        onProgress: (p) => callback.onProgress(10 + (p * 40).round()),
      ).read(probeCu: !appyConfirmed);
      final tuCard = shanghai.tu.card;
      final cuCard = shanghai.cu.card;
      final tuProbe = _applicationEvidence(
        shanghai.tu,
        'tu',
        CommonUnitTu.moduleName,
      );
      if (tuProbe != null) probes.add(tuProbe);
      final cuProbe = _applicationEvidence(
        shanghai.cu,
        'cu',
        CommonUnitCu.moduleName,
      );
      if (cuProbe != null) probes.add(cuProbe);

      if (!appyConfirmed &&
          (shanghai.isShanghaiTransitUnion || shanghai.isHarbinTransitUnion) &&
          shanghai.mergedCard != null) {
        callback.onProgress(95);
        return LocalReadOutcome.transit(
          readResult: shanghai.readResult,
          parsedCard: shanghai.mergedCard,
          shanghai: shanghai,
        );
      }

      if (appyConfirmed &&
          LingnanTong.matchesTuIdentity(
            confirmed: shanghai.tu.confirmed,
            cardNumber:
                shanghai.tu.identity?.displayCardNumber ??
                tuCard?.info.displayCardNumber,
          )) {
        final tuInfo = tuCard?.info ?? shanghai.tu.identity;
        if (tuInfo != null) {
          callback.onProgress(95);
          return _outcome(
            shanghai.tu.cardInfo,
            shanghai.tu.records,
            extras,
            ParsedCard(
              parserId: CardParserIds.lingnanTunion,
              parserName: '岭南通（交通联合版）',
              info: tuInfo,
              transactions: tuCard?.transactions ?? const [],
              transactionFileObserved: tuCard?.transactionFileObserved ?? false,
              transitProcessRecords: tuCard?.transitProcessRecords ?? const [],
              selectedAidHex: tuCard?.selectedAidHex ?? '',
              localCard: local,
            ),
            readError: shanghai.tu.readError ?? lntError,
          );
        }
      }

      if (appyConfirmed) {
        // TU 不匹配/不可用时保留地方钱包；TU 部分产物也留作诊断。
        lntExtras.slots['lnt.tuConfirmed'] = shanghai.tu.confirmed;
        lntExtras.slots['lnt.tuCard'] = tuCard == null
            ? null
            : {
                'applicationSerial': tuCard.info.applicationSerial,
                'balanceFen': tuCard.info.balanceFen,
                'selectedAidHex': tuCard.selectedAidHex,
              };
        lntExtras.slots['lnt.tuRecords'] = [
          for (final record in shanghai.tu.records)
            {
              'commandHex': record.commandHex,
              'response': record.response,
              'rawBody': record.rawBody,
            },
        ];
        return _localOutcome(
          ReadResult(
            info: lntInfo,
            records: lntRecords,
            extras: lntExtras,
            readError: shanghai.tu.readError ?? lntError,
            transportFailure:
                shanghai.tu.transportFailure ?? local.transportFailure,
          ),
        );
      }

      if (Shenzhentong.matchesTuIdentity(
        confirmed: shanghai.tu.confirmed,
        cardNumber:
            shanghai.tu.identity?.displayCardNumber ??
            tuCard?.info.displayCardNumber,
      )) {
        final tuInfo = tuCard?.info ?? shanghai.tu.identity!;
        final sztInfo = CardInfo();
        final sztRecords = <ApduRecord>[];
        final sztExtras = CardExtras();
        Object? sztError;
        final tuFailure = shanghai.tu.transportFailure;
        final shouldProbe = tuFailure?.stopsSession != true;
        sztExtras.slots['szt.probed'] = shouldProbe;
        sztExtras.slots['szt.confirmed'] = false;
        if (shouldProbe) {
          onStage?.call(Shenzhentong.moduleName);
          final szt = Shenzhentong(apdu);
          try {
            if (await szt.select(sztInfo, sztRecords)) {
              sztExtras.slots['szt.confirmed'] = true;
              await szt.read(sztInfo, sztRecords, sztExtras);
            }
          } on Exception catch (e) {
            sztError = e;
            callback.onError(_mapError(e));
          }
        }
        probes.add(
          sztExtras.slots['szt.confirmed'] == true
              ? ApplicationEvidence.succeeded(
                  'shenzhen',
                  Shenzhentong.moduleName,
                  cardNumber: sztInfo.cardNumber.isEmpty
                      ? null
                      : sztInfo.cardNumber,
                  balanceFen: sztInfo.observedBalance,
                  recordCount: sztRecords
                      .where((r) => r.type == 2)
                      .length,
                  records: sztRecords,
                  readError: sztError,
                  transportFailure: _transportFailureOf(sztError),
                  payload: sztInfo.rawInfo == null
                      ? null
                      : List<int>.of(sztInfo.rawInfo!),
                )
              : ApplicationEvidence.rejected(
                  'shenzhen',
                  Shenzhentong.moduleName,
                  reason: sztError?.toString() ?? 'PAY.SZT 未确认',
                ),
        );
        final sztResult = ReadResult(
          info: sztInfo,
          records: sztRecords,
          extras: sztExtras,
          readError: sztError,
          transportFailure: _transportFailureOf(sztError),
        );
        callback.onProgress(95);
        return _outcome(
          shanghai.tu.cardInfo,
          shanghai.tu.records,
          extras,
          ParsedCard(
            parserId: CardParserIds.shenzhenTunion,
            parserName: Shenzhentong.tuModuleName,
            info: tuInfo,
            transactions: tuCard?.transactions ?? const [],
            transactionFileObserved: tuCard?.transactionFileObserved ?? false,
            transitProcessRecords: tuCard?.transitProcessRecords ?? const [],
            selectedAidHex: tuCard?.selectedAidHex ?? 'A000000632010105',
            localCard: sztResult,
          ),
          readError: shanghai.tu.readError ?? sztError,
        );
      }

      // 2) 普通 TU 确认后仍按默认目录继续探测 CU（普通城市 TU+CU 组合）；
      //    再独立探测澳门通钱包，最后以 TU 为主卡返回。
      if (tuCard != null) {
        final tuFailure = shanghai.tu.transportFailure;
        if (tuFailure != null && tuFailure.stopsSession) {
          // TU 已保留部分数据时不再尝试后续应用探测。
          callback.onProgress(95);
          return _outcome(
            shanghai.tu.cardInfo,
            shanghai.tu.records,
            extras,
            tuCard,
            readError: shanghai.tu.readError,
          );
        }

        ParsedCard? mergedCuCard;
        Object? cuReadError;
        if (!shanghai.cu.probed) {
          onStage?.call(CommonUnitCu.moduleName);
          final cuInfo = CardInfo();
          final cuRecords = <ApduRecord>[];
          final cu = CommonUnitCu(apdu);
          try {
            if (await cu.selectPrimary(cuInfo)) {
              mergedCuCard = await cu.read(
                cuInfo,
                cuRecords,
                readBalance: true,
              );
            }
          } on Exception catch (e) {
            mergedCuCard = cu.parsedCard;
            cuReadError = e;
            callback.onError(_mapError(e));
            if (_transportFailureOf(e)?.stopsSession == true &&
                (mergedCuCard == null ||
                    mergedCuCard.cityUnionFiles.isEmpty)) {
              rethrow;
            }
          }
          if (mergedCuCard != null && mergedCuCard.cityUnionFiles.isNotEmpty) {
            probes.add(
              ApplicationEvidence.succeeded(
                'cu',
                CommonUnitCu.moduleName,
                balanceFen: mergedCuCard.info.balanceFen,
                recordCount: cuRecords
                    .where((r) => r.type == 2)
                    .length,
                records: cuRecords,
                readError: cuReadError,
                transportFailure: _transportFailureOf(cuReadError),
                payload: mergedCuCard,
              ),
            );
            final dual = ParsedCard(
              parserId: CardParserIds.tunion,
              parserName: tuCard.parserName,
              info: tuCard.info,
              transactions: tuCard.transactions,
              transactionFileObserved: tuCard.transactionFileObserved,
              transitProcessRecords: tuCard.transitProcessRecords,
              cityUnionFiles: mergedCuCard.cityUnionFiles,
              cityUnionBalanceFen: mergedCuCard.info.balanceFen,
              dualApplication: true,
              selectedAidHex: tuCard.selectedAidHex,
            );
            final dualInfo = shanghai.tu.cardInfo.copy()
              ..isTU = true
              ..isCU = true;
            callback.onProgress(95);
            return _outcome(
              dualInfo,
              [...shanghai.tu.records, ...cuRecords],
              extras,
              dual,
              readError: shanghai.tu.readError ?? cuReadError,
            );
          }
          probes.add(
            ApplicationEvidence.rejected(
              'cu',
              CommonUnitCu.moduleName,
              reason: cuReadError?.toString() ?? 'CU 应用未确认',
            ),
          );
        }

        // 澳门通钱包作为独立应用探测；确认后保留其身份、余额与流水证据，
        // 主卡仍为 TU，不冒充 CU 双应用。
        Object? macauError;
        var macauConfirmed = false;
        final macauInfo = CardInfo();
        final macauRecords = <ApduRecord>[];
        try {
          onStage?.call(MacauPassCard.moduleName);
          final macau = MacauPassCard(apdu);
          macauConfirmed = await macau.select(macauInfo, macauRecords);
          if (macauConfirmed) {
            await macau.readBalanceAndRecords(macauInfo, macauRecords);
          }
        } on Exception catch (e) {
          macauError = e;
          callback.onError(_mapError(e));
          if (!macauConfirmed &&
              _transportFailureOf(e)?.stopsSession == true) {
            rethrow;
          }
        }
        probes.add(
          macauConfirmed
              ? ApplicationEvidence.succeeded(
                  'macau',
                  MacauPassCard.moduleName,
                  cardNumber: macauInfo.cardNumber.isEmpty
                      ? null
                      : macauInfo.cardNumber,
                  balanceFen: macauInfo.observedBalance,
                  recordCount: macauRecords
                      .where((r) => r.label == '澳门通交易记录')
                      .length,
                  records: macauRecords,
                  readError: macauError,
                  transportFailure: _transportFailureOf(macauError),
                  payload: macauInfo.rawInfo == null
                      ? null
                      : List<int>.of(macauInfo.rawInfo!),
                )
              : ApplicationEvidence.rejected(
                  'macau',
                  MacauPassCard.moduleName,
                  reason: macauError?.toString() ?? '澳门通钱包应用未确认',
                ),
        );
        callback.onProgress(95);
        return _outcome(
          shanghai.tu.cardInfo,
          shanghai.tu.records,
          extras,
          tuCard,
          readError: shanghai.tu.readError,
        );
      }

      // 已发生终止性传输错误时，无卡结果也不能被当成应用不匹配。
      final tuFailure = shanghai.tu.transportFailure;
      if (tuFailure != null && tuFailure.stopsSession) {
        throw shanghai.tu.readError ?? tuFailure;
      }

      // TU 无可返回结果时独立尝试普通 CU；上海分支已探测过则不重读。
      if (!shanghai.cu.probed) {
        onStage?.call(CommonUnitCu.moduleName);
        final cu = CommonUnitCu(apdu);
        ParsedCard? card;
        Object? readError;
        try {
          if (await cu.select(info, records)) {
            card = await cu.read(info, records, readBalance: true);
          }
        } on Exception catch (e) {
          card = cu.parsedCard;
          readError = e;
          callback.onError(_mapError(e));
          probes.add(
            ApplicationEvidence.failed(
              'cu',
              CommonUnitCu.moduleName,
              readError: e,
              transportFailure: _transportFailureOf(e),
            ),
          );
          if (_transportFailureOf(e)?.stopsSession == true &&
              (card == null || card.cityUnionFiles.isEmpty)) {
            rethrow;
          }
        }
        if (card != null && card.cityUnionFiles.isNotEmpty) {
          probes.add(
            ApplicationEvidence.succeeded(
              'cu',
              CommonUnitCu.moduleName,
              cardNumber:
                  info.cardNumber.isEmpty ? null : info.cardNumber,
              balanceFen: info.observedBalance,
              recordCount: records
                  .where((r) => r.type == 2)
                  .length,
              records: List.of(records),
              readError: readError,
              transportFailure: _transportFailureOf(readError),
              payload: card,
            ),
          );
          callback.onProgress(95);
          return _outcome(info, records, extras, card, readError: readError);
        }
        if (readError == null) {
          probes.add(
            ApplicationEvidence.rejected(
              'cu',
              CommonUnitCu.moduleName,
              reason: 'CU 标准文件为空',
            ),
          );
        }
      } else if (cuCard != null) {
        callback.onProgress(95);
        return _outcome(
          shanghai.cu.cardInfo,
          shanghai.cu.records,
          extras,
          cuCard,
          readError: shanghai.cu.readError,
        );
      }

      // 3~7) 地方交通卡探测（通用单元均未命中时）
      callback.onProgress(25);

      // 澳门通以专属钱包应用名认领，不套用国内地方卡的金额及余额重建规则。
      final macauPass = MacauPassCard(apdu);
      if (await macauPass.select(info, records)) {
        callback.onProgress(35);
        await macauPass.readBalanceAndRecords(info, records);
        probes.add(
          ApplicationEvidence.succeeded(
            'macau',
            MacauPassCard.moduleName,
            cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
            balanceFen: info.observedBalance,
            recordCount: records
                .where((r) => r.label == '澳门通交易记录')
                .length,
            records: List.of(records),
            payload: info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
          ),
        );
        callback.onProgress(95);
        return _localOutcome(
          ReadResult(info: info, records: records, extras: extras),
        );
      }
      probes.add(
        ApplicationEvidence.rejected(
          'macau',
          MacauPassCard.moduleName,
          reason: '澳门通钱包应用未确认',
        ),
      );

      // 3) 老版武汉通（AP1.WHCTC）：先于 PBOC 探测完成应用确认；
      //    一旦确认，即使后续流水读取失败也按地方卡返回，不再回退银行卡。
      final whctc = WuhanTongCard(apdu);
      if (await whctc.probe(info, records)) {
        info.isWHCTC = true;
        callback.onProgress(35);
        await whctc.readLogs(info, records);
        probes.add(
          ApplicationEvidence.succeeded(
            'wuhan',
            '武汉通（AP1.WHCTC）',
            cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
            balanceFen: info.observedBalance,
            recordCount: records
                .where((r) => r.type == 2)
                .length,
            payload: info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
          ),
        );
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }
      probes.add(
        ApplicationEvidence.rejected('wuhan', '武汉通（AP1.WHCTC）'),
      );

      onStage?.call(BeijingBmac.moduleName);
      final bmac = BeijingBmac(apdu);
      if (await bmac.select(info, records, extras)) {
        callback.onProgress(35);
        await bmac.read(info, records, extras);
        probes.add(
          ApplicationEvidence.succeeded(
            'beijing_bmac',
            BeijingBmac.moduleName,
            cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
            balanceFen: info.observedBalance,
            recordCount: records
                .where((r) => r.type == 2)
                .length,
            payload: info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
          ),
        );
        callback.onProgress(95);
        return _localOutcome(
          ReadResult(info: info, records: records, extras: extras),
        );
      }
      probes.add(
        ApplicationEvidence.rejected(
          'beijing_bmac',
          BeijingBmac.moduleName,
          reason: 'BMAC 应用未确认',
        ),
      );

      // 4) 北京地方卡探测
      if (await BeijingLocalCard(apdu).probe(info, records)) {
        info.isBeijing = true;
        callback.onProgress(35);
        await extrasReader.readCommon(info, records, extras); // m790f
        callback.onProgress(55);
        await tripReader.readFile(
          info,
          records,
          extras,
          TripFile.metro,
        ); // m789e 196
        probes.add(
          ApplicationEvidence.succeeded(
            'beijing',
            '北京互通卡（地方卡）',
            cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
            balanceFen: info.observedBalance,
            recordCount: records
                .where((r) => r.type == 2)
                .length,
            payload: info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
          ),
        );
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }
      probes.add(
        ApplicationEvidence.rejected('beijing', '北京互通卡（地方卡）'),
      );

      final szt = Shenzhentong(apdu);
      onStage?.call(Shenzhentong.moduleName);
      if (await szt.select(info, records)) {
        callback.onProgress(35);
        await szt.read(info, records, extras);
        probes.add(
          ApplicationEvidence.succeeded(
            'shenzhen',
            Shenzhentong.moduleName,
            cardNumber: info.cardNumber.isEmpty ? null : info.cardNumber,
            balanceFen: info.observedBalance,
            recordCount: records
                .where((r) => r.type == 2)
                .length,
            records: List.of(records),
            payload: info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
          ),
        );
        callback.onProgress(95);
        return _localOutcome(
          ReadResult(info: info, records: records, extras: extras),
        );
      }
      probes.add(
        ApplicationEvidence.rejected(
          'shenzhen',
          Shenzhentong.moduleName,
          reason: 'PAY.SZT 未确认',
        ),
      );

      // 6) SUXIN / SUZ CIKA / TFT
      var suzhouConfirmed = false;
      var tftConfirmed = false;
      if (await SuzhouCard(apdu).select(info, records)) {
        suzhouConfirmed = true;
        // isSuzhou / isSuxin 已置位
      } else if (await SuzhouCika(apdu).select(info, records)) {
        suzhouConfirmed = true;
        // isSuzhou / isCika 已置位
      } else {
        tftConfirmed = await TftLocalCard(apdu).select(info, records);
        // isTFT 已置位
      }
      if (suzhouConfirmed) {
        probes.add(
          ApplicationEvidence.confirmed('suzhou', '苏州（苏薪 / 计次）'),
        );
      } else if (tftConfirmed) {
        probes.add(
          ApplicationEvidence.confirmed('tft', TftLocalCard.moduleName),
        );
      }

      // 7) 共用读取 m791g（条件：YCT/SUXIN/CIKA）
      if (info.isYCT || info.isSuxin || info.isCika) {
        callback.onProgress(35);
        if (await CommonCardInfo(apdu).read(info, records)) {
          callback.onProgress(50);
          await _readNonTuTrips(
            extrasReader,
            tripReader,
            info,
            records,
            extras,
          );
          callback.onProgress(80);
          final outcome = await _finishLocal(tripReader, info, records, extras);
          if (probes.isNotEmpty &&
              probes.last.appId == (suzhouConfirmed ? 'suzhou' : 'tft')) {
            probes[probes.length - 1] = ApplicationEvidence.succeeded(
              probes.last.appId,
              probes.last.displayName,
              cardNumber:
                  info.cardNumber.isEmpty ? null : info.cardNumber,
              balanceFen: info.observedBalance,
              recordCount: records
                  .where((r) => r.type == 2)
                  .length,
              payload:
                  info.rawInfo == null ? null : List<int>.of(info.rawInfo!),
            );
          }
          return outcome;
        }
      }

      return null; // 非地方卡且通用单元未命中
    } on Exception catch (e) {
      callback.onError(_mapError(e));
      if (info.isLocalCard) {
        // A confirmed application's late failure is not a protocol non-match.
        // Do not call _finish: its balance reconstruction can perform I/O.
        return _localOutcome(
          ReadResult(
            info: info,
            records: List.unmodifiable(records),
            extras: extras,
            readError: e,
            transportFailure: switch (e) {
              ApduTransportException(:final failure) => failure,
              TransportFailure() => e,
              _ => null,
            },
          ),
        );
      }
      if (_transportFailureOf(e)?.stopsSession == true) rethrow;
      return null;
    }
  }

  /// 非 TU 分支的行程/扩展读取（对应 L8705-8755）。
  Future<void> _readNonTuTrips(
    CardExtrasReader ex,
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    await ex.readCommon(info, records, extras); // m790f
    await reader.readFile(info, records, extras, TripFile.metro); // m789e 196

    if (info.isCika) {
      await reader.readFile(
        info,
        records,
        extras,
        TripFile.suxinTx,
      ); // m789e 132
    }
    if (info.isCika) {
      await reader.readFile(info, records, extras, TripFile.bus); // m789e 76
    }
  }

  /// 地方卡收尾：余额重建 + 换乘去重后，仅在命中地方卡种时封装产出；
  /// 通用 TU/CU 不走此路径（由富识读分支直接返回）。
  Future<LocalReadOutcome?> _finishLocal(
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    final result = await _finish(
      reader,
      info,
      records,
      extras,
    ); // m785a + m786b
    if (!info.isLocalCard) return null;
    callback.onProgress(90);
    final outcome = _localOutcome(result);
    callback.onProgress(95);
    return outcome;
  }

  /// Pure construction shared by complete reads and interrupted local reads.
  LocalReadOutcome _localOutcome(ReadResult result) {
    final info = result.info;
    final parsed = ParsedCard(
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
      localCard: result,
    );
    return LocalReadOutcome.transit(readResult: result, parsedCard: parsed);
  }

  /// 通用单元（TU/CU）命中后封装：保留新架构 ReadResult 汇总。
  LocalReadOutcome _outcome(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
    ParsedCard parsed, {
    Object? readError,
  }) => LocalReadOutcome.transit(
    readResult: ReadResult(
      info: info,
      records: records,
      extras: extras,
      readError: readError,
      transportFailure: _transportFailureOf(readError),
    ),
    parsedCard: parsed,
  );

  static TransportFailure? _transportFailureOf(Object? error) =>
      switch (error) {
        ApduTransportException(:final failure) => failure,
        TransportFailure() => error,
        _ => null,
      };

  /// 上海 / 哈尔滨双应用侧结果 → 逐应用证据；未探测时不产出条目。
  static ApplicationEvidence? _applicationEvidence(
    ShanghaiTransitApplication app,
    String appId,
    String displayName,
  ) {
    if (!app.probed) return null;
    final card = app.card;
    final identity = app.identity;
    final cardNumber =
        card?.info.displayCardNumber ??
        identity?.displayCardNumber ??
        (app.cardInfo.cardNumber.isEmpty ? null : app.cardInfo.cardNumber);
    if (!app.confirmed) {
      return ApplicationEvidence.rejected(
        appId,
        displayName,
        reason: app.errors.isEmpty
            ? '应用未确认'
            : app.errors.first,
      );
    }
    if (app.readError != null && (card == null || !app.readSucceeded)) {
      return ApplicationEvidence.failed(
        appId,
        displayName,
        readError: app.readError,
        transportFailure: app.transportFailure,
      );
    }
    return ApplicationEvidence.succeeded(
      appId,
      displayName,
      cardNumber: cardNumber,
      balanceFen: card?.info.balanceFen,
      recordCount: app.records.where((r) => r.type == 2).length,
      records: app.records,
      readError: app.readError,
      transportFailure: app.transportFailure,
      payload: card,
    );
  }

  /// 收尾（对应 L8911-8923）：余额重建 + 换乘去重 + 进度 100。
  Future<ReadResult> _finish(
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    await reader.reconstructBalances(info, records); // m785a
    TripDeduper().process(info, records); // m786b
    return ReadResult(info: info, records: records, extras: extras);
  }

  static String _mapError(Object e) {
    final m = e.toString();
    if (m.contains('info')) return 'CardInfoFailed';
    if (m.contains('balance')) return 'BalanceFailed';
    return 'ReadingIncomplete';
  }
}
