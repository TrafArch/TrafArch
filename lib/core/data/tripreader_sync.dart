import 'dart:convert';
import 'dart:io';

import 'station_codes.dart';

/// 读卡识途（Trip Reader）公开数据——应用内在线同步。
///
/// 在手机端直接联网拉取数据（归档 ZIP 解压），解析 CSV 生成
/// 站点数据集，结果由上层（AppState + online_data_store.dart）持久化到
/// 本地并取代应用内预制快照，重启后继续生效，直至再次更新或关闭开关清除。
///
/// 数据通道（按顺序尝试，任一成功即返回）：
/// - GitHub 主源归档 ZIP：https://github.com/domosekai/tripreader-data
///   （CC BY 4.0），master / main 双分支候选。
///
/// 本服务仅在用户开启「在线拉取数据」开关并点击“在线更新”后调用。

/// 数据归档下载器（可注入，测试用）。
typedef TripreaderFetcher = Future<List<int>> Function(Uri uri);

/// 在线同步结果摘要。
class TripreaderSyncResult {
  /// 本次拉取解析出的站点数据集（由上层持久化保存）。
  final List<StationDataset> datasets;

  /// 全部数据集的可查询编码总数。
  final int codeCount;

  /// 成功数据源标签（如 "GitHub 主源"）。
  final String sourceLabel;

  /// 成功摘要（供界面展示）。
  final String report;

  const TripreaderSyncResult({
    required this.datasets,
    required this.codeCount,
    required this.sourceLabel,
    required this.report,
  });

  /// 数据集数量。
  int get datasetCount => datasets.length;
}

/// 在线同步服务：多通道拉取 → 解压/聚合 → CSV 解析为站点数据集。
class TripreaderSyncService {
  TripreaderSyncService({TripreaderFetcher? fetch})
      : _fetch = fetch ?? _httpFetch;

  final TripreaderFetcher _fetch;

  /// 归档 ZIP 通道（同一仓库 master / main 双分支候选）。
  static const _archiveSources = <_ArchiveSource>[
    _ArchiveSource('GitHub 主源',
        'https://github.com/domosekai/tripreader-data/archive/refs/heads/master.zip'),
    _ArchiveSource('GitHub 主源',
        'https://github.com/domosekai/tripreader-data/archive/refs/heads/main.zip'),
  ];

  /// 拉取并解析数据；任一通道成功即返回（由调用方持久化保存）。
  /// 全部失败抛出 [StateError]，聚合每个通道的失败原因便于排查。
  Future<TripreaderSyncResult> sync() async {
    final failures = <String>[];

    // 归档 ZIP 通道
    for (final source in _archiveSources) {
      try {
        final bytes = await _fetch(Uri.parse(source.url))
            .timeout(const Duration(seconds: 120));
        final files = _unpackArchive(bytes);
        return _buildResult(files, source.label);
      } catch (e) {
        failures.add('${source.label}：$e');
      }
    }

    throw StateError('全部数据源拉取失败：\n${failures.join('\n')}');
  }

  /// 数据集与编码统计（无有效数据集视为该通道失败）。
  TripreaderSyncResult _buildResult(Map<String, String> files, String label) {
    final datasets = _buildDatasets(files);
    if (datasets.isEmpty) {
      throw const FormatException('数据内未解析到任何数据集');
    }
    var codeCount = 0;
    for (final dataset in datasets) {
      codeCount += dataset.codes.length;
    }
    return TripreaderSyncResult(
      datasets: datasets,
      codeCount: codeCount,
      sourceLabel: label,
      report: '站点数据已更新：${datasets.length} 个数据集 / '
          '$codeCount 个编码（来源：$label）',
    );
  }

  /// 校验响应为 ZIP 归档（过滤风控页/错误页，快速切换下一通道）。
  Map<String, String> _unpackArchive(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException('响应不是 ZIP 数据（可能被风控拦截或返回了网页）');
    }
    return _unpackZip(bytes);
  }
}

class _ArchiveSource {
  final String label;
  final String url;
  const _ArchiveSource(this.label, this.url);
}

/// 默认下载器：HttpClient 直连（跟随重定向）；连接 / 响应头 / 数据间隔
/// 三级超时，避免网络挂死时请求无限等待。
Future<List<int>> _httpFetch(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 '
          'TransitCardAnalyzer/1.0',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    const maxBytes = 64 * 1024 * 1024;
    final builder = BytesBuilder(copy: false);
    // 数据间隔超时：响应中途挂死（长时间无数据到达）时尽快失败切换
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw HttpException('响应超过大小上限（64 MB）', uri: uri);
      }
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

/// 解析 ZIP 归档：仅解压 CSV 与 README.md（文本），
/// 键为剥离根目录后的相对路径（如 Fujian/Fuzhou/metro-tu.csv）。
Map<String, String> _unpackZip(List<int> bytes) {
  if (bytes.length < 22) {
    throw const FormatException('ZIP 数据不完整');
  }
  var eocd = -1;
  final floor = bytes.length - 22 - 0xFFFF;
  for (var i = bytes.length - 22; i >= 0 && i >= floor; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    throw const FormatException('ZIP 结构识别失败（未找到中央目录）');
  }

  final count = _u16(bytes, eocd + 10);
  var pos = _u32(bytes, eocd + 16);
  final out = <String, String>{};
  for (var i = 0; i < count; i++) {
    if (_u32(bytes, pos) != 0x02014B50) {
      throw const FormatException('ZIP 中央目录损坏');
    }
    final method = _u16(bytes, pos + 10);
    final compSize = _u32(bytes, pos + 20);
    final nameLen = _u16(bytes, pos + 28);
    final extraLen = _u16(bytes, pos + 30);
    final commentLen = _u16(bytes, pos + 32);
    final localOffset = _u32(bytes, pos + 42);
    final name = utf8.decode(
      bytes.sublist(pos + 46, pos + 46 + nameLen),
      allowMalformed: true,
    );
    pos += 46 + nameLen + extraLen + commentLen;

    if (name.isEmpty || name.endsWith('/')) continue;
    if (compSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF) {
      throw const FormatException('暂不支持 ZIP64 归档');
    }
    final rel = _stripRootDir(name);
    final lower = rel.toLowerCase();
    if (!lower.endsWith('.csv') && !lower.endsWith('readme.md')) continue;
    out[rel] = _readZipEntry(bytes, localOffset, method, compSize);
  }
  return out;
}

/// 剥离归档根目录（如 tripreader-data-master/）得到相对路径。
String _stripRootDir(String name) {
  final slash = name.indexOf('/');
  return slash < 0 ? name : name.substring(slash + 1);
}

String _readZipEntry(List<int> all, int localOffset, int method, int compSize) {
  if (_u32(all, localOffset) != 0x04034B50) {
    throw const FormatException('ZIP 本地文件头损坏');
  }
  final nameLen = _u16(all, localOffset + 26);
  final extraLen = _u16(all, localOffset + 28);
  final start = localOffset + 30 + nameLen + extraLen;
  final end = start + compSize;
  if (end > all.length) {
    throw const FormatException('ZIP 条目数据越界');
  }
  final compressed = all.sublist(start, end);
  final List<int> raw = switch (method) {
    0 => compressed,
    8 => ZLibDecoder(raw: true).convert(compressed),
    _ => throw FormatException('不支持的 ZIP 压缩方法：$method'),
  };
  return utf8.decode(raw, allowMalformed: true);
}

int _u16(List<int> b, int off) => b[off] | (b[off + 1] << 8);

int _u32(List<int> b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

/// 省份目录名 → 中文省份名。
const _provinceNames = <String, String>{
  'Beijing': '北京市',
  'Tianjin': '天津市',
  'Shanghai': '上海市',
  'Chongqing': '重庆市',
  'Anhui': '安徽省',
  'Fujian': '福建省',
  'Gansu': '甘肃省',
  'Guangdong': '广东省',
  'Guizhou': '贵州省',
  'Heilongjiang': '黑龙江省',
  'Henan': '河南省',
  'Hunan': '湖南省',
  'Jiangsu': '江苏省',
  'Jiangxi': '江西省',
  'Liaoning': '辽宁省',
  'Shaanxi': '陕西省',
  'Shandong': '山东省',
  'Shanxi': '山西省',
  'Xinjiang': '新疆维吾尔自治区',
  'Yunnan': '云南省',
  'Zhejiang': '浙江省',
};

/// CSV 文件群 → 站点数据集列表（逐文件解析，无有效编码行的跳过）。
List<StationDataset> _buildDatasets(Map<String, String> files) {
  final csvPaths = files.keys
      .where((p) => p.toLowerCase().endsWith('.csv') && p.contains('/'))
      .toList()
    ..sort();

  final datasets = <StationDataset>[];
  final cityInfoCache = <String, Map<String, Object?>>{};

  for (final rel in csvPaths) {
    final parts = rel.split('/');
    final parsed = _parseDataFileName(parts.last);
    final cityRel = parts.sublist(0, parts.length - 1).join('/');
    final info = cityInfoCache.putIfAbsent(
      cityRel,
      () => _readCityInfo(files, cityRel, parts),
    );

    final dataset = parseTripreaderDatasetCsv(
      file: rel,
      csvText: files[rel]!,
      cityName: info['name'] as String?,
      province: info['province'] as String?,
      system: parsed.system,
      kind: parsed.kind,
    );
    if (dataset != null) datasets.add(dataset);
  }
  return datasets;
}

/// 解析数据文件名：system（tu/cu/yct）与类别（metro/brt/bus/…）。
/// 例：metro-tu.csv → tu / metro；cu.csv → cu / mixed。
({String system, String kind}) _parseDataFileName(String fileName) {
  var base = fileName;
  if (base.toLowerCase().endsWith('.csv')) {
    base = base.substring(0, base.length - 4);
  }
  final parts = base.split('-');
  var system = 'tu';
  if (parts.isNotEmpty) {
    final last = parts.last.toLowerCase();
    if (last == 'tu' || last == 'cu' || last == 'yct') {
      system = last;
      parts.removeLast();
    }
  }
  parts.remove('1e'); // 1e 变体标记不作为类别名
  return (system: system, kind: parts.isEmpty ? 'mixed' : parts.join('-'));
}

/// 读取城市目录 README：中文城市名（缺失时回退目录名）+ 省份。
Map<String, Object?> _readCityInfo(
  Map<String, String> files,
  String cityRel,
  List<String> parts,
) {
  final dirName = parts[parts.length - 2];
  String? name;
  final readme = files['$cityRel/README.md'];
  if (readme != null) {
    final cjk = RegExp(r'[\u4e00-\u9fff]{2,}');
    for (final rawLine in readme.split('\n')) {
      final line = rawLine.trim();
      if (name == null && line.startsWith('# ')) {
        name = cjk.firstMatch(line)?.group(0);
      }
    }
  }
  return <String, Object?>{
    'name': name ?? dirName,
    'province': _provinceNames[parts.first],
  };
}
