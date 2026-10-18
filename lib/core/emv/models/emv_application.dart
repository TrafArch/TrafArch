// D:\iteam\TrafArch\lib\core\emv\models\emv_application.dart
/// 一个已发现的 EMV 应用（发现/枚举阶段的产物）。
class EmvApplication {
  const EmvApplication({
    required this.aidHex,
    this.label,
    this.preferredName,
    this.priority,
    this.fciHex,
  });

  final String aidHex;
  final String? label;
  final String? preferredName;
  final int? priority;
  final String? fciHex;

  /// 展示名：优先名称 → 标签 → AID（不猜测，缺失即回退上一级）。
  String get displayName => preferredName?.trim().isNotEmpty == true
      ? preferredName!.trim()
      : label?.trim().isNotEmpty == true
          ? label!.trim()
          : aidHex;
}