import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/tunion/tunion_trip_matcher.dart';
import '../reference_data/data/tunion_knowledge_base.dart';
import '../reference_data/domain/station_codes.dart';
import '../reference_data/domain/tunion_terminal_decoder.dart';
import '../reference_data/data/tunion_bus_location.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import 'tunion_analysis_models.dart';
import 'tunion_card_identifier.dart';
import 'balance_interpretation.dart';
import 'balance_reconstruction.dart';
import 'tunion_record_context.dart';

/// 分析引擎：识别 → 行程聚合 → 符合性检查 → 异常检测。
class AnalysisEngine {
  final KnowledgeBase knowledge;
  final CardIdentifier identifier;
  final TerminalDecoder terminalDecoder;

  AnalysisEngine(this.knowledge)
    : identifier = CardIdentifier(knowledge),
      terminalDecoder = TerminalDecoder(knowledge.terminalRules);

  CardAnalysisResult analyze(ParsedCard card, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final identity = identifier.identify(card.info);
    final currency = _resolveCurrency(card.info);
    final trips = _buildTrips(card, identity, currency);
    return CardAnalysisResult(
      identity: identity,
      wallet: WalletSummary.of(card.info, at, currency: currency),
      currency: currency,
      trips: trips,
      compliance: _checkCompliance(card, at, currency),
      anomalies: _detectAnomalies(card, identity, at),
      generatedAt: at,
    );
  }

  /// 钱包货币判定：卡号（应用序列号）IIN 前缀命中卡前缀库且条目声明
  /// currency 时按其取值，未命中再按发卡机构标识反查；均未收录时回退
  /// 人民币。八达通全国通的 HKD 前缀元数据描述账户，不能把 TU 文件的
  /// 人民币观察直接改标为港币；真实账户余额由独立读取证据解释。
  Currency _resolveCurrency(TUnionCardInfo info) {
    if (BalanceInterpretation.fromCardInfo(
      info,
      parserId: CardParserIds.tunion,
    ).isOctopusTunion) {
      return Currency.cny;
    }
    return Currency.fromCode(
      (knowledge.cardPrefixes.lookup(info.displayCardNumber) ??
              knowledge.cardPrefixes.lookupByIssuerId(info.issuerId))
          ?.currency,
    );
  }

  List<TransitTrip> _buildTrips(
    ParsedCard card,
    CardIdentity identity,
    Currency currency,
  ) {
    // 展示按原始记录顺序关联：秒级时间相等 OR 有效基础 POS 被包含。
    // 1E 与 1A 各自占用基础交易；余额仍走独立的严格证据匹配。
    final cycles = [
      for (final r in card.transitProcessRecords)
        if (r.sfi == 0x1E && r.trip != null) r.trip!,
    ];
    final sides = tunionApplicationSides(card.transitProcessRecords);
    final cycleLinks = matchTunionDisplayEvents(
      card.transactions,
      cycles,
      basicTime: (t) => t.time,
      basicPos: (t) => t.terminalId,
      eventTime: (p) => p.time,
      eventPos: (p) => p.terminalId,
    );
    final sideLinks = matchTunionDisplayEvents(
      card.transactions,
      sides,
      basicTime: (t) => t.time,
      basicPos: (t) => t.terminalId,
      eventTime: (p) => p.time,
      eventPos: (p) => p.terminal,
    );
    final rideAnnotations = _buildRideAnnotations(
      card,
      identity,
      cycles,
      cycleLinks,
    );
    // 0x1A 按进入/离开两侧补充，未匹配侧保持独立展示。
    final entryFallbacks = _buildEntryFallbacks(
      card,
      identity,
      sides,
      sideLinks,
    );
    // 交易后余额：0x1E 记录余额优先，缺失处按账本顺序从当前钱包余额倒推；
    // 无法证明连续（类型未知 / 顺序不明 / 无读取锚点）时保持未知。
    final balanceMatches = _buildBalanceMatches(card);
    final interpretation = BalanceInterpretation.fromParsedCard(card);
    final balances = reconstructTransactionBalances(
      card.transactions,
      openingBalanceFen: interpretation.semantics == BalanceSemantics.direct
          ? interpretation.accountBalanceMinor
          : null,
      recordedBalanceFen: (txn) => balanceMatches[txn]?.balanceFen,
    );
    final trips = card.transactions.indexed.map((indexed) {
      final (index, txn) = indexed;
      final balance = balances[index];
      // 终端解码切出的线路/站点编码 → 站点代码表（读卡识途数据）查名称；
      // 终端查表未命中时尝试 0x1E 注解；仍未收录则回退原始编码（不猜测）。
      final annotation = rideAnnotations[index];
      // 两来源独立关联，1E 优先，1A 补缺。
      final fallback = entryFallbacks[index];
      // 已配对过程记录给出受理城市，不能用发卡城市的终端规则覆盖它。
      final recordCity = _validCityCode(
        annotation?.cityCode ?? fallback?.cityCode,
      );
      final knownCity = recordCity ?? identity.cityCode ?? card.info.cityCode;
      final location = terminalDecoder.decode(
        txn.terminalId,
        cityCode: knownCity,
        issuerId: card.info.issuerId,
      );
      // 仅按前缀命中的规则也可能切出另一座城市；冲突时不混入其线路/站点。
      final terminalCity = _validCityCode(location?.cityCode);
      final loc =
          recordCity != null &&
              terminalCity != null &&
              recordCity != terminalCity
          ? null
          : location;
      final cityCode = recordCity ?? _validCityCode(loc?.cityCode);
      final cityName = cityCode == null
          ? null
          : knowledge.cities.lookup(cityCode)?.name;
      // 公交走独立的完整编码查询与城市规则，不套用轨道片段匹配。
      final isBus = annotation != null
          ? isTunionBusCycle(annotation.record)
          : (fallback?.isBus ?? false);
      final busLocation = isBus
          ? (annotation != null
                ? resolveTunionBusLocation(
                    stations: knowledge.stationCodes,
                    cityCode:
                        annotation.cityCode ??
                        identity.cityCode ??
                        card.info.cityCode,
                    field: annotation.record.lineStationCode,
                    context: busContextForCycle(annotation.record),
                  )
                : fallback?.busLocation)
          : null;
      final processMatch = isBus
          ? busLocation?.match
          : annotation?.match == null || annotation!.match.isUnmatched
          ? fallback?.stationMatch ?? annotation?.match
          : annotation.match;
      // 原 m761o：0x1E / 0x1A 均未命中时，按 0x18 基础终端查本地映射。
      final localTerminalMatch =
          !isBus && (processMatch == null || processMatch.isUnmatched)
          ? _lookupBasicTerminal(txn.terminalId, knownCity, txn.time)
          : null;
      final stationMatch =
          localTerminalMatch != null && !localTerminalMatch.isUnmatched
          ? localTerminalMatch
          : processMatch;
      final terminalEntry = isBus
          ? null
          : _lookupStationEntry(loc, identity, card);
      final stationEntry = terminalEntry ?? stationMatch?.entry;
      // 匹配置信级别：终端解码查表精确命中优先；其次取 0x1E / 本地终端
      // 查表结论；存在站点原始编码但查不到表时直接标记未匹配（不猜测）。
      final confidence = isBus
          ? (busLocation?.match.isUnmatched == false
                ? busLocation!.match.confidence
                : null)
          : (terminalEntry != null
                ? StationMatchConfidence.exact
                : (stationMatch?.confidence ??
                      (loc?.stationCode != null
                          ? StationMatchConfidence.unmatched
                          : null)));
      // 歧义候选整体压制名称（线路 / 站点均回退原始编码，不强行显示）。
      final suppressed = confidence == StationMatchConfidence.ambiguous;
      final lineLabel = isBus
          ? busLocation?.lineLabel ??
                annotation?.record.lineCode ??
                fallback?.lineCode ??
                loc?.lineCode
          : (stationMatch?.lineName ??
                (suppressed
                    ? null
                    : stationEntry?.line ??
                          _lookupTerminalLineName(loc, identity, card)) ??
                fallback?.lineCode ??
                loc?.lineCode);
      final resolvedStation = confidence == StationMatchConfidence.exact
          ? stationEntry?.station
          : null;
      // 复合消费（0x09）配对命中时以行程状态短名（出站 / 进站 / 上车 /
      // 下车…）替代类型名展示；未配对保持 null（展示层不替换，不猜测）。
      final rideStatusName = txn.isCompositeConsume
          ? annotation?.record.statusShortName ?? fallback?.statusName
          : null;
      return TransitTrip(
        time: txn.time,
        amountFen: txn.amountFen,
        overdraftLimitFen: txn.overdraftLimitFen,
        isConsume: txn.isConsume,
        typeName: txn.typeName,
        isCompositeConsume: txn.isCompositeConsume,
        sequence: txn.sequence,
        terminalId: txn.terminalId,
        location: loc,
        cityName:
            cityName ??
            (recordCity == null
                ? annotation?.cityName ?? fallback?.cityName
                : null),
        cityCode: cityCode,
        lineLabel: lineLabel,
        stationLabel:
            busLocation?.stationLabel ??
            resolvedStation ??
            loc?.stationCode ??
            fallback?.stationLabel ??
            (isBus ? annotation?.record.stationCode : null),
        stationType: stationEntry?.type,
        appTypeName:
            annotation?.record.appTypeLabel ??
            (fallback == null
                ? null
                : fallback.isBus
                ? '公共汽电车'
                : '城市轨道交通'),
        balanceAfterFen: balance?.fen,
        balanceAfterIsRecorded: balance?.isRecorded,
        rideStatusName: rideStatusName,
        isEntry:
            annotation?.record.isEntry ??
            (sideLinks[index] == null
                ? false
                : sides[sideLinks[index]!].isEntry),
        displayProcessKey: cycleLinks[index] == null
            ? null
            : cycleDisplayKey(cycles[cycleLinks[index]!]),
        displayApplicationKey: sideLinks[index] == null
            ? null
            : sides[sideLinks[index]!].key,
        // 快照由 matchedProcess 的余额恢复来源，不能保存仅分钟级的注解
        // 为余额证据，否则钱包倒推结果可能在恢复时被误标为记录余额。
        matchedProcessTrip: balanceMatches[txn],
        stationConfidence: confidence,
        rawHex: txn.rawHex,
        currency: currency,
      );
    }).toList()..sort((a, b) => b.time.compareTo(a.time));
    return trips;
  }

  /// 原 m761o 基础终端映射：仅 0x1E / 0x1A 未命中时调用；未知城市不猜测。
  StationMatch? _lookupBasicTerminal(
    String terminalId,
    String? cityCode,
    DateTime time,
  ) {
    final service = knowledge.tuLookup;
    if (service == null || cityCode == null || cityCode.isEmpty) return null;
    return service.resolveBasic(
      city: cityCode,
      terminal: terminalId,
      time: time,
    );
  }

  /// 站点代码表查询：城市取终端解码城市，缺省依次回退识别城市与卡片城市；
  /// 候选编码按"最具体优先"尝试（线路+站点拼接 → 站点 → 线路）。
  StationCodeEntry? _lookupStationEntry(
    TerminalLocation? loc,
    CardIdentity identity,
    ParsedCard card,
  ) {
    if (loc == null) return null;
    final cityCode = loc.cityCode ?? identity.cityCode ?? card.info.cityCode;
    if (cityCode == null || cityCode.isEmpty) return null;
    return knowledge.stationCodes.lookupLineStation(
      lineCode: loc.lineCode,
      stationCode: loc.stationCode,
      cityCode: cityCode,
    );
  }

  String? _lookupTerminalLineName(
    TerminalLocation? loc,
    CardIdentity identity,
    ParsedCard card,
  ) {
    final line = loc?.lineCode;
    final city = loc?.cityCode ?? identity.cityCode ?? card.info.cityCode;
    if (line == null || city == null) return null;
    final match = knowledge.stationCodes.matchTuLineByCardValue(
      rawLineCode: line,
      cityCode: city,
    );
    if (match.confidence == StationMatchConfidence.ambiguous) return null;
    return match.lineName ??
        knowledge.stationCodes.lookupLineName(
          rawLineCode: line,
          cityCode: city,
        );
  }

  /// 消费共享顺序关联结果，补齐站点与分类，不改变基础时间、金额或余额。
  Map<int, _RideAnnotation> _buildRideAnnotations(
    ParsedCard card,
    CardIdentity identity,
    List<TUnionTripRecord> cycles,
    Map<int, int> links,
  ) {
    final byKey = <int, _RideAnnotation>{};
    for (final link in links.entries) {
      final trip = cycles[link.value];
      // 原 m793j 的受理城市修正只作用于派生城市（查询 / 展示）；记录原始
      // 城市仍保留在 matchedProcessTrip，作为来源证据。
      final recordCity = normalizeTunionAcquirerCity(
        trip.cityCode,
        rawCity36: cycleCityPair(trip, 36),
      );
      final cityCode = recordCity ?? identity.cityCode ?? card.info.cityCode;
      // 公交在聚合时用独立查询；轨道先走原始完整键 / 城市专用布局 /
      // 终端别名，全部未命中时才保留既有片段匹配兜底。
      final match = !trip.isCityRail || isTunionBusCycle(trip)
          ? StationMatch.unmatched
          : _matchRailCycle(trip, cityCode);
      {
        byKey[link.key] = _RideAnnotation(
          record: trip,
          match: match,
          cityCode: recordCity,
          cityName: cityCode == null || cityCode.isEmpty
              ? null
              : knowledge.cities.lookup(cityCode)?.name,
        );
      }
    }
    return byKey;
  }

  /// 余额证据与宽松的站点注解分开：类型方向已知、金额及秒级时间一致，
  /// 且两侧唯一才接受。两文件没有可证明时间偏差的关联流水号，不能仅凭
  /// 同分钟（或终端片段）把不同秒的记录升级为余额锚点。
  Map<TUnionTransaction, TUnionTripRecord> _buildBalanceMatches(
    ParsedCard card,
  ) {
    final candidates = <TUnionTransaction, List<TUnionTripRecord>>{};
    final uses = <TUnionTripRecord, int>{};
    for (final txn in card.transactions) {
      final matches = <TUnionTripRecord>[];
      for (final record in card.transitProcessRecords) {
        final trip = record.trip;
        if (record.sfi != 0x1E || trip == null) continue;
        final compatible = txn.isRecharge
            ? trip.isRecharge
            : txn.isConsume &&
                  (trip.isConsume || (trip.isEntry && trip.amountFen == 0));
        if (!compatible ||
            txn.amountFen != trip.amountFen ||
            !txn.time.isAtSameMomentAs(trip.time)) {
          continue;
        }
        matches.add(trip);
        uses.update(trip, (count) => count + 1, ifAbsent: () => 1);
      }
      candidates[txn] = matches;
    }
    return {
      for (final entry in candidates.entries)
        if (entry.value.length == 1 && uses[entry.value.single] == 1)
          entry.key: entry.value.single,
    };
  }

  StationMatch _matchRailCycle(TUnionTripRecord trip, String? cityCode) {
    if (trip.appTypeCode != 0x01) return StationMatch.unmatched;
    final service = knowledge.tuLookup;
    if (service != null && cityCode != null) {
      final source = service.resolveCycle(
        city: cityCode,
        field: trip.lineStationCode,
        terminalId: trip.terminalId,
        time: trip.time,
        appType: trip.appTypeCode,
      );
      if (!source.isUnmatched) return source;
    }
    return knowledge.stationCodes.matchLineStationField(
      field: trip.lineStationCode,
      cityCode: cityCode,
    );
  }

  /// 0x1A 进出站/上下车逐侧增强；金额不是展示关联条件，1E 优先、1A 补缺。
  Map<int, _EntryFallback> _buildEntryFallbacks(
    ParsedCard card,
    CardIdentity identity,
    List<TunionApplicationSide> sides,
    Map<int, int> links,
  ) {
    final byKey = <int, _EntryFallback>{};
    for (final link in links.entries) {
      final side = sides[link.value];
      final entry = side.isEntry;
      final rail = side.rail;
      final bus = side.bus;
      String? entryCityCode;
      String? entryStationId;
      DateTime? entryTime;
      final String statusName;
      if (rail != null) {
        entryCityCode = entry ? rail.entryCityCode : rail.exitCityCode;
        entryStationId = entry ? rail.entryStationId : rail.exitStationId;
        entryTime = side.time;
        statusName = entry ? '进站' : '出站';
      } else if (bus != null) {
        entryCityCode = entry ? bus.entryCityCode : bus.exitCityCode;
        entryStationId = entry ? bus.entryStationCode : bus.exitStationCode;
        entryTime = side.time;
        statusName = entry ? '上车' : '下车';
      } else {
        continue;
      }
      if (entryTime == null) continue;
      final cityCode = entryCityCode ?? identity.cityCode ?? card.info.cityCode;
      final railMatch = rail == null || entryStationId == null
          ? null
          : knowledge.stationCodes.matchTuStationByCardId(
              rawStationId: entryStationId,
              cityCode: cityCode,
              lineValue: entry ? rail.entryLineCode : rail.exitLineCode,
            );
      {
        byKey[link.key] = _EntryFallback(
          cityName: cityCode == null || cityCode.isEmpty
              ? null
              : knowledge.cities.lookup(cityCode)?.name,
          cityCode: entryCityCode,
          stationLabel: entryStationId,
          lineCode: entry
              ? bus?.entryLineCode ?? rail?.entryLineCode?.toString()
              : bus?.exitLineCode ?? rail?.exitLineCode?.toString(),
          stationMatch: railMatch,
          busLocation: bus == null
              ? null
              : resolveTunionBusLocation(
                  stations: knowledge.stationCodes,
                  cityCode: cityCode,
                  field: busRecordLocationField(
                    entry ? bus.entryLineCode : bus.exitLineCode,
                    entry ? bus.entryStationCode : bus.exitStationCode,
                    entry ? bus.entryOperatorCode : bus.exitOperatorCode,
                  ),
                  context: TunionBusDecodeContext(transactionTime: entryTime),
                ),
          statusName: statusName,
          isBus: bus != null,
        );
      }
    }
    return byKey;
  }

  /// 交易城市代码有效性：空或全 0（未写入）视为未知（返回 null），
  /// 供异地用卡判定（未知不判定，不猜测）。
  static String? _validCityCode(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(trimmed) || trimmed == '0000') {
      return null;
    }
    return trimmed;
  }

  ComplianceReport _checkCompliance(
    ParsedCard card,
    DateTime now,
    Currency currency,
  ) {
    final info = card.info;
    final items = <ComplianceItem>[
      ComplianceItem(
        id: 'app-selected',
        title: '应用选择',
        status: ComplianceStatus.pass,
        detail: card.selectedAidHex.isEmpty
            ? '已选中应用（AID 未知）'
            : '已选中应用 ${card.selectedAidHex}',
      ),
      ComplianceItem(
        id: 'file-public',
        title: '公共应用信息文件 (SFI 0x15)',
        status: info.issuerId == null
            ? ComplianceStatus.warn
            : ComplianceStatus.pass,
        detail: info.issuerId == null
            ? '未读到发卡机构标识等字段'
            : '发卡机构标识 ${info.issuerId}',
      ),
      ComplianceItem(
        id: 'file-management',
        title: '管理信息文件 (SFI 0x17)',
        status: info.cityCode == null
            ? ComplianceStatus.warn
            : ComplianceStatus.pass,
        detail: info.cityCode == null ? '未读到城市代码' : '城市代码 ${info.cityCode}',
      ),
      ComplianceItem(
        id: 'file-holder',
        title: '持卡人基本信息文件 (SFI 0x16)',
        status: info.cardTypeId == null
            ? ComplianceStatus.info
            : ComplianceStatus.pass,
        detail: info.cardTypeId == null
            ? '未读到（部分卡种无此文件）'
            : '卡类型标识 ${info.cardTypeId}',
      ),
      ComplianceItem(
        id: 'balance',
        title: '余额读取 (GET BALANCE)',
        status: info.balanceFen == null
            ? ComplianceStatus.warn
            : ComplianceStatus.pass,
        detail: info.balanceFen == null
            ? '未读到余额'
            : '余额 ${(info.balanceFen! / 100).toStringAsFixed(2)} ${currency.unit}',
      ),
      ComplianceItem(
        id: 'transactions',
        title: '交易明细文件 (SFI 0x18)',
        status: card.transactions.isEmpty
            ? ComplianceStatus.info
            : ComplianceStatus.pass,
        detail: card.transactions.isEmpty
            ? '无交易记录或未读到'
            : '共 ${card.transactions.length} 条记录',
      ),
    ];

    final eff = info.effectiveDate;
    final exp = info.expireDate;
    if (eff == null || exp == null) {
      items.add(
        const ComplianceItem(
          id: 'date-consistency',
          title: '日期一致性',
          status: ComplianceStatus.warn,
          detail: '生效/失效日期字段不全',
        ),
      );
    } else if (eff.isAfter(exp)) {
      items.add(
        ComplianceItem(
          id: 'date-consistency',
          title: '日期一致性',
          status: ComplianceStatus.fail,
          detail: '生效日期 ${_fmtDate(eff)} 晚于失效日期 ${_fmtDate(exp)}',
        ),
      );
    } else {
      items.add(
        ComplianceItem(
          id: 'date-consistency',
          title: '日期一致性',
          status: ComplianceStatus.pass,
          detail: '${_fmtDate(eff)} ~ ${_fmtDate(exp)}',
        ),
      );
    }

    if (exp == null) {
      items.add(
        const ComplianceItem(
          id: 'not-expired',
          title: '卡片有效性',
          status: ComplianceStatus.info,
          detail: '无失效日期，无法判断',
        ),
      );
    } else if (exp.isBefore(now)) {
      items.add(
        ComplianceItem(
          id: 'not-expired',
          title: '卡片有效性',
          status: ComplianceStatus.fail,
          detail: '已过期（失效日期 ${_fmtDate(exp)}）',
        ),
      );
    } else {
      items.add(
        const ComplianceItem(
          id: 'not-expired',
          title: '卡片有效性',
          status: ComplianceStatus.pass,
          detail: '有效期内',
        ),
      );
    }

    final future = card.transactions.where((t) => t.time.isAfter(now)).length;
    if (card.transactions.isEmpty) {
      items.add(
        const ComplianceItem(
          id: 'txn-time',
          title: '交易时间合理性',
          status: ComplianceStatus.info,
          detail: '无交易记录',
        ),
      );
    } else if (future > 0) {
      items.add(
        ComplianceItem(
          id: 'txn-time',
          title: '交易时间合理性',
          status: ComplianceStatus.warn,
          detail: '$future 条交易时间晚于当前时间',
        ),
      );
    } else {
      items.add(
        const ComplianceItem(
          id: 'txn-time',
          title: '交易时间合理性',
          status: ComplianceStatus.pass,
          detail: '交易时间均正常',
        ),
      );
    }

    final scored = items
        .where((i) => i.status != ComplianceStatus.info)
        .toList();
    final score = scored.isEmpty
        ? 100
        : (scored.fold<double>(0, (acc, i) => acc + i.weight) /
                  scored.length *
                  100)
              .round();
    return ComplianceReport(items: items, scorePercent: score);
  }

  List<Anomaly> _detectAnomalies(
    ParsedCard card,
    CardIdentity identity,
    DateTime now,
  ) {
    final info = card.info;
    final out = <Anomaly>[];

    if (info.expireDate != null && info.expireDate!.isBefore(now)) {
      out.add(
        Anomaly(
          code: 'card-expired',
          severity: AnomalySeverity.critical,
          message: '卡片已过期（失效日期 ${_fmtDate(info.expireDate!)}）',
        ),
      );
    }
    if (info.effectiveDate != null && info.effectiveDate!.isAfter(now)) {
      out.add(
        const Anomaly(
          code: 'effective-in-future',
          severity: AnomalySeverity.warn,
          message: '生效日期晚于当前日期，数据可疑',
        ),
      );
    }
    if (identity.cityCode != null &&
        info.cityCode != null &&
        identity.cityCode != info.cityCode) {
      out.add(
        Anomaly(
          code: 'identity-conflict',
          severity: AnomalySeverity.warn,
          message:
              '识别证据冲突：指纹库城市(${identity.cityCode}) '
              '与卡片城市代码(${info.cityCode}) 不一致',
        ),
      );
    }
    if (info.balanceFen != null && info.balanceFen! < 0) {
      out.add(
        const Anomaly(
          code: 'negative-balance',
          severity: AnomalySeverity.warn,
          message: '余额为负值，数据可疑',
        ),
      );
    }
    final negative = card.transactions.where((t) => t.amountFen < 0).length;
    if (negative > 0) {
      out.add(
        Anomaly(
          code: 'negative-amount',
          severity: AnomalySeverity.warn,
          message: '发现 $negative 条金额为负的交易记录',
        ),
      );
    }
    final zeroConsume = card.transactions
        .where((t) => t.isConsume && t.amountFen == 0)
        .length;
    if (zeroConsume > 0) {
      out.add(
        Anomaly(
          code: 'zero-consume',
          severity: AnomalySeverity.info,
          message: '存在 $zeroConsume 条金额为 0 的消费记录',
        ),
      );
    }
    final seen = <int>{};
    final duplicated = <int>{};
    for (final t in card.transactions) {
      if (!seen.add(t.sequence)) duplicated.add(t.sequence);
    }
    if (duplicated.isNotEmpty) {
      out.add(
        Anomaly(
          code: 'duplicate-sequence',
          severity: AnomalySeverity.info,
          message: '交易序号重复: ${duplicated.join(', ')}',
        ),
      );
    }
    final eff = info.effectiveDate;
    if (eff != null) {
      final before = card.transactions
          .where((t) => t.time.isBefore(eff))
          .length;
      if (before > 0) {
        out.add(
          Anomaly(
            code: 'txn-before-effective',
            severity: AnomalySeverity.info,
            message: '$before 条交易记录早于卡片生效日期',
          ),
        );
      }
    }
    final future = card.transactions.where((t) => t.time.isAfter(now)).length;
    if (future > 0) {
      out.add(
        Anomaly(
          code: 'txn-in-future',
          severity: AnomalySeverity.warn,
          message: '发现 $future 条交易时间晚于当前时间',
        ),
      );
    }
    return out;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 0x1E 行程注解（内部用）：配对的 0x1E 记录、站点代码表匹配置信结果
/// （未命中时为 [StationMatch.unmatched]）、修正后的受理城市（记录未写
/// 城市时为 null，原始值仍在 [record]）与城市名。
class _RideAnnotation {
  final TUnionTripRecord record;
  final StationMatch match;
  final String? cityCode;
  final String? cityName;

  const _RideAnnotation({
    required this.record,
    required this.match,
    this.cityCode,
    this.cityName,
  });
}

/// 0x1A 进站兜底注解（内部用）：进站城市名（编码查得时）、城市代码
/// （记录原始值，供异地用卡判定；未写入时为 null）、站点原始编码
/// （记录中的站点 ID，线路库接入前保持原始值；未写入时为 null）与
/// 行程状态短名（"进站" / "上车"，复合消费标题展示用）；[isBus]
/// 标识注解来源是否为记录 2（公共汽电车），供展示层屏蔽线路 / 站点匹配。
class _EntryFallback {
  final String? cityName;
  final String? cityCode;
  final String? stationLabel;
  final String statusName;
  final bool isBus;
  final String? lineCode;
  final TunionBusLocation? busLocation;
  final StationMatch? stationMatch;

  const _EntryFallback({
    this.cityName,
    this.cityCode,
    this.stationLabel,
    required this.statusName,
    this.isBus = false,
    this.lineCode,
    this.busLocation,
    this.stationMatch,
  });
}
