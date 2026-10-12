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
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  final AppState app;
  final bool active;
  const HomePage({super.key, required this.app, required this.active});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with NfcScanMixin<HomePage> {
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
                  if (result != null) ...[
                    const SizedBox(height: 12),
                    RepaintBoundary(
                      child: _SummaryCard(app: app),
                    ),
                  ],
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    child: _QrAcquireCard(app: app),
                  ),
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
                  if (app.hasQrData) ...[
                    const SizedBox(height: 12),
                    RepaintBoundary(
                      child: _QrSummaryCard(app: app),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final AppState app;
  const _SummaryCard({required this.app});

  @override
  Widget build(BuildContext context) {
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
    final issuerCity =
        prefix?.city ?? app.cityNameOf(app.cardInfo?.cityCode) ?? identity?.cityName ?? '—';

    final expireAt = wallet?.expireDate;
    final expireText = expireAt == null
        ? '—'
        : '${_fmtDate(expireAt)}${(wallet?.expired ?? false) ? '（已过期）' : ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近读取', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
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
            _row('类型', _cardTypeText()),
            _row('发卡地', issuerCity),
            _row('卡种', _cardKindText()),
            _row('卡号', wallet?.cardNumber ?? '—'),
            _row('余额', wallet?.balanceText ?? '—'),
            _row('有效期至', expireText),
            _row('全国互联互通', _interopText()),
          ],
        ),
      ),
    );
  }

  /// 卡片类型：按当前解析结果展示交通联合 / 城市一卡通；未命中显示 —。
  String _cardTypeText() {
    if (app.tunionDetected) return '交通联合';
    if (app.cityUnionDetected) return '城市一卡通';
    return '—';
  }

  /// 卡种：管理信息文件（SFI 0x17）卡种类型优先，回退持卡人文件卡类型标识；
  /// 已知取值（JT/T 978.2-2023 表 A.1）映射为名称，其余展示原始 HEX。
  String _cardKindText() {
    final info = app.cardInfo;
    final hex = info?.cardKind ?? info?.cardTypeId;
    if (hex == null || hex.isEmpty) return '—';
    return app.cardKindName(hex) ?? '0x$hex';
  }

  /// 全国互联互通启用状态：互通卡种（SFI 0x17）0000 表示发卡机构自定义
  /// 卡种（不参与互通），其余标准取值视为已启用；未读到显示 —。
  String _interopText() {
    final interop = app.cardInfo?.interopCardType;
    if (interop == null || interop.isEmpty) return '—';
    return interop == '0000' ? '未启用' : '已启用';
  }

  static String _fmtDate(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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

/// 二维码获取卡片：相机扫描 / 手动输入两个入口。
class _QrAcquireCard extends StatelessWidget {
  final AppState app;
  const _QrAcquireCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.qr_code_scanner,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('扫码读取乘车码',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '支持 JT/T 1179 交通一卡通乘车码，可相机扫描或手动输入原始数据',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => scanQrAndParse(context, app),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫描二维码'),
                ),
                OutlinedButton.icon(
                  onPressed: () => inputQrAndParse(context, app),
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('手动输入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 二维码摘要卡片：证书发卡机构（知识库前缀匹配）+ 关键字段。
class _QrSummaryCard extends StatelessWidget {
  final AppState app;
  const _QrSummaryCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final JtT1179QrData qr = app.qrData!;
    // 发卡机构：证书 BCD 发卡机构标识（8 位）→ 卡前缀库名称 / 发卡地
    final issuerId = qr.issuerIdText;
    final prefix = app.cardPrefixByIssuerId(issuerId);
    final issuerName = prefix?.cardName ??
        (issuerId == null ? '未知发卡机构' : '未收录机构（$issuerId）');
    final validUntil = qr.qrValidUntilUtc.toLocal();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('最近扫描二维码',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: app.clearQr,
                  tooltip: '清除二维码结果',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
            _row('支付账户号',
                qr.paymentAccountDigits ?? qr.paymentAccountNumberHex),
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
          ],
        ),
      ),
    );
  }

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
