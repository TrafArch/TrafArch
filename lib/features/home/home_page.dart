import 'package:flutter/material.dart';
import '../../core/nfc/nfc_models.dart';
import '../../core/nfc/nfc_scan_mixin.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_display.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_parser.dart';
import '../../core/ui_constants.dart';
import '../../core/app_info.dart';
import '../../state/app_state.dart';
import '../qr/qr_acquire.dart';
import '../settings/settings_action_button.dart';

class HomePage extends StatefulWidget {
  final AppState app;
  final bool active;
  const HomePage({super.key, required this.app, required this.active});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with NfcScanMixin<HomePage> {
  /// 相册导入进行中（选图 / 图片识别），用于禁用按钮并展示进度。
  bool _qrImporting = false;

  @override
  AppState get app => widget.app;

  @override
  bool get isActive => widget.active;

  String get _statusText {
    if (app.parsing) return '已读到卡片，正在解析数据…';
    if (scanning) return '正在监听 NFC 标签…';
    if (error != null) return '读取失败，请点击下方按钮重试';
    if (result != null) return '读取完成，再次读取请点击下方按钮';
    return '点击下方按钮开始读取卡片信息';
  }

  String get _buttonLabel {
    if (error != null) return '重试';
    if (result != null) return '再次读取';
    return '开始读取';
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      // 离开首页：停止读取，释放 NFC 资源
      stopScan();
    } else if (!oldWidget.active && widget.active) {
      // 切回首页：尚未成功读取过则自动恢复读取模式；
      // 成功读取过则保持空闲，需点击下方按钮再次读取
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) enterAutoScanIfNeeded();
      });
    }
  }

  /// 从相册导入二维码：原生相册选图 → MLKit 识别 → 内置纯 Dart 解码兜底，
  /// 成功后解析并写入 [app]。
  Future<void> _importQrFromGallery() async {
    if (_qrImporting) return;
    setState(() => _qrImporting = true);
    try {
      await importQrFromGalleryAndParse(context, app);
    } finally {
      if (mounted) setState(() => _qrImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        cacheExtent: 300,
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(AppInfo.appName),
            actions: [SettingsActionButton(app: app)],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                UiConstants.floatingNavBarClearance,
              ),
              child: Column(
                children: [
                  // 贴卡读取与乘车码获取合并为同一模块展示
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(Icons.contactless,
                              size: 72,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            '请将卡片贴近手机背面',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _statusText,
                            textAlign: TextAlign.center,
                          ),
                          if (!scanning) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => startScan(),
                              icon: const Icon(Icons.nfc),
                              label: Text(_buttonLabel),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Divider(height: 1),
                          const SizedBox(height: 24),
                          Text(
                            '扫码读取乘车码',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            app.useGmsScanner
                                ? '支持 JT/T 1179 交通一卡通乘车码，可系统扫码或从相册导入'
                                : '支持 JT/T 1179 交通一卡通乘车码，可相机扫描或从相册导入',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => scanQrAndParse(context, app),
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('扫描二维码'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _qrImporting
                                    ? null
                                    : _importQrFromGallery,
                                icon: _qrImporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons.photo_library_outlined),
                                label: Text(
                                    _qrImporting ? '正在识别…' : '从相册导入'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('NFC 读取失败'),
                        subtitle: Text(error!),
                      ),
                    ),
                  ],
                  if (app.qrError != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('二维码解析失败'),
                        subtitle: Text(app.qrError!),
                        trailing: TextButton(
                          onPressed: app.clearQr,
                          child: const Text('清除'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // 最近扫描：卡片 / 二维码共用展示，支持切换类型
                  RepaintBoundary(
                    child: _RecentScanSection(app: app),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 最近扫描模块：展示最近一次获取的数据，支持在多种类型间切换。
///
/// 读取 NFC 卡片（交通联合 / 城市一卡通）后自动展示卡片信息，
/// 扫码或从相册导入二维码后自动展示二维码相关信息；
/// 两类数据并存时可通过顶部分段按钮手动切换查看。
class _RecentScanSection extends StatefulWidget {
  final AppState app;
  const _RecentScanSection({required this.app});

  @override
  State<_RecentScanSection> createState() => _RecentScanSectionState();
}

/// 最近扫描数据类型：NFC 卡片 / 乘车码二维码。
enum _RecentScanKind { card, qr }

class _RecentScanSectionState extends State<_RecentScanSection> {
  _RecentScanKind _selected = _RecentScanKind.card;

  // 上一次已见到的最新数据对象，用于跟随新的读取 / 扫描结果自动切换类型
  NfcScanResult? _seenResult;
  JtT1179QrData? _seenQr;

  @override
  void initState() {
    super.initState();
    _seenResult = widget.app.lastResult;
    _seenQr = widget.app.qrData;
    if (_seenResult == null) _selected = _RecentScanKind.qr;
  }

  @override
  void didUpdateWidget(covariant _RecentScanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final app = widget.app;
    if (!identical(app.lastResult, _seenResult)) {
      _seenResult = app.lastResult;
      // 新读到卡片：自动切换到卡片信息
      if (app.lastResult != null) _selected = _RecentScanKind.card;
    }
    if (!identical(app.qrData, _seenQr)) {
      _seenQr = app.qrData;
      // 新获取到二维码：自动切换到二维码信息
      if (app.qrData != null) _selected = _RecentScanKind.qr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final hasCard = app.lastResult != null;
    final hasQr = app.hasQrData;
    if (!hasCard && !hasQr) return const SizedBox.shrink();

    // 所选类型数据已被清除时回退到另一类型
    if (_selected == _RecentScanKind.card && !hasCard) {
      _selected = _RecentScanKind.qr;
    } else if (_selected == _RecentScanKind.qr && !hasQr) {
      _selected = _RecentScanKind.card;
    }
    final kind = _selected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('最近扫描',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (kind == _RecentScanKind.qr)
                  IconButton(
                    onPressed: app.clearQr,
                    tooltip: '清除二维码结果',
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 两类数据并存时才提供手动切换
            if (hasCard && hasQr) ...[
              SegmentedButton<_RecentScanKind>(
                segments: [
                  ButtonSegment(
                    value: _RecentScanKind.card,
                    label: Text(_cardSegmentLabel(app)),
                  ),
                  const ButtonSegment(
                    value: _RecentScanKind.qr,
                    label: Text('乘车码二维码'),
                  ),
                ],
                selected: {kind},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _selected = selection.first);
                },
              ),
              const SizedBox(height: 8),
            ],
            ...(kind == _RecentScanKind.card
                ? _cardInfo(context, app)
                : _qrInfo(context, app)),
          ],
        ),
      ),
    );
  }

  /// 卡片分段标签：按当前解析结果展示具体卡型。
  String _cardSegmentLabel(AppState app) {
    if (app.tunionDetected) return '交通联合卡片';
    if (app.cityUnionDetected) return '城市一卡通卡片';
    return 'NFC 卡片';
  }

  /// 卡片信息（交通联合 JT/T 978.2 / 城市一卡通 CJ/T 331-2016）。
  List<Widget> _cardInfo(BuildContext context, AppState app) {
    final analysis = app.analysis;
    final identity = analysis?.identity;
    final wallet = analysis?.wallet;

    // 卡片名称：卡号前 8 位（IIN）前缀库优先，回退指纹库识别结果
    final prefix = app.cardPrefixOf(wallet?.cardNumber);
    final cardName = prefix?.cardName ??
        identity?.cardFamily ??
        identity?.operatorName ??
        '—';
    // 发卡地：前缀库城市优先，回退管理信息文件城市代码 → 识别城市
    final issuerCity = prefix?.city ??
        app.cityNameOf(app.cardInfo?.cityCode) ??
        identity?.cityName ??
        '—';

    final expireAt = wallet?.expireDate;
    final expireText = expireAt == null
        ? '—'
        : '${_fmtDate(expireAt)}'
            '${(wallet?.expired ?? false) ? '（已过期）' : ''}';

    return [
      Text(
        cardName,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
      const SizedBox(height: 8),
      const Divider(height: 20),
      // 类型：交通联合（JT/T 978.2）或城市一卡通（CJ/T 331-2016）
      // 解析命中时展示对应名称
      _row('类型', _cardTypeText(app)),
      _row('发卡地', issuerCity),
      _row('卡种', _cardKindText(app)),
      _row('卡号', wallet?.cardNumber ?? '—'),
      _row('余额', wallet?.balanceText ?? '—'),
      _row('有效期至', expireText),
      _row('全国互联互通', _interopText(app)),
    ];
  }

  /// 二维码信息（JT/T 1179 乘车码）。
  List<Widget> _qrInfo(BuildContext context, AppState app) {
    final JtT1179QrData qr = app.qrData!;
    // 发卡机构：证书 BCD 发卡机构标识（8 位）→ 卡前缀库名称 / 发卡地
    final issuerId = qr.issuerIdText;
    final prefix = app.cardPrefixByIssuerId(issuerId);
    final issuerName = prefix?.cardName ??
        (issuerId == null ? '未知发卡机构' : '未收录机构（$issuerId）');
    final validUntil = qr.qrValidUntilUtc.toLocal();

    return [
      Text(
        issuerName,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
      const SizedBox(height: 8),
      const Divider(height: 20),
      _row('类型', '交通联合乘车码（JT/T 1179）'),
      _row('版本', qr.versionHex),
      _row('发卡地', prefix?.city ?? '—'),
      _row('支付账户号', qr.paymentAccountDigits ?? qr.paymentAccountNumberHex),
      _row(
        '单次消费上限',
        '${(qr.singleConsumptionLimitFen / 100).toStringAsFixed(2)} 元',
      ),
      _row('生成时间', _fmtDateTime(qr.generationTimeUtc.toLocal())),
      _row(
        '有效期至',
        '${_fmtDateTime(validUntil)}'
            '${qr.isQrExpired() ? '（已过期）' : ''}',
      ),
    ];
  }

  /// 卡片类型：按当前解析结果展示交通联合 / 城市一卡通；未命中显示 —。
  String _cardTypeText(AppState app) {
    if (app.tunionDetected) return '交通联合';
    if (app.cityUnionDetected) return '城市一卡通';
    return '—';
  }

  /// 卡种：管理信息文件（SFI 0x17）卡种类型优先，回退持卡人文件卡类型标识；
  /// 已知取值（JT/T 978.2-2023 表 A.1）映射为名称，其余展示原始 HEX。
  String _cardKindText(AppState app) {
    final info = app.cardInfo;
    final hex = info?.cardKind ?? info?.cardTypeId;
    if (hex == null || hex.isEmpty) return '—';
    return app.cardKindName(hex) ?? '0x$hex';
  }

  /// 全国互联互通启用状态：互通卡种（SFI 0x17）0000 表示发卡机构自定义
  /// 卡种（不参与互通），其余标准取值视为已启用；未读到显示 —。
  String _interopText(AppState app) {
    final interop = app.cardInfo?.interopCardType;
    if (interop == null || interop.isEmpty) return '—';
    return interop == '0000' ? '未启用' : '已启用';
  }

  static String _fmtDate(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _fmtDateTime(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
        '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(a)),
            Expanded(child: Text(b)),
          ],
        ),
      );
}
