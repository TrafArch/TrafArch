import 'emv_application.dart';
import '../../../transport/transport_failure.dart';

/// 单个候选 AID 的失败说明（发现阶段的结构化诊断，不含敏感数据）。
class EmvCandidateFailure {
  const EmvCandidateFailure({
    required this.aidHex,
    required this.reason,
    required this.message,
    this.statusHex,
  });

  final String aidHex;
  final String reason; // select_rejected / fci_error / io_error
  final String message;
  final String? statusHex;
}

/// 一次 EMV 应用发现的完整结果。
class EmvDiscoveryResult {
  const EmvDiscoveryResult({
    required this.applications,
    required this.failures,
    required this.diagnostics,
    required this.usedFallback,
    this.transportFailure,
  });

  final List<EmvApplication> applications;
  final List<EmvCandidateFailure> failures;
  final List<String> diagnostics;

  /// PPSE 未得到任何 AID、使用了内置回退表时为 true。
  final bool usedFallback;
  final TransportFailure? transportFailure;

  bool get hasApplications => applications.isNotEmpty;
}
