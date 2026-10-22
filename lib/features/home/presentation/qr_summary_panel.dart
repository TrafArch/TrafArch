import 'package:flutter/material.dart';

import '../../qr/presentation/jt_t1179_qr_display.dart';
import '../../../app/app_dependencies.dart';

import 'summary_widgets.dart';

class QrSummaryPanel extends StatelessWidget {
  const QrSummaryPanel({super.key, required this.app});
  final AppDependencies app;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _qrPanel(context, app),
  );
  List<Widget> _qrPanel(BuildContext context, AppDependencies app) {
    final qr = app.qrData;
    if (qr == null) return const [];
    final issuerName =
        app.cardPrefixByIssuerId(qr.issuerIdText)?.cardName ?? '未知';
    final paymentAccount =
        qr.paymentAccountDigits ?? qr.paymentAccountNumberHex;
    final userAccount =
        qr.userAccountNumberText ??
        qr.userAccountDigits ??
        qr.userAccountNumberHex;
    final issuerCode = qr.issuerCodeText ?? qr.issuerCodeHex;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '交通联合乘车码（JT/T 1179）',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      const SizedBox(height: 8),
      summaryField(context, '发卡机构', issuerName),
      summaryField(context, '支付账户号', paymentAccount),
      summaryField(context, '用户账户号', userAccount),
      summaryField(context, '发卡机构代码', issuerCode),
      summaryField(
        context,
        '二维码状态',
        qr.isQrExpired() ? '已超出生成时间 + 有效时间窗口' : '有效期内',
      ),
    ];
  }
}
