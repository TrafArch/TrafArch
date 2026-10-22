import '../models/card_application.dart';
import 'card_transport.dart';

/// 银行卡应用解析器统一接口。
abstract interface class CardParser {
  String get parserId;

  /// 依据已获取的应用信息（AID / 标签）与明确规则判断是否适用。
  bool supports(CardApplication application);

  /// 执行本解析器允许的读取步骤并返回结构化结果；
  /// 不支持的应用不得伪装为解析成功。
  Future<ParsedApplication> parse(
    CardApplication application,
    CardTransport transport,
  );
}
