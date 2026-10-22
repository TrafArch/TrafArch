import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../qr/presentation/jt_t1179_qr_display.dart';
import '../../protocols/transit/qr/jt_t1179_qr_parser.dart';

class QrInspectionPanel extends StatelessWidget {
  const QrInspectionPanel({
    super.key,
    required this.qr,
    required this.error,
    required this.raw,
    required this.issuerName,
    required this.onClear,
  });
  final JtT1179QrData? qr;
  final String? error;
  final List<int>? raw;
  final String issuerName;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Column(children: _qrSection(context));
  List<Widget> _qrSection(BuildContext context) {
    if (qr == null) {
      // 外层（_infoGetTabBody）已排除空态：qr 为 null 时必有解析失败原因
      return [
        ExpertField('状态', '解析失败'),
        ExpertField('原因', expertValue(error)),
        ExpertField('原始数据', '${raw?.length ?? 0} 字节'),
        const SizedBox(height: 6),
        if (raw != null) ExpertHex(hexBytes(raw!)),
        const SizedBox(height: 12),
        ExpertHomeHint('可返回首页重新扫描或从相册导入乘车码'),
        const SizedBox(height: 12),
        _qrClearButton(),
      ];
    }
    return [
      ..._qrDetailFields(qr!),
      const Divider(height: 28),
      _qrCertificateTile(context, qr!),
      _qrRawTile(context, qr!),
      const SizedBox(height: 12),
      _qrClearButton(),
    ];
  }

  Widget _qrClearButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onClear,
        icon: const Icon(Icons.clear),
        label: const Text('清除'),
      ),
    );
  }

  /// 二维码解析字段视图（表 2 全字段）。
  List<Widget> _qrDetailFields(JtT1179QrData qr) {
    final cert = qr.issuerCertificate;
    final issuerId = qr.issuerIdText;
    return [
      ExpertField('版本', qr.versionHex),
      ExpertField('声明长度', '${qr.declaredLength} 字节（数据体，自证书起）'),
      ExpertField('数据总长', '${qr.raw.length} 字节'),
      ExpertField('发卡机构名称', issuerName),
      ExpertField('发卡机构标识', issuerId ?? hexBytes(cert.issuerIdBytes)),
      ExpertField(
        '支付账户号',
        qr.paymentAccountDigits ?? qr.paymentAccountNumberHex,
      ),
      ExpertField(
        '用户账户号',
        qr.userAccountNumberText ??
            qr.userAccountDigits ??
            qr.userAccountNumberHex,
      ),
      ExpertField('发卡机构代码', qr.issuerCodeText ?? qr.issuerCodeHex),
      ExpertField('发码平台代码', qr.platformCodeText ?? qr.platformCodeHex),
      ExpertField('用户账户类型', '0x${hexByte(qr.userAccountType)}'),
      ExpertField(
        '单次消费金额上限',
        '${(qr.singleConsumptionLimitFen / 100).toStringAsFixed(2)} 元',
      ),
      ExpertField('支付账户用户公钥', qr.userPublicKeyHex),
      ExpertField(
        '授权过期时间',
        '${expertTime(qr.authorizationExpiryUtc.toLocal())}'
            '${qr.isAuthorizationExpired() ? '（已过期）' : ''}',
      ),
      ExpertField('二维码有效时间', '${qr.qrValiditySeconds} 秒'),
      ExpertField('二维码生成时间', expertTime(qr.generationTimeUtc.toLocal())),
      ExpertField('二维码状态', qr.isQrExpired() ? '已超出生成时间 + 有效时间窗口' : '有效期内'),
      ExpertField(
        '发卡机构自定义域',
        qr.issuerDefinedLength == 0
            ? '无（长度 0）'
            : '${qr.issuerDefinedLength} 字节',
      ),
      if (qr.issuerDefinedLength > 0) ...[
        const SizedBox(height: 6),
        ExpertHex(qr.issuerDefinedDataHex),
      ],
    ];
  }

  /// 发卡机构公钥证书（117 字节）子菜单。
  Widget _qrCertificateTile(BuildContext context, JtT1179QrData qr) {
    final scheme = Theme.of(context).colorScheme;
    final cert = qr.issuerCertificate;
    return ExpansionTile(
      key: const PageStorageKey<String>('qr-certificate'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('发卡机构公钥证书（117 字节）'),
      subtitle: Text(
        '发卡机构 ${qr.issuerIdText ?? '未知'} · '
        '失效 ${expertDate(cert.expiryDateUtc.toLocal())}'
        '${cert.isExpired() ? '（已过期）' : ''}',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: [
        ExpertField('记录头', '0x${hexByte(cert.recordHeader)}'),
        ExpertField(
          '服务标识',
          '${cert.serviceIdHex}'
              '${cert.isTransportEcashService ? '（交通电子现金应用）' : ''}',
        ),
        ExpertField('中心 CA 公钥索引', '${cert.caPublicKeyIndex}'),
        ExpertField('证书格式', '0x${hexByte(cert.certificateFormat)}'),
        ExpertField('发卡机构标识', qr.issuerIdText ?? hexBytes(cert.issuerIdBytes)),
        ExpertField('证书失效日期', expertDate(cert.expiryDateUtc.toLocal())),
        ExpertField('证书序列号', cert.serialNumberHex),
        ExpertField(
          '公钥签名算法',
          '0x${hexByte(cert.signatureAlgorithm)}'
              '${cert.usesSm2Signature ? '（SM2）' : ''}',
        ),
        ExpertField('公钥加密算法（保留）', '0x${hexByte(cert.encryptionAlgorithm)}'),
        ExpertField('公钥参数标识', '0x${hexByte(cert.publicKeyParameter)}'),
        ExpertField('公钥长度', '0x${hexByte(cert.publicKeyLength)}（33 字节）'),
        ExpertField('发卡机构公钥', cert.issuerPublicKeyHex),
        const SizedBox(height: 6),
        _titledHexBlock(
          context,
          title: '证书原始数据（117 字节）',
          hex: hexBytes(cert.raw),
        ),
      ],
    );
  }

  /// 二维码原始数据子菜单。
  Widget _qrRawTile(BuildContext context, JtT1179QrData qr) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const PageStorageKey<String>('qr-raw'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('二维码原始数据'),
      subtitle: Text(
        '${qr.raw.length} 字节（声明长度 ${qr.declaredLength} 字节）',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: [ExpertHex(hexBytes(qr.raw))],
    );
  }

  /// 标题 + HEX 数据块（长数据展示用）。
  Widget _titledHexBlock(
    BuildContext context, {
    required String title,
    required String hex,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        ExpertHex(hex),
      ],
    );
  }
}
