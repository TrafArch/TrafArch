import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/station_codes.dart';
import 'package:transit_card_analyzer/core/data/tripreader_sync.dart';

void main() {
  test('在线同步（无压缩归档）：解析 CSV 生成会话内存数据集', () async {
    await _expectSyncParses(deflate: false);
  });

  test('在线同步（deflate 压缩归档）：解析 CSV 生成会话内存数据集', () async {
    await _expectSyncParses(deflate: true);
  });

  test('全部通道被风控拦截（HTML 响应）时聚合失败原因', () async {
    final service = TripreaderSyncService(
      fetch: (uri) async => utf8.encode('<html>风控挑战页</html>'),
    );
    await expectLater(
      service.sync(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(
          contains('GitHub 主源'),
          isNot(contains('Gitee')),
        ),
      )),
    );
  });
}

Future<void> _expectSyncParses({required bool deflate}) async {
  final zip = _buildZip({
    'tripreader-data-master/Fujian/Fuzhou/README.md':
        '# 福州市 Fuzhou\n\n### 轨道交通\n识别方式：1E文件，线路和站点3-4位+7-8位\n',
    'tripreader-data-master/Fujian/Fuzhou/metro-tu.csv': 'City,Code,Type,Line,Station\n'
        '3910,02,地铁,2号线,\n'
        '3910,0231,地铁,2号线,苏洋\n',
    'tripreader-data-master/cardname-tu.csv': 'IIN,Issuer,Name\n',
  }, deflate: deflate);

  final service = TripreaderSyncService(fetch: (uri) async => zip);
  final result = await service.sync();

  // 结果仅存在于返回值（会话内存），不再写入任何存储
  expect(result.datasetCount, 1);
  expect(result.codeCount, 2);
  expect(result.sourceLabel, 'GitHub 主源');
  expect(result.report, contains('1 个数据集'));

  final dataset = result.datasets.single;
  expect(dataset.file, 'Fujian/Fuzhou/metro-tu.csv');
  expect(dataset.cityCode, '3910');
  expect(dataset.cityName, '福州市');
  expect(dataset.system, 'tu');
  expect(dataset.kind, 'metro');

  final table = StationCodeTable.fromDatasets(result.datasets);
  expect(table.lookup(code: '02', cityCode: '3910')?.line, '2号线');
  final entry = table.lookup(code: '0231', cityCode: '3910');
  expect(entry?.line, '2号线');
  expect(entry?.station, '苏洋');
}

/// 构造最小 ZIP 归档（仅测试用，无 CRC 校验需求）：
/// local file header + 数据 + central directory + EOCD。
List<int> _buildZip(Map<String, String> files, {required bool deflate}) {
  final local = <int>[];
  final central = <int>[];
  files.forEach((name, content) {
    final nameBytes = utf8.encode(name);
    final rawBytes = utf8.encode(content);
    final data =
        deflate ? const ZLibEncoder(raw: true).convert(rawBytes) : rawBytes;
    final method = deflate ? 8 : 0;
    final offset = local.length;

    local.addAll([
      0x50, 0x4B, 0x03, 0x04, // 签名
      20, 0, // 版本
      0, 0, // 标志
      method, 0, // 压缩方法
      0, 0, 0, 0, // 时间/日期
      0, 0, 0, 0, // CRC32（解析器不校验）
      ..._le32(data.length),
      ..._le32(rawBytes.length),
      ..._le16(nameBytes.length),
      0, 0, // 扩展字段长度
      ...nameBytes,
      ...data,
    ]);

    central.addAll([
      0x50, 0x4B, 0x01, 0x02, // 签名
      20, 0, // 版本（创建）
      20, 0, // 版本（需要）
      0, 0, // 标志
      method, 0, // 压缩方法
      0, 0, 0, 0, // 时间/日期
      0, 0, 0, 0, // CRC32
      ..._le32(data.length),
      ..._le32(rawBytes.length),
      ..._le16(nameBytes.length),
      0, 0, // 扩展字段长度
      0, 0, // 注释长度
      0, 0, // 磁盘号
      0, 0, // 内部属性
      0, 0, 0, 0, // 外部属性
      ..._le32(offset),
      ...nameBytes,
    ]);
  });

  return [
    ...local,
    ...central,
    0x50, 0x4B, 0x05, 0x06, // EOCD
    0, 0, // 磁盘号
    0, 0, // 中央目录起始磁盘
    ..._le16(files.length),
    ..._le16(files.length),
    ..._le32(central.length),
    ..._le32(local.length),
    0, 0, // 注释长度
  ];
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _le32(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];