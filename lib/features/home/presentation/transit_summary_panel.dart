import 'package:flutter/material.dart';

import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../transit_analysis/balance_interpretation.dart';
import '../../../app/app_dependencies.dart';

import 'summary_widgets.dart';
import 'summary_formatters.dart';
import 'felica_summary_panel.dart';
import 'result_labels.dart';

class TransitSummaryPanel extends StatelessWidget {
  const TransitSummaryPanel({super.key, required this.app});
  final AppDependencies app;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _cardPanel(context, app),
  );
  List<Widget> _cardPanel(BuildContext context, AppDependencies app) {
    final result = app.lastResult;
    final parsed = app.parsedCard;
    final felica = app.felicaResult;
    // FeliCa（NFC-F）结果：与 TU / CU 卡片视图并列，使用同一版式。
    if (felica != null && parsed == null) {
      return [FelicaSummaryPanel(felica: felica)];
    }
    final identified = app.lastIdentified;
    final isTUnion = CardParserIds.isTUnionFamily(parsed?.parserId);
    final isCityUnion = parsed?.parserId == CardParserIds.cityUnion;
    final isShanghai = parsed?.parserId == CardParserIds.shanghaiTunion;
    final isLocal = parsed?.parserId == CardParserIds.localCard;
    final local = parsed?.localCard;
    final info = parsed?.info;
    final publicInfo = app.cityUnionPublicInfo;
    // 首页显示本次读卡的协议结果。行程分析摘要和历史档案不参与余额
    // 取值；TU / CU 各自的钱包也不能相加或互相覆盖。
    final balanceFen = info?.balanceFen;
    final balanceText = balanceFen == null
        ? null
        : '${app.cardCurrency.symbol}${(balanceFen / 100).toStringAsFixed(2)}';
    final interpretation = parsed == null
        ? null
        : BalanceInterpretation.fromParsedCard(parsed);
    final separateObservation =
        isTUnion && interpretation?.semantics != BalanceSemantics.direct;
    final cardKind = isTUnion ? info?.cardKind : null;
    final expireDate = isTUnion ? info?.expireDate : null;

    // 卡片名称：正式卡名优先（识别引擎），未识别时回退卡型通用名称。
    final typeLabel = transitTypeLabel(parsed?.parserId);
    final name = transitDisplayName(
      parserId: parsed?.parserId,
      identifiedName: identified?.displayName,
      localName: local?.info.cardKindLabel,
    );
    // 发卡地：识别城市优先，回退城市码表（与识别引擎链路一致）。
    final cityName =
        identified?.identity.cityName ??
        (isCityUnion
            ? app.cuCityNameOf(app.cardCityCode)
            : app.cityNameOf(app.cardCityCode));
    // 卡号（完整，不脱敏）：识别结果优先，回退解析字段，最后回退 UID。
    final String? parsedCardNumber;
    if (isLocal) {
      final number = local?.info.cardNumber ?? '';
      parsedCardNumber = number.isEmpty ? null : number;
    } else if (isCityUnion) {
      parsedCardNumber = publicInfo?.cityCardNumber;
    } else {
      parsedCardNumber =
          info?.displayCardNumber ?? publicInfo?.cityCardNumber;
    }
    final cardNumber = identified?.cardNumber ?? parsedCardNumber ?? '未读取到卡号';

    return [
      ...summaryNameLine(context, name),
      if (parsed != null)
        summaryField(context, '类型', isLocal ? '地方交通卡' : typeLabel)
      else if (result?.cardType != null)
        summaryField(context, '卡型', result!.cardType!),
      if (cityName != null && cityName.isNotEmpty)
        summaryField(context, '发卡地', cityName),
      if (isShanghai)
        summaryField(
          context,
          '识别状态',
          app.shanghaiTransitUnion?.status.label ?? '未知',
        ),
      if (cardKind != null)
        summaryField(context, '卡种', app.cardKindName(cardKind) ?? cardKind),
      summaryField(context, '卡号', cardNumber),
      // 仅读到 NFC 标签（未解析成功）时补充 UID，与模块文档说明一致。
      if (parsed == null && result != null)
        summaryField(context, 'UID', result.uid),
      if (isLocal && local != null && local.info.balance != 0)
        summaryField(
          context,
          '余额',
          '${(local.info.balance / 100).toStringAsFixed(2)} 元',
        ),
      if (separateObservation) ...[
        summaryField(context, '余额', interpretation!.accountBalanceText),
        if (interpretation.observedBalanceText case final observed?)
          summaryField(context, interpretation.observationLabel, observed),
        if (interpretation.semantics == BalanceSemantics.tuObservation)
          summaryField(context, '余额说明', 'TU侧金额不能直接作为港币账户余额'),
      ],
      // Direct non-Octopus cards retain the existing currency policy.
      if (isTUnion && !separateObservation && balanceText != null)
        summaryField(context, '余额', balanceText),
      // 上海卡 CU 单侧可用时，TU 钱包不可读，单独展示住建部钱包余额
      // （双应用卡统一在下方的双应用区块中展示，避免重复）。
      if (isShanghai &&
          balanceFen == null &&
          parsed?.dualApplication != true &&
          app.cityUnionBalanceFen != null)
        summaryField(
          context,
          '城市一卡通余额',
          '${(app.cityUnionBalanceFen! / 100).toStringAsFixed(2)} 元',
        ),
      if (expireDate != null)
        summaryField(context, '有效期至', summaryDate(expireDate)),
      if (isCityUnion && publicInfo?.applicationExpiryDate != null)
        summaryField(context, '有效期至', publicInfo!.applicationExpiryDate!),
      // 全国互联互通启用状态：两套网络分别判定，均以解析数据为准，不臆断。
      // - 交通联合（TU）：取自管理信息文件（SFI 0x17）「互通卡种」字段——
      //   部标口径 01 互通卡（已启用）/ 00 非互通卡（未启用），未读到管理
      //   信息文件或部标未定义取值时为未知；
      // - 城市一卡通（CU）：住建部「全国城市一卡通互联互通」网络，启用状态
      //   取自公共应用基本信息文件（SFI 0x15）字节 09 的互联互通启用标识；
      //   未读取到该文件时标记「未知」，不猜测、不隐藏。
      if (isTUnion)
        summaryField(
          context,
          '全国互联互通',
          tunionInteropText(info?.isNationalInteropEnabled),
        )
      else if (isCityUnion)
        summaryField(
          context,
          '全国互联互通',
          publicInfo == null
              ? '未知（未读到公共信息文件）'
              : publicInfo.isInterconnectionEnabled
              ? '已启用（城市一卡通）'
              : '未启用',
        ),
      // 双应用卡：在同一张物理卡上另有城市一卡通（住建部）钱包，与上面的
      // 交通联合余额分属两套独立网络，逐一列出避免混淆。
      if (parsed?.dualApplication == true) ...[
        summaryField(context, '城市一卡通应用', '已发现（双应用卡）'),
        if (app.cityUnionBalanceFen != null)
          summaryField(
            context,
            '城市一卡通余额',
            '${(app.cityUnionBalanceFen! / 100).toStringAsFixed(2)} 元',
          ),
        if (publicInfo?.cityCardNumber != null &&
            publicInfo!.cityCardNumber!.isNotEmpty)
          summaryField(
            context,
            '城市一卡通卡号',
            publicInfo.cityCardNumber!,
          ),
        summaryField(
          context,
          '城市一卡通互联互通',
          publicInfo == null
              ? '未知（未读到公共信息文件）'
              : publicInfo.isInterconnectionEnabled
              ? '已启用（城市一卡通）'
              : '未启用',
        ),
      ],
    ];
  }
}
