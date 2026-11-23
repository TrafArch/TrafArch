/// 读卡识途（Trip Reader）数据导入的预留接口。
///
/// 目前只定义契约和明确的「开发中」结果，尚未实现解析：
/// - 不读取、也不解析读卡识途的数据格式；
/// - 不访问网络；
/// - 不写入本机档案。
///
/// 后续接入时，由真实实现替换 [TripReaderImportService]，把读卡识途的
/// 数据映射为 TrafArch 的卡片与读取批次；在此之前 UI 只提示开发中，
/// 不会调用这里的任何方法。
library;

/// 读卡识途数据尚未支持时抛出的异常。
class TripReaderImportUnavailable implements Exception {
  const TripReaderImportUnavailable();

  /// 面向用户的固定文案，与设置页「导入卡片记录」弹窗保持一致。
  static const message = '正在开发中，敬请期待';

  @override
  String toString() => '读卡识途数据导入$message（接口已预留，尚未实现）';
}

/// 读卡识途导入的预览结果。字段刻意保持最小，避免提前绑定外部数据格式。
class TripReaderImportPreview {
  const TripReaderImportPreview({
    required this.name,
    required this.summary,
    this.recordCount = 0,
  });

  /// 数据来源名称，例如文件或导出批次的名字。
  final String name;

  /// 供确认弹窗展示的摘要。
  final String summary;

  /// 识别到的记录条数；未实现解析时保持 0。
  final int recordCount;
}

/// 读卡识途导入的结果。
class TripReaderImportResult {
  const TripReaderImportResult({
    this.insertedCards = 0,
    this.mergedCards = 0,
    this.records = 0,
  });

  final int insertedCards;
  final int mergedCards;
  final int records;
}

/// 读卡识途数据导入的服务契约。
abstract interface class TripReaderImportService {
  /// 选择并解析读卡识途数据，返回待确认的预览；用户取消时返回 null。
  Future<TripReaderImportPreview?> pickImport();

  /// 确认导入最近一次预览的数据。
  Future<TripReaderImportResult> confirmImport(TripReaderImportPreview preview);
}

/// 占位实现：所有方法都抛出 [TripReaderImportUnavailable]。
///
/// UI 当前不调用它；保留该类是为了让后续接入方有明确的替换点和失败语义。
class UnavailableTripReaderImportService implements TripReaderImportService {
  const UnavailableTripReaderImportService();

  @override
  Future<TripReaderImportPreview?> pickImport() async =>
      throw const TripReaderImportUnavailable();

  @override
  Future<TripReaderImportResult> confirmImport(
    TripReaderImportPreview preview,
  ) async => throw const TripReaderImportUnavailable();
}
