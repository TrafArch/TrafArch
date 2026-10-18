import 'package:flutter/material.dart';

import '../../core/card/card_parser.dart';
import '../../core/nfc/nfc_models.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_display.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_parser.dart';
import '../../state/app_state.dart';
import '../bank_card/domain/models/bank_card_result.dart';
import '../bank_card/domain/models/card_application.dart';
import '../bank_card/presentation/application_detail_page.dart';
import '../card_archive/models/card_types.dart';

/// 「最近扫描」展示类型：NFC 卡片 / 乘车码二维码 / 银行卡只读分析。
enum _RecentScanKind { card, qr, bank }

/// 首页「最近扫描」模块（版式：模块标题 → 卡片名称 → 分隔线 → 字段列表）。
///
/// - 卡片视图按最新一次读取自动切换类型：交通联合（TU）与城市一卡通
///   （CU）按解析结果展示对应字段；交通应用未命中时自动展示 EMV / PBOC
///   银行卡只读分析结果，无需手动切换；
/// - 乘车码（JT/T 1179）保持原有逻辑：获取成功后模块内嵌展示二维码字段，
///   卡片与二维码等多类数据并存时由顶部分段按钮手动切换（不跳转子页面）；
/// - 无任何数据时不占用页面空间（返回空尺寸）。数据获取入口在首页
///   上方模块，本模块只负责展示，不发起任何读取 / 扫描操作。
class RecentScanSection extends StatefulWidget {
  final AppState app;

  const RecentScanSection({super.key, required this.app});

  @override
  State<RecentScanSection> createState() => _RecentScanSectionState();
}

class _RecentScanSectionState extends State<RecentScanSection> {
  /// 当前展示类型；随新数据自动切换，或由用户手动切换。
  _RecentScanKind _kind = _RecentScanKind.card;

  /// 上一次已见到的最新数据对象，用于识别新数据并自动切换展示类型。
  NfcScanResult? _seenCard;
  JtT1179QrData? _seenQr;
  BankCardResult? _seenBank;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    _seenCard = app.lastResult;
    _seenQr = app.qrData;
    _seenBank = app.lastBankCardResult;
    if (_seenCard == null && _seenQr == null && _seenBank != null) {
      _kind = _RecentScanKind.bank;
    } else if (_seenCard == null && _seenQr != null) {
      _kind = _RecentScanKind.qr;
    }
    app.addListener(_onAppChanged);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    final app = widget.app;
    if (!identical(app.lastResult, _seenCard)) {
      _seenCard = app.lastResult;
      // 新读到卡片：自动切换到卡片信息
      if (app.lastResult != null) _kind = _RecentScanKind.card;
    }
    if (!identical(app.qrData, _seenQr)) {
      _seenQr = app.qrData;
      // 新获取到二维码：自动切换到二维码信息
      if (app.qrData != null) _kind = _RecentScanKind.qr;
    }
    if (!identical(app.lastBankCardResult, _seenBank)) {
      _seenBank = app.lastBankCardResult;
      // 新完成银行卡分析：自动切换到银行卡信息
      if (app.lastBankCardResult != null) _kind = _RecentScanKind.bank;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final bankResult = app.lastBankCardResult;
    // 银行卡分析结果存在（交通应用未命中）时不再展示空交通卡片视图。
    final hasCard = app.parsedCard != null ||
        (app.lastResult != null && bankResult == null);
    final hasQr = app.qrData != null;
    final hasBank = bankResult != null;
    if (!hasCard && !hasQr && !hasBank) return const SizedBox.shrink();

    final available = <_RecentScanKind>[
      if (hasCard) _RecentScanKind.card,
      if (hasQr) _RecentScanKind.qr,
      if (hasBank) _RecentScanKind.bank,
    ];
    final kind = available.contains(_kind) ? _kind : available.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最近扫描',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (available.length > 1) ...[
              SegmentedButton<_RecentScanKind>(
                segments: [
                  if (hasCard)
                    const ButtonSegment(
                      value: _RecentScanKind.card,
                      label: Text('NFC 卡片'),
                    ),
                  if (hasQr)
                    const ButtonSegment(
                      value: _RecentScanKind.qr,
                      label: Text('乘车码二维码'),
                    ),
                  if (hasBank)
                    const ButtonSegment(
                      value: _RecentScanKind.bank,
                      label: Text('银行卡'),
                    ),
                ],
                selected: {kind},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                onSelectionChanged: (selection) {
                  setState(() => _kind = selection.first);
                },
              ),
              const SizedBox(height: 12),
            ],
            ...switch (kind) {
              _RecentScanKind.card => _cardPanel(context, app),
              _RecentScanKind.qr => _qrPanel(context, app),
              _RecentScanKind.bank => _bankPanel(context, bankResult!),
            },
          ],
        ),
      ),
    );
  }

  /// 卡片面板（TU / CU 自动切换）：名称 + 字段列表。解析成功时展示
  /// 类型 / 发卡地 / 卡种 / 卡号 / 余额 / 有效期至 / 全国互联互通；
  /// 仅读到 NFC 标签（未解析成功）时展示 UID 与卡型摘要。卡号完整
  /// 展示（不脱敏）。
  List<Widget> _cardPanel(BuildContext context, AppState app) {
    final result = app.lastResult;
    final parsed = app.parsedCard;
    final identified = app.lastIdentified;
    final isTUnion = parsed?.parserId == CardParserIds.tunion;
    final isCityUnion = parsed?.parserId == CardParserIds.cityUnion;
    final isLocal = parsed?.parserId == CardParserIds.localCard;
    final local = parsed?.localCard;
    final info = parsed?.info;
    final publicInfo = app.cityUnionPublicInfo;
    final wallet = app.analysis?.wallet;
    final cardKind = isTUnion ? info?.cardKind : null;
    final expireDate = isTUnion ? info?.expireDate : null;

    // 卡片名称：正式卡名优先（识别引擎），未识别时回退卡型通用名称。
    final name = identified != null
        ? identified.displayName
        : parsed == null
            ? '未识别卡片'
            : isLocal
                ? local!.info.cardKindLabel
                : cardTypeLabel(
                    isCityUnion ? CardTypes.cityUnion : CardTypes.chinaTunion,
                  );
    // 发卡地：识别城市优先，回退城市码表（与识别引擎链路一致）。
    final cityName =
        identified?.identity.cityName ?? app.cityNameOf(app.cardCityCode);
    // 卡号（完整，不脱敏）：识别结果优先，回退解析字段，最后回退 UID。
    final cardNumber = identified?.cardNumber ??
        (isLocal
            ? (local!.info.cardNumber.isEmpty
                ? null
                : local.info.cardNumber)
            : isCityUnion
                ? publicInfo?.applicationSerialNumber
                : info?.displayCardNumber) ??
        result?.uid ??
        '未知';

    return [
      ..._nameLine(context, name),
      if (parsed != null)
        _kv(
          context,
          '类型',
          isLocal
              ? '地方交通卡'
              : cardTypeLabel(
                  isCityUnion ? CardTypes.cityUnion : CardTypes.chinaTunion,
                ),
        )
      else if (result?.cardType != null)
        _kv(context, '卡型', result!.cardType!),
      if (cityName != null && cityName.isNotEmpty)
        _kv(context, '发卡地', cityName),
      if (cardKind != null)
        _kv(context, '卡种', app.cardKindName(cardKind) ?? cardKind),
      _kv(context, '卡号', cardNumber),
      if (isLocal && local != null && local.info.balance != 0)
        _kv(
          context,
          '余额',
          '${(local.info.balance / 100).toStringAsFixed(2)} 元',
        ),
      if (isTUnion && wallet?.balanceText != null)
        _kv(context, '余额', wallet!.balanceText!),
      if (expireDate != null) _kv(context, '有效期至', _fmtDate(expireDate)),
      if (isCityUnion && publicInfo?.applicationExpiryDate != null)
        _kv(context, '有效期至', publicInfo!.applicationExpiryDate!),
      // 全国互联互通启用状态：两套网络分别判定，均以解析数据为准，不臆断。
      // - 交通联合（TU）：取自管理信息文件（SFI 0x17）「互通卡种」字段——
      //   部标口径 01 互通卡（已启用）/ 00 非互通卡（未启用），未读到管理
      //   信息文件或部标未定义取值时为未知；
      // - 城市一卡通（CU）：住建部「全国城市一卡通互联互通」网络，启用状态
      //   取自公共应用基本信息文件（SFI 0x15）字节 09 的互联互通启用标识；
      //   未读取到该文件时标记「未知」，不猜测、不隐藏。
      if (isTUnion)
        _kv(
          context,
          '全国互联互通',
          _tuInteropText(info?.isNationalInteropEnabled),
        )
      else if (isCityUnion)
        _kv(
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
        _kv(context, '城市一卡通应用', '已发现（双应用卡）'),
        if (app.cityUnionBalanceFen != null)
          _kv(
            context,
            '城市一卡通余额',
            '${(app.cityUnionBalanceFen! / 100).toStringAsFixed(2)} 元',
          ),
        if (publicInfo?.applicationSerialNumber != null &&
            publicInfo!.applicationSerialNumber!.isNotEmpty)
          _kv(context, '城市一卡通卡号', publicInfo.applicationSerialNumber!),
        _kv(
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

  /// 二维码面板（JT/T 1179 表 2）：发卡机构（按前缀库解析）、支付账户号、
  /// 用户账户号与有效状态；完整字段（证书 / 签名长度 / 原始数据）见专家页。
  List<Widget> _qrPanel(BuildContext context, AppState app) {
    final qr = app.qrData;
    if (qr == null) return const [];
    final issuerName =
        app.cardPrefixByIssuerId(qr.issuerIdText)?.cardName ?? '未知';
    final paymentAccount =
        qr.paymentAccountDigits ?? qr.paymentAccountNumberHex;
    final userAccount = qr.userAccountNumberText ??
        qr.userAccountDigits ??
        qr.userAccountNumberHex;
    final issuerCode = qr.issuerCodeText ?? qr.issuerCodeHex;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '交通联合乘车码（JT/T 1179）',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      const SizedBox(height: 8),
      _kv(context, '发卡机构', issuerName),
      _kv(context, '支付账户号', paymentAccount),
      _kv(context, '用户账户号', userAccount),
      _kv(context, '发卡机构代码', issuerCode),
      _kv(
        context,
        '二维码状态',
        qr.isQrExpired() ? '已超出生成时间 + 有效时间窗口' : '有效期内',
      ),
    ];
  }

  /// 名称行：卡片名称 + 分隔线（版式与设计稿一致）。
  List<Widget> _nameLine(BuildContext context, String name) => [
        Text(
          name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Divider(height: 20),
      ];

  /// 银行卡面板（EMV / PBOC 只读分析）：名称 + 概览字段 + 应用列表；
  /// 点击应用进入应用详情页查看完整标签树与记录；解析异常汇总条数，
  /// 明细见应用详情页。
  List<Widget> _bankPanel(BuildContext context, BankCardResult bank) {
    return [
      ..._nameLine(context, '银行卡（EMV / PBOC）'),
      _kv(
        context,
        '协议族',
        bank.protocolFamily == BankCardProtocolFamily.pboc
            ? 'PBOC（JR/T 0025 系列规则）'
            : 'EMV（通用规范规则）',
      ),
      _kv(context, '结果状态', _bankStatusText(bank)),
      if (bank.applications.isEmpty)
        _hint(context, '未解析到应用：${_bankEmptyReason(bank)}')
      else ...[
        const SizedBox(height: 4),
        for (final application in bank.applications)
          _bankApplicationTile(context, application),
      ],
      if (bank.issues.isNotEmpty)
        _hint(context, '读取与解析异常 ${bank.issues.length} 项（明细见应用详情）'),
    ];
  }

  Widget _bankApplicationTile(
    BuildContext context,
    ParsedApplication application,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = application.application.selected;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.credit_score : Icons.credit_card_off,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(application.application.displayLabel),
      subtitle: Text(
        'AID ${application.application.aidHex}'
        ' · 记录 ${application.records.length} 条'
        '${application.issues.isEmpty ? '' : ' · 异常 ${application.issues.length} 项'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ApplicationDetailPage(application: application),
        ),
      ),
    );
  }

  String _bankStatusText(BankCardResult bank) => switch (bank.status) {
        BankCardStatus.noCard => '未读到应用数据',
        BankCardStatus.enumerationFailed => _bankEnumerationText(bank),
        BankCardStatus.partial => '部分解析成功（仅公开可读数据）',
        BankCardStatus.success => '解析完成',
      };

  /// 银行卡枚举失败文案：优先展示具体原因码，避免统一盖成「PPSE 不支持」。
  String _bankEnumerationText(BankCardResult bank) {
    for (final issue in bank.issues) {
      if (issue.stage == 'enumeration' || issue.stage == 'ppse') {
        return '应用枚举未完成（${issue.code}）';
      }
    }
    return '应用枚举未完成';
  }

  String _bankEmptyReason(BankCardResult bank) {
    for (final issue in bank.issues) {
      if (issue.stage == 'ppse') return issue.message;
    }
    return bank.status == BankCardStatus.enumerationFailed
        ? '卡片未返回应用目录（PPSE），或读取被访问条件拒绝'
        : '未读到可展示的应用数据';
  }

  Widget _kv(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );

  static String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// 交通联合「互通卡种」推导的全国互联互通启用状态文案：与解析层
  /// [TUnionCardInfo.isNationalInteropEnabled] 的 bool? 三态一一对应
  /// （true 互通卡 / false 非互通卡 / null 未知），不猜测。
  static String _tuInteropText(bool? enabled) => switch (enabled) {
        true => '已启用（互通卡）',
        false => '未启用（非互通卡）',
        null => '未知（未读到管理信息文件或部标未定义取值）',
      };
}