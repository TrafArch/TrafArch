import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'station_codes.dart';

/// 在线拉取站点数据的本地快照持久化（文本格式，非 JSON）。
///
/// 数据来源为在线拉取（tripreader_sync.dart）解析出的 [StationDataset]
/// 列表；应用启动时若「开启在线拉取数据」开关为开启且存在本地快照，
/// 则以快照取代应用内预制数据（prebuilt_station_data.dart），重启后
/// 继续生效，直至再次在线更新或关闭开关清除。
///
/// 完整性保障：
/// - 写入采用「临时文件 + 原子替换」，写入中断不会破坏上一次的完整快照；
/// - v2 格式在头部声明数据集数量、尾部写结束标记，加载时三者不一致
///   （写入中断/文件损坏）则整体拒绝并回退预制数据，避免加载半截
///   数据导致站点信息错乱。
///
/// 文本快照结构（v2，每数据集一个块）：
///
///     # transit_card_analyzer online station data v2 datasets=2
///     @Fujian/Fuzhou/metro-tu.csv|福州市|福建省|tu|metro
///     City,Code,Type,Line,Station
///     3910,02,地铁,2号线,
///     3910,0231,地铁,2号线,苏洋
///     # END datasets=2
///
/// `@` 开头为数据集头行（file|cityName|province|system|kind 以 `|` 分隔，
/// 避开 CSV 逗号）；其余行为标准 CSV 数据行（字段按 RFC 4180 风格引号
/// 转义），逐块复用 [parseTripreaderDatasetCsv] 解析。
abstract class OnlineDataStore {
  /// 读取本地快照；无快照或不可用时返回空列表。
  Future<List<StationDataset>> load();

  /// 覆盖保存快照（先序列化后写入）。
  Future<void> save(List<StationDataset> datasets);

  /// 删除本地快照（不存在时忽略）。
  Future<void> clear();
}

/// 文件实现：应用私有文档目录下的 online_station_data.txt
/// （与 app_settings.txt 同目录）。
class FileOnlineDataStore implements OnlineDataStore {
  static const fileName = 'online_station_data.txt';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<List<StationDataset>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final bytes = await file.readAsBytes();
      // 容错解码：文件被截断在多字节字符中间时也尽力恢复（v2 校验仍会把关）
      return parseOnlineDatasets(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      // 目录/文件不可用或内容损坏时按无快照降级（回退预制数据）
      return const [];
    }
  }

  @override
  Future<void> save(List<StationDataset> datasets) async {
    final file = await _file();
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 原子替换：先写临时文件，完成后 rename 覆盖正式文件，
    // 中途中断时旧快照保持完整（不会留下半截数据）
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(serializeOnlineDatasets(datasets), flush: true);
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        // 个别平台 rename 不支持覆盖已存在文件：先删再改名
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      }
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 临时文件清理失败忽略
      }
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
    // 清理可能残留的临时文件
    final tmp = File('${file.path}.tmp');
    if (await tmp.exists()) {
      await tmp.delete();
    }
  }
}

/// 内存实现：测试与无文件系统环境使用（存取同一文本快照格式）。
class MemoryOnlineDataStore implements OnlineDataStore {
  String? _text;

  @override
  Future<List<StationDataset>> load() async =>
      _text == null ? const [] : parseOnlineDatasets(_text!);

  @override
  Future<void> save(List<StationDataset> datasets) async {
    _text = serializeOnlineDatasets(datasets);
  }

  @override
  Future<void> clear() async => _text = null;
}

/// 序列化数据集列表为文本快照（文件存取与测试共用）。
/// 头部/尾部写入数据集数量标记，供 [parseOnlineDatasets] 做完整性校验。
String serializeOnlineDatasets(List<StationDataset> datasets) {
  final buffer = StringBuffer()
    ..writeln('# transit_card_analyzer online station data v2 '
        'datasets=${datasets.length}');
  for (final dataset in datasets) {
    buffer
      ..writeln('@${dataset.file}|${dataset.cityName ?? ''}|'
          '${dataset.province ?? ''}|${dataset.system}|${dataset.kind}')
      ..writeln('City,Code,Type,Line,Station');
    // prefix 模式数据集 cityCode 为 null：首列写空，编码键即拼接值，
    // 重新解析后仅不参与查询（与原始语义一致）
    final cityCode = dataset.cityCode ?? '';
    for (final entry in dataset.codes.values) {
      buffer.writeln(
        [cityCode, entry.code, entry.type, entry.line, entry.station]
            .map(_csvField)
            .join(','),
      );
    }
  }
  buffer.writeln('# END datasets=${datasets.length}');
  return buffer.toString();
}

/// 解析文本快照为数据集列表。
///
/// 快照块首若带有原始 CSV 表头（`City,...` / `Prefix,...`，历史快照的
/// 写入格式），会先剥离再补一份标准表头后交给 [parseTripreaderDatasetCsv]；
/// 表头行若被当作数据行解析，城市代码会错成 "City"、编码表混入假条目
/// "Code"，导致重启后全部站点查询落空、编码计数缩水。
///
/// v2 格式（头部 datasets= 声明 + 尾部 `# END datasets=` 标记）严格校验：
/// 声明数、结束标记、实际数据集数三者必须一致，任一不符（写入中断/
/// 文件损坏）返回空列表，由调用方回退预制数据；v1 旧格式（无标记）
/// 按宽松模式尽力解析，保持向后兼容。
List<StationDataset> parseOnlineDatasets(String text) {
  final datasets = <StationDataset>[];
  String? file;
  String? cityName;
  String? province;
  String? system;
  String? kind;
  final csvLines = <String>[];
  var hasV2Header = false;
  int? declaredCount;
  int? endCount;

  void flush() {
    if (file != null && csvLines.isNotEmpty) {
      // 剥离块内残留的 CSV 表头行（历史快照在块首写入了表头，
      // 若被当作数据行会解析出城市代码 "City" 与假编码 "Code"）
      final rows = List<String>.of(csvLines);
      while (rows.isNotEmpty && _isCsvHeader(rows.first)) {
        rows.removeAt(0);
      }
      if (rows.isNotEmpty) {
        final csvText =
            'City,Code,Type,Line,Station\n${rows.join('\n')}\n';
        final dataset = parseTripreaderDatasetCsv(
          file: file!,
          csvText: csvText,
          cityName: _nullIfEmpty(cityName),
          province: _nullIfEmpty(province),
          system: _nullIfEmpty(system) ?? 'tu',
          kind: _nullIfEmpty(kind) ?? 'mixed',
        );
        if (dataset != null) datasets.add(dataset);
      }
    }
    csvLines.clear();
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      // v2 完整性标记（头部声明 / 尾部结束）
      if (line.contains('online station data v2')) {
        hasV2Header = true;
        declaredCount = _parseDatasetCount(line);
      } else if (line.startsWith('# END')) {
        endCount = _parseDatasetCount(line);
      }
      continue;
    }
    if (line.startsWith('@')) {
      flush();
      final parts = line.substring(1).split('|');
      file = parts.isNotEmpty ? parts[0].trim() : null;
      cityName = parts.length > 1 ? parts[1].trim() : '';
      province = parts.length > 2 ? parts[2].trim() : '';
      system = parts.length > 3 ? parts[3].trim() : '';
      kind = parts.length > 4 ? parts[4].trim() : '';
    } else if (file != null) {
      csvLines.add(raw);
    }
  }
  flush();

  // v2 严格模式：检测到 v2 头就必须通过完整性校验，否则视为损坏快照
  if (hasV2Header) {
    if (declaredCount == null ||
        endCount != declaredCount ||
        datasets.length != declaredCount) {
      return const [];
    }
  }
  return datasets;
}

/// 解析快照标记行中的 `datasets=<n>`（缺失或非法时返回 null）。
int? _parseDatasetCount(String line) {
  final match = RegExp(r'datasets=(\d+)').firstMatch(line);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// 判断快照块行是否为 CSV 表头行（首列为 City / Prefix，忽略大小写与引号）。
bool _isCsvHeader(String line) {
  final comma = line.indexOf(',');
  final first = (comma < 0 ? line : line.substring(0, comma))
      .replaceAll('"', '')
      .trim()
      .toUpperCase();
  return first == 'CITY' || first == 'PREFIX';
}

/// CSV 字段转义：含逗号/引号/换行时按 RFC 4180 风格加引号包裹。
String _csvField(String? value) {
  final text = value ?? '';
  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String? _nullIfEmpty(String? value) =>
    (value == null || value.isEmpty) ? null : value;