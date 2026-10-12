import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/online_data_store.dart';
import 'package:transit_card_analyzer/core/data/station_codes.dart';

void main() {
  const datasets = [
    StationDataset(
      file: 'Fujian/Fuzhou/metro-tu.csv',
      cityCode: '3910',
      cityName: '福州市',
      province: '福建省',
      system: 'tu',
      kind: 'metro',
      codes: {
        '02': StationCodeEntry(code: '02', type: '地铁', line: '2号线'),
        '0231': StationCodeEntry(
            code: '0231', type: '地铁', line: '2号线', station: '苏洋'),
        '0232': StationCodeEntry(
            code: '0232', type: '地铁', line: '2号线', station: '含,逗号站'),
      },
    ),
    StationDataset(
      file: 'Shanghai/metro-tu.csv',
      cityCode: '2900',
      system: 'tu',
      kind: 'metro',
      codes: {
        '0001': StationCodeEntry(code: '0001', type: '地铁', line: '1号线'),
      },
    ),
  ];

  test('文本快照序列化/解析往返：字段、编码与引号转义完整保留', () {
    final text = serializeOnlineDatasets(datasets);
    expect(text.startsWith('#'), isTrue);
    expect(text, contains('online station data v2'));
    expect(text, contains('datasets=2'));
    expect(text, contains('# END datasets=2'));
    final parsed = parseOnlineDatasets(text);
    expect(parsed, hasLength(2));

    final fuzhou = parsed.first;
    expect(fuzhou.file, 'Fujian/Fuzhou/metro-tu.csv');
    expect(fuzhou.cityCode, '3910');
    expect(fuzhou.cityName, '福州市');
    expect(fuzhou.province, '福建省');
    expect(fuzhou.system, 'tu');
    expect(fuzhou.kind, 'metro');
    expect(fuzhou.codes.keys.toSet(), {'02', '0231', '0232'});
    expect(fuzhou.codes['02']?.line, '2号线');
    expect(fuzhou.codes['0231']?.station, '苏洋');
    expect(fuzhou.codes['0232']?.station, '含,逗号站');

    final shanghai = parsed.last;
    expect(shanghai.cityCode, '2900');
    expect(shanghai.cityName, isNull);
    expect(shanghai.codes['0001']?.line, '1号线');
  });

  test('v2 快照完整性校验：截断或计数不符时整体拒绝（回退预制）', () {
    final text = serializeOnlineDatasets(datasets);

    // 写入中断：尾部结束标记缺失
    final truncated = text.substring(0, text.lastIndexOf('# END'));
    expect(parseOnlineDatasets(truncated), isEmpty);

    // 文件损坏：尾部计数与头部声明不符
    final tampered = text.replaceFirst('# END datasets=2', '# END datasets=5');
    expect(parseOnlineDatasets(tampered), isEmpty);

    // 完整快照不受影响
    expect(parseOnlineDatasets(text), hasLength(2));
  });

  test('v1 旧快照（无完整性标记）按宽松模式兼容解析', () {
    const legacy = '# transit_card_analyzer online station data v1\n'
        '@Shanghai/metro-tu.csv|||tu|metro\n'
        'City,Code,Type,Line,Station\n'
        '2900,0001,地铁,1号线,\n';
    final parsed = parseOnlineDatasets(legacy);
    expect(parsed, hasLength(1));
    expect(parsed.single.cityCode, '2900');
    expect(parsed.single.codes['0001']?.line, '1号线');
  });

  test('回归：块内残留表头行不得解析为数据（重启后查询全部落空）', () {
    // 历史快照在块首写入了 CSV 表头；若解析时未剥离，表头行会被当作
    // 数据行：城市代码错成 "City"、编码表混入 "Code" 假条目，
    // 重启后所有查询（如 3910|0231）落空、编码计数缩水
    const text = '# transit_card_analyzer online station data v2 datasets=1\n'
        '@Fujian/Fuzhou/metro-tu.csv|福州市|福建省|tu|metro\n'
        'City,Code,Type,Line,Station\n'
        '3910,0231,地铁,2号线,苏洋\n'
        '# END datasets=1\n';
    final parsed = parseOnlineDatasets(text);
    expect(parsed, hasLength(1));
    expect(parsed.single.cityCode, '3910');
    expect(parsed.single.codes.containsKey('Code'), isFalse);

    final table = StationCodeTable.fromDatasets(parsed);
    expect(table.lookup(code: '0231', cityCode: '3910')?.station, '苏洋');

    // prefix 模式数据集（块首为 Prefix 表头）同样需剥离，编码键保持拼接值
    const prefixText =
        '# transit_card_analyzer online station data v2 datasets=1\n'
        '@Zhejiang/Hangzhou/union-tu.csv|杭州市|浙江省|tu|union\n'
        'Prefix,Code,Type,Line,Station\n'
        ',35390020,地铁,1号线,某站\n'
        '# END datasets=1\n';
    final prefixParsed = parseOnlineDatasets(prefixText);
    expect(prefixParsed, hasLength(1));
    expect(prefixParsed.single.codes.containsKey('35390020'), isTrue);
  });

  test('解析结果构建查询表：取代预制后仍可按城市+编码查询', () {
    final table = StationCodeTable.fromDatasets(
        parseOnlineDatasets(serializeOnlineDatasets(datasets)));
    expect(table.lookup(code: '0231', cityCode: '3910')?.station, '苏洋');
    expect(table.lookup(code: '0231', cityCode: '1000'), isNull);
  });

  test('MemoryOnlineDataStore：保存、加载与清除', () async {
    final store = MemoryOnlineDataStore();
    expect(await store.load(), isEmpty);

    await store.save(datasets);
    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded.first.codes['0231']?.station, '苏洋');

    await store.clear();
    expect(await store.load(), isEmpty);
  });
}