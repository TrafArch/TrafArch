/// 解析异常 / 受限说明：按阶段记录，不伪装成功，也不携带敏感数据。
class ParseIssue {
  final String stage;
  final String code;
  final String message;

  const ParseIssue({
    required this.stage,
    required this.code,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'code': code,
    'message': message,
  };
}
