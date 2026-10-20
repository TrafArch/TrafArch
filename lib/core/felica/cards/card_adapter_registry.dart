library;

import 'felica_card_adapter.dart';
import 'generic_adapter.dart';
import 'octopus_adapter.dart';
import 'suica_adapter.dart';

/// 适配器注册表：按注册顺序匹配，全部未命中时回退通用适配器。
///
/// 判定原则：
/// 1. 先执行基础协议探测（由读取编排层完成：NFC-F / IDm / 系统码）；
/// 2. 卡型识别由各卡种独立识别器完成（如 SuicaDetector 的
///    Request Service 探测与记录格式校验）；
/// 3. 匹配规则可靠时才使用专用适配器；
/// 4. 无法确认卡种时使用通用模式，展示原始数据与读取状态；
/// 5. 不允许仅凭 IDm 前缀认定卡型。
class CardAdapterRegistry {
  CardAdapterRegistry([List<FelicaCardAdapter> adapters = const []])
      : _adapters = [...adapters];

  final List<FelicaCardAdapter> _adapters;

  /// 默认注册表：Suica（经 SuicaDetector 服务探测后匹配）→ 八达通 → 通用兜底。
  factory CardAdapterRegistry.defaults() => CardAdapterRegistry([
        const SuicaAdapter(),
        const OctopusAdapter(),
      ]);

  void register(FelicaCardAdapter adapter) => _adapters.add(adapter);

  /// 选择适配器：匹配失败一律回退 GenericFelicaAdapter，不返回 null。
  Future<FelicaCardAdapter> select(FelicaCardContext context) async {
    for (final adapter in _adapters) {
      if (await adapter.matches(context)) return adapter;
    }
    return const GenericFelicaAdapter();
  }
}