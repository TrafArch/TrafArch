import '../card/card_parser.dart';
import '../data/tunion_knowledge_base.dart';
import '../data/station_codes.dart';
import '../data/tunion_terminal_decoder.dart';
import '../data/tunion_bus_location.dart';
import '../transit/tunion/tunion_models.dart';
import 'tunion_analysis_models.dart';
import 'tunion_card_identifier.dart';

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
  /// 人民币（缺省口径，不猜测外币）。八达通-全国通卡不单独适配货币，
  /// 金额统一按人民币展示。
  Currency _resolveCurrency(TUnionCardInfo info) => Currency.fromCode(
    (knowledge.cardPrefixes.lookup(info.displayCardNumber) ??
            knowledge.cardPrefixes.lookupByIssuerId(info.issuerId))
        ?.currency,
  );

  List<TransitTrip> _buildTrips(
    ParsedCard card,
    CardIdentity identity,
    Currency currency,
  ) {
    // 0x1E 过程记录增强：按"交易时间（分钟）+ 金额"与交易记录配对。
    // 部分城市（如福州地铁）线路/站点信息不写终端号，只写 0x1E 文件，
    // 终端规则未命中时用注解补齐；配对命中时一并补充 0x1E 独有的
    // 应用分类与交易后余额（配对不唯一时不注解，保持未知）。
    final rideAnnotations = _buildRideAnnotations(card, identity);
    // 0x1A 记录进站兜底：记录 1（城市轨道）/ 记录 2（公共汽电车）的
    // 进站信息与 0 元交易按时间配对，在 0x1E 注解未命中时标记进站。
    final entryFallbacks = _buildEntryFallbacks(card, identity);
    final trips = card.transactions.map((txn) {
      final location = terminalDecoder.decode(
        txn.terminalId,
        cityCode: identity.cityCode ?? card.info.cityCode,
        issuerId: card.info.issuerId,
      );
      final loc = location;
      String? cityName;
      if (loc != null && loc.cityCode != null) {
        cityName = knowledge.cities.lookup(loc.cityCode!)?.name;
      }

      // 终端解码切出的线路/站点编码 → 站点代码表（读卡识途数据）查名称；
      // 终端查表未命中时尝试 0x1E 注解；仍未收录则回退原始编码（不猜测）。
      final key = _pairKey(txn.time, txn.amountFen);
      final annotation = rideAnnotations[key];
      // 0x1E 注解优先；无 0x1E 注解时用 0x1A 记录进站兜底（兜底配对键
      // 金额恒为 0，仅可能命中进站刷卡的 0 元交易）。
      final fallback = annotation == null ? entryFallbacks[key] : null;
      // 公交走独立的完整编码查询与城市规则，不套用轨道片段匹配。
      final isBus =
          (annotation?.record.isBus ?? false) || (fallback?.isBus ?? false);
      final busLocation = isBus
          ? (annotation != null
                ? resolveTunionBusLocation(
                    stations: knowledge.stationCodes,
                    cityCode:
                        annotation.record.cityCode ??
                        identity.cityCode ??
                        card.info.cityCode,
                    field: annotation.record.lineStationCode,
                  )
                : fallback?.busLocation)
          : null;
      final stationMatch = isBus ? busLocation?.match : annotation?.match;
      final terminalEntry = isBus
          ? null
          : _lookupStationEntry(loc, identity, card);
      final stationEntry = terminalEntry ?? stationMatch?.entry;
      // 匹配置信级别：终端解码查表精确命中优先；其次取 0x1E 查表结论；
      // 存在站点原始编码但查不到表时直接标记未匹配（已取消站名推测）。
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
        cityName: cityName ?? annotation?.cityName ?? fallback?.cityName,
        cityCode: _validCityCode(
          loc?.cityCode ?? annotation?.record.cityCode ?? fallback?.cityCode,
        ),
        lineLabel: lineLabel,
        stationLabel:
            busLocation?.stationLabel ??
            resolvedStation ??
            loc?.stationCode ??
            fallback?.stationLabel ??
            (isBus ? annotation?.record.stationCode : null),
        stationType: stationEntry?.type,
        appTypeName: annotation?.record.appTypeLabel,
        balanceAfterFen: annotation?.record.balanceFen,
        rideStatusName: rideStatusName,
        isEntry: annotation?.record.isEntry ?? (fallback != null),
        matchedProcessTrip: annotation?.record,
        stationConfidence: confidence,
        rawHex: txn.rawHex,
        currency: currency,
      );
    }).toList()..sort((a, b) => b.time.compareTo(a.time));
    return trips;
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

  /// 构建 0x1E 行程注解：可选补齐线路/站点名称（站点代码表命中时）与
  /// 0x1E 独有的应用分类、交易后余额（未命中站点代码表时仍保留后两者）；
  /// 按"交易时间（分钟）+ 金额"与交易配对，同键多条视为不可判定不注解。
  /// 入站类记录（EC 0x01 / EP 0x03）不承载扣费金额（金额字段为 0），仅与
  /// 进站刷卡写入的 0 元交易配对，命中时行程标记为进站；金额字段非 0 的
  /// 入站记录视为异常数据，不参与配对（不猜测）。
  Map<String, _RideAnnotation> _buildRideAnnotations(
    ParsedCard card,
    CardIdentity identity,
  ) {
    final byKey = <String, _RideAnnotation>{};
    final ambiguous = <String>{};
    final transactionCounts = <String, int>{};
    for (final txn in card.transactions) {
      final key = _pairKey(txn.time, txn.amountFen);
      transactionCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final record in card.transitProcessRecords) {
      if (record.sfi != 0x1E) continue;
      final trip = record.trip;
      if (trip == null) continue;
      // 入站类记录金额字段为 0 时才有配对意义（与 0 元交易同键）；
      // 非 0 视为异常数据，不参与配对（不猜测）。
      if (trip.isEntry && trip.amountFen != 0) continue;
      final cityCode = trip.cityCode ?? identity.cityCode ?? card.info.cityCode;
      // 公交在聚合时用独立查询，轨道仍使用原有片段匹配。
      final match = trip.isBus
          ? StationMatch.unmatched
          : knowledge.stationCodes.matchLineStationField(
              field: trip.lineStationCode,
              cityCode: cityCode,
            );
      final key = _pairKey(trip.time, trip.amountFen);
      if (byKey.containsKey(key)) {
        ambiguous.add(key);
      } else {
        byKey[key] = _RideAnnotation(
          record: trip,
          match: match,
          cityName: cityCode == null || cityCode.isEmpty
              ? null
              : knowledge.cities.lookup(cityCode)?.name,
        );
      }
    }
    byKey.removeWhere(
      (key, _) => ambiguous.contains(key) || transactionCounts[key] != 1,
    );
    return byKey;
  }

  /// 构建 0x1A 记录进站兜底注解：记录 1（城市轨道应用信息记录）与记录 2
  /// （公共汽电车应用信息记录）解码成功时，其进站信息（进闸时间 / 上车
  /// 时间）按"进站时间（分钟）+ 金额 0"与进站刷卡的 0 元交易配对；命中时
  /// 行程标记为进站并补齐进站城市名与站点原始编码（站点名称待线路库接入
  /// 后补全）。记录 1 进站交易金额字段非 0 视为异常数据、进站时间缺失
  /// （未写入 / 截断）时不参与配对；同键多条视为不可判定不注解。
  /// 0x1E 过程记录对同一交易存在注解时以 0x1E 为准（调用方优先消费）。
  Map<String, _EntryFallback> _buildEntryFallbacks(
    ParsedCard card,
    CardIdentity identity,
  ) {
    final byKey = <String, _EntryFallback>{};
    final ambiguous = <String>{};
    for (final record in card.transitProcessRecords) {
      if (record.sfi != 0x1A) continue;
      final rail = record.railTransit;
      final bus = record.busTransit;
      String? entryCityCode;
      String? entryStationId;
      DateTime? entryTime;
      final String statusName;
      if (rail != null) {
        // 进站交易金额非 0 与 0 元进站交易的实测特征不符，视为异常不配对。
        if (rail.entryAmountFen != null && rail.entryAmountFen != 0) continue;
        entryCityCode = rail.entryCityCode;
        entryStationId = rail.entryStationId;
        entryTime = rail.entryTime;
        statusName = '进站';
      } else if (bus != null) {
        entryCityCode = bus.entryCityCode;
        entryStationId = bus.entryStationCode;
        entryTime = bus.entryTime;
        statusName = '上车';
      } else {
        continue;
      }
      if (entryTime == null) continue;
      final cityCode = entryCityCode ?? identity.cityCode ?? card.info.cityCode;
      final key = _pairKey(entryTime, 0);
      if (byKey.containsKey(key)) {
        ambiguous.add(key);
      } else {
        byKey[key] = _EntryFallback(
          cityName: cityCode == null || cityCode.isEmpty
              ? null
              : knowledge.cities.lookup(cityCode)?.name,
          cityCode: entryCityCode,
          stationLabel: entryStationId,
          lineCode: bus?.entryLineCode,
          busLocation: bus == null
              ? null
              : resolveTunionBusLocation(
                  stations: knowledge.stationCodes,
                  cityCode: cityCode,
                  field: busRecordLocationField(
                    bus.entryLineCode,
                    bus.entryStationCode,
                    bus.entryOperatorCode,
                  ),
                ),
          statusName: statusName,
          isBus: bus != null,
        );
      }
    }
    byKey.removeWhere((key, _) => ambiguous.contains(key));
    return byKey;
  }

  /// 交易/0x1E 记录的配对键：交易时间（分钟精度）+ 金额（分）。
  static String _pairKey(DateTime time, int amountFen) =>
      '${time.year}-${time.month}-${time.day} '
      '${time.hour}:${time.minute}|$amountFen';

  /// 交易城市代码有效性：空或全 0（未写入）视为未知（返回 null），
  /// 供异地用卡判定（未知不判定，不猜测）。
  static String? _validCityCode(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    if (trimmed.isEmpty || trimmed.replaceAll('0', '').isEmpty) return null;
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
/// （未命中时为 [StationMatch.unmatched]）与城市名。
class _RideAnnotation {
  final TUnionTripRecord record;
  final StationMatch match;
  final String? cityName;

  const _RideAnnotation({
    required this.record,
    required this.match,
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

  const _EntryFallback({
    this.cityName,
    this.cityCode,
    this.stationLabel,
    required this.statusName,
    this.isBus = false,
    this.lineCode,
    this.busLocation,
  });
}
