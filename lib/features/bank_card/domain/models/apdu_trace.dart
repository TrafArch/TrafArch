import '../../data/apdu/status_word.dart';

/// 单步 APDU 追踪（供 APDU 日志页展示，默认不含解析后的敏感字段）。
class ApduTrace {
  final String stepName;
  final String commandHex;
  final String responseHex;
  final int? statusWord;
  final int elapsedMs;
  final String? errorCode;

  const ApduTrace({
    required this.stepName,
    required this.commandHex,
    required this.responseHex,
    this.statusWord,
    this.elapsedMs = 0,
    this.errorCode,
  });

  String get statusText =>
      statusWord == null ? '无响应' : StatusWord.describe(statusWord!);

  Map<String, dynamic> toJson() => {
        'stepName': stepName,
        'commandHex': commandHex,
        'responseHex': responseHex,
        if (statusWord != null) 'statusWord': statusWord,
        'elapsedMs': elapsedMs,
        if (errorCode != null) 'errorCode': errorCode,
      };
}