import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/settings_store.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/state/app_state.dart';

/// 行程页展示链路测试：假 NFC 通道 + 假资产包 + 内存设置存储驱动完整管道
/// （scanOnce → TUnionParser → AnalysisEngine → TripsPage），
/// 验证终端解码 + 应用内预制站点数据（福州快照）查出的城市/线路/站点/类型
/// 真实渲染。
void main() {
  testWidgets('命中站点代码表：行程页展示城市/线路/站点/类型', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(record: _record(terminal: '391002003100'));
    await _scanAndPump(tester, channel);

    expect(find.text('福州市'), findsOneWidget);
    expect(find.text('2号线'), findsOneWidget);
    expect(find.text('苏洋'), findsOneWidget);
    expect(find.text('地铁'), findsOneWidget);
    expect(find.textContaining('未匹配终端解码规则'), findsNothing);
  });

  testWidgets('未匹配终端解码规则：行程页显示提示，无线 路/站点行', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(record: _record()); // 终端 123456789012 不匹配规则
    await _scanAndPump(tester, channel);

    expect(find.textContaining('未匹配终端解码规则'), findsOneWidget);
    expect(find.text('线路'), findsNothing);
    expect(find.text('站点'), findsNothing);
  });

  testWidgets('充值交易（0x02）：显示充值类型与 + 金额，不显示未匹配提示', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', rawType: 0x02),
      );
    await _scanAndPump(tester, channel);

    expect(find.text('充值 · 序号 1'), findsOneWidget);
    expect(find.text('+¥46.60'), findsOneWidget);
    expect(find.textContaining('未匹配终端解码规则'), findsNothing);
  });

  testWidgets('充值交易配对 0x1E 充值记录：补充交易后余额与行业', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', rawType: 0x02),
        cycleRecord: _cycleRecord(typeCode: 0x09), // EC 充值
      );
    await _scanAndPump(tester, channel);

    expect(find.text('充值 · 序号 1'), findsOneWidget);
    expect(find.text('¥53.40'), findsOneWidget); // 0x1E 交易后余额
    expect(find.text('城市轨道交通'), findsOneWidget);
  });

  testWidgets('站点编码未收录：线路命中名称、站点回退原始编码', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(record: _record(terminal: '391002999999'));
    await _scanAndPump(tester, channel);

    expect(find.text('2号线'), findsOneWidget); // "02" 单独命中线路条目
    expect(find.text('99'), findsOneWidget); // "0299"/"99" 未收录 → 回退原始编码
  });

  testWidgets('终端未命中：0x1E 出站记录按时间+金额配对补齐站点与分类/余额', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'), // 不匹配任何终端规则
        cycleRecord: _cycleRecord(), // 0x1E：2024-05-01 08:30 · 4660 分 · "0231"
      );
    await _scanAndPump(tester, channel);

    expect(find.text('福州市'), findsOneWidget);
    expect(find.text('2号线'), findsOneWidget);
    expect(find.text('苏洋'), findsOneWidget);
    expect(find.text('地铁'), findsOneWidget);
    expect(find.textContaining('未匹配终端解码规则'), findsNothing);
    // 0x1E 独有字段按配对补充：应用分类 + 交易后余额
    expect(find.text('城市轨道交通'), findsOneWidget);
    expect(find.text('¥53.40'), findsOneWidget);
  });

  testWidgets('0 元交易配对 0x1E 进站记录：显示进站时间与站点', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', amountFen: 0), // 进站 0 元
        cycleRecord: _cycleRecord(typeCode: 0x01, amountFen: 0), // EC 入站
      );
    await _scanAndPump(tester, channel);

    expect(find.text('进站时间'), findsOneWidget);
    expect(find.text('2024-05-01 08:30:00'), findsOneWidget);
    expect(find.text('站点'), findsOneWidget);
    expect(find.text('苏洋'), findsOneWidget);
    expect(find.text('2号线'), findsOneWidget);
    expect(find.text('时间'), findsNothing); // 时间行已改显进站时间
  });

  testWidgets('0 元交易未配对进站记录：保持时间行（不猜测）', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', amountFen: 0),
      );
    await _scanAndPump(tester, channel);

    expect(find.text('时间'), findsOneWidget);
    expect(find.text('进站时间'), findsNothing);
  });

  testWidgets('0 元交易配对 0x1E 出站记录：不误判为进站', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', amountFen: 0),
        cycleRecord: _cycleRecord(typeCode: 0x04, amountFen: 0), // EP 出站
      );
    await _scanAndPump(tester, channel);

    expect(find.text('时间'), findsOneWidget);
    expect(find.text('进站时间'), findsNothing);
    expect(find.text('苏洋'), findsOneWidget); // 出站配对补齐站点仍生效
  });

  testWidgets('0 元交易配对 0x1A 记录 1 进站：显示进站时间与站点', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', amountFen: 0), // 进站 0 元
        varRecord: _railRecord(entryTime: DateTime(2024, 5, 1, 8, 30)),
      );
    await _scanAndPump(tester, channel);

    // 行程卡按 0x1A 记录进站配对展示；0x1A 卡片进站时间同为 08:30:00
    expect(find.text('进站时间'), findsNWidgets(2));
    expect(find.text('2024-05-01 08:30:00'), findsNWidgets(2));
    // 行程卡补齐进站城市与站点原始编码（进闸站点）
    expect(find.text('城市'), findsOneWidget);
    expect(find.text('福州市'), findsOneWidget);
    expect(find.text('站点'), findsOneWidget);
    expect(find.text('0800190030000123'), findsOneWidget);
    expect(find.text('时间'), findsNothing); // 行程卡时间行已改显进站时间
  });

  testWidgets('0 元交易未配对上 0x1A 记录进站时间：保持时间行（不猜测）', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012', amountFen: 0),
        varRecord: _railRecord(), // 进站 2026-08-08 09:06:02，与交易不同分钟
      );
    await _scanAndPump(tester, channel);

    expect(find.text('时间'), findsOneWidget); // 行程卡保持时间行
    expect(find.text('进站时间'), findsOneWidget); // 仅 0x1A 卡片自身
    expect(find.text('站点'), findsNothing); // 未配对不补齐站点
    expect(find.text('福州市'), findsNothing); // 未配对不补齐城市
  });

  testWidgets('0x1A 记录 1：行程页加入城市轨道进出站卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'), // 不匹配终端规则
        varRecord: _railRecord(),
      );
    await _scanAndPump(tester, channel);

    expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('出闸'), findsOneWidget);
    expect(find.text('进站时间'), findsOneWidget);
    expect(find.text('2026-08-08 09:06:02'), findsOneWidget);
    expect(find.text('出站时间'), findsOneWidget);
    expect(find.text('2026-08-08 09:12:31'), findsOneWidget);
    expect(find.text('出闸城市'), findsOneWidget);
    expect(find.text('3501'), findsOneWidget); // 未收录回退原始代码
    expect(find.text('出闸站点'), findsOneWidget);
    expect(find.text('0800190030000456'), findsOneWidget);
    expect(find.text('进站钱包余额'), findsOneWidget);
    expect(find.text('¥25.00'), findsOneWidget);
    expect(find.text('出站钱包余额'), findsOneWidget);
    expect(find.text('¥22.00'), findsOneWidget); // 进站余额 25.00 − 出闸金额 3.00
    // 不再展示：进闸城市/进闸站点与标题右侧出闸金额
    expect(find.text('进闸城市'), findsNothing);
    expect(find.text('进闸站点'), findsNothing);
    expect(find.text('福州市'), findsNothing);
    expect(find.text('0800190030000123'), findsNothing);
    expect(find.text('-¥3.00'), findsNothing);
  });

  testWidgets('0x1A 记录 1 未写入：行程页不产出进出站卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varRecord: List.filled(85, 0x00), // 初始值（全 0）
      );
    await _scanAndPump(tester, channel);

    expect(find.text('城市轨道交通 · 进出站记录'), findsNothing);
    expect(find.textContaining('未匹配终端解码规则'), findsOneWidget);
  });

  testWidgets('0x1A 逐条读取不可用：行程页按整体数据前缀解析并展示', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varBlob: _railRecord(), // 整体读取兜底：85 字节裸字段体
      );
    await _scanAndPump(tester, channel);

    expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget);
    expect(find.text('2026-08-08 09:06:02'), findsOneWidget);
    expect(find.text('2026-08-08 09:12:31'), findsOneWidget);
    expect(find.text('¥25.00'), findsOneWidget);
    expect(find.text('¥22.00'), findsOneWidget);
  });

  testWidgets('0x1A 与 0x1E 同时出现（城市轨道交通）：以 0x1E 为准，不展示 0x1A', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varRecord: _railRecord(),
        cycleRecord: _cycleRecord(), // 0x1E：城市轨道交通行业
      );
    await _scanAndPump(tester, channel);

    // 0x1A 进出站卡片被抑制
    expect(find.text('城市轨道交通 · 进出站记录'), findsNothing);
    expect(find.text('¥25.00'), findsNothing); // 0x1A 进站钱包余额
    expect(find.text('¥22.00'), findsNothing); // 0x1A 出站钱包余额
    // 0x1E 主导的行程卡片照常展示
    expect(find.text('城市轨道交通'), findsOneWidget); // 行业
    expect(find.text('福州市'), findsOneWidget);
    expect(find.text('2024-05-01 08:30:00'), findsOneWidget);
    expect(find.text('¥53.40'), findsOneWidget); // 0x1E 交易后余额
  });

  testWidgets('0x1A 与 0x1E 同时出现（公共汽电车）：不抑制 0x1A 进出站卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varRecord: _railRecord(),
        cycleRecord: _cycleRecord(appTypeCode: 0x02), // 0x1E：公共汽电车行业
      );
    await _scanAndPump(tester, channel);

    expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget); // 0x1A 卡片保留
    expect(find.text('¥25.00'), findsOneWidget);
    expect(find.text('¥22.00'), findsOneWidget);
    expect(find.text('公共汽电车'), findsOneWidget); // 0x1E 行业仍在行程卡展示
    expect(find.text('¥53.40'), findsOneWidget);
  });

  testWidgets('0x1A 记录 2：行程页加入公共汽电车上下车卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'), // 不匹配终端规则
        busRecord: _busRecord(), // 记录 1 缺省为初始值
      );
    await _scanAndPump(tester, channel);

    expect(find.text('公共汽电车 · 上下车记录'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('未知(0x02)'), findsOneWidget); // 实测取值未收录，显式未知
    expect(find.text('上车时间'), findsOneWidget);
    expect(find.text('2026-08-08 09:06:02'), findsOneWidget);
    expect(find.text('下车时间'), findsOneWidget);
    expect(find.text('2026-08-08 09:12:31'), findsOneWidget);
    expect(find.text('下车城市'), findsOneWidget);
    expect(find.text('3501'), findsOneWidget); // 未收录回退原始代码
    expect(find.text('下车站点'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('方向'), findsOneWidget);
    expect(find.text('未知方向'), findsOneWidget);
    expect(find.text('交易金额'), findsOneWidget);
    expect(find.text('¥3.00'), findsOneWidget);
    expect(find.text('乘车里程'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // 记录 1 未写入（初始值）：不产出轨道进出站卡片
    expect(find.text('城市轨道交通 · 进出站记录'), findsNothing);
  });

  testWidgets('0x1A 记录 2 未写入：行程页不产出公共汽电车卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varRecord: _railRecord(),
        busRecord: List.filled(88, 0x00), // 记录 2 初始值（全 0）
      );
    await _scanAndPump(tester, channel);

    expect(find.text('公共汽电车 · 上下车记录'), findsNothing);
    expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget);
  });

  testWidgets('0x1A 记录 2 与 0x1E 同时出现（公共汽电车）：以 0x1E 为准，不展示 0x1A', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        busRecord: _busRecord(),
        cycleRecord: _cycleRecord(appTypeCode: 0x02), // 0x1E：公共汽电车行业
      );
    await _scanAndPump(tester, channel);

    // 0x1A 上下车卡片被抑制
    expect(find.text('公共汽电车 · 上下车记录'), findsNothing);
    expect(find.text('¥3.00'), findsNothing); // 0x1A 交易金额
    expect(find.text('2026-08-08 09:06:02'), findsNothing); // 0x1A 上车时间
    // 0x1E 主导的行程卡片照常展示
    expect(find.text('公共汽电车'), findsOneWidget); // 行业
    expect(find.text('¥53.40'), findsOneWidget); // 0x1E 交易后余额
  });

  testWidgets('0x1A 记录 2 与 0x1E 同时出现（城市轨道交通）：不抑制公交卡片', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        busRecord: _busRecord(),
        cycleRecord: _cycleRecord(), // 0x1E：城市轨道交通行业
      );
    await _scanAndPump(tester, channel);

    expect(find.text('公共汽电车 · 上下车记录'), findsOneWidget); // 行业不匹配不抑制
    expect(find.text('¥3.00'), findsOneWidget);
    expect(find.text('2026-08-08 09:12:31'), findsOneWidget);
    expect(find.text('城市轨道交通'), findsOneWidget); // 0x1E 行业仍在行程卡展示
    expect(find.text('¥53.40'), findsOneWidget);
  });

  testWidgets('0x1A 仅有整体数据：轨道按记录 1 前缀解析，公交记录 2 不猜测', (tester) async {
    final channel = _FakeNfcChannel()
      ..enqueueWalletScript(
        record: _record(terminal: '123456789012'),
        varBlob: [..._railRecord(), ..._busRecord()], // 裸记录体拼接 85 + 88 字节
      );
    await _scanAndPump(tester, channel);

    expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget); // 前缀按记录 1 解析
    expect(find.text('公共汽电车 · 上下车记录'), findsNothing); // 记录 2 起始位置不可定位
    expect(find.text('¥3.00'), findsNothing);
  });
}

/// 注入假通道、假资产包与内存设置存储，走一次完整扫描并渲染行程页。
/// 站点数据使用应用内预制快照（prebuilt_station_data.dart），无需外部注入。
Future<void> _scanAndPump(WidgetTester tester, _FakeNfcChannel channel) async {
  final app = AppState(
    channel: channel,
    bundle: _FakeBundle(_assets),
    settingsStore: MemorySettingsStore(),
  );
  await app.init();
  await app.scanOnce();
  await tester.pumpWidget(MaterialApp(home: TripsPage(app: app)));
  await tester.pump();
}

/// 最小知识库资产：卡前缀库条目（发卡机构代码 01283910 后 4 位即城市
/// 代码 3910 → 福州市）+ 指纹与终端规则。
final Map<String, String> _assets = {
  'assets/data/issuer_fingerprints.json': jsonEncode({
    'entries': [
      {
        'issuerId': '1122334455667788',
        'cityCode': '3910',
        'cityName': '福州市',
        'operator': '示例运营方',
        'cardFamily': '测试卡',
      }
    ]
  }),
  'assets/data/terminal_rules.json': jsonEncode({
    'rules': [
      {
        'id': 'test-fuzhou',
        'match': {'terminalPrefix': '3910'},
        'layout': {
          'cityCode': [0, 4],
          'lineCode': [4, 6],
          'stationCode': [8, 10],
        },
      }
    ]
  }),
  'assets/data/card_prefixes.json': jsonEncode({
    'entries': [
      {
        'prefix': '31050600',
        'issuer': '01283910',
        'cardName': '福路通·榕城通',
        'city': '福州市',
      }
    ]
  }),
};

/// 按 INS 脚本化的假 NFC 通道：队列耗尽后返回 6A82（记录未找到）。
class _FakeNfcChannel implements NfcChannel {
  final Map<int, List<List<int>>> _queues = {};

  void enqueue(int ins, List<int> response) =>
      _queues.putIfAbsent(ins, () => []).add(response);

  /// 电子钱包完整读取脚本：选择 MF → 选择钱包 AID → 读三个标准文件
  /// → GET BALANCE → 0x18 交易明细整体读取（与管道测试脚本一致）。
  /// 传入 [varRecord] 时 0x1A 逐条读取记录 1 命中；传入 [busRecord] 时
  /// 记录 2 追加命中（记录 1 缺省为未写入的初始值），随后以记录未找到终止；
  /// 传入 [varBlob] 时 0x1A 逐条读取失败、整体读取兜底返回该数据；
  /// 均未传入时 0x1A 逐条与整体兜底都以记录未找到终止。
  /// 传入 [cycleRecord] 时追加 0x1E 循环记录 1（整体读取命中）。
  void enqueueWalletScript({
    required List<int> record,
    List<int>? varRecord,
    List<int>? varBlob,
    List<int>? busRecord,
    List<int>? cycleRecord,
  }) {
    enqueue(0xA4, const [0x90, 0x00]);
    enqueue(0xA4, _sw9000(const []));
    enqueue(0xB0, _sw9000(_publicFile()));
    enqueue(0xB0, _sw9000(_holderFile()));
    enqueue(0xB0, _sw9000(_managementFile()));
    enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]); // 余额 10000 分
    enqueue(0xB2, _sw9000(record)); // 0x18 交易明细整体读取
    if (busRecord != null) {
      enqueue(0xB2, _sw9000(varRecord ?? List.filled(85, 0x00))); // 0x1A 记录 1
      enqueue(0xB2, _sw9000(busRecord)); // 0x1A 记录 2 命中
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 3：记录未找到
    } else if (varRecord != null) {
      enqueue(0xB2, _sw9000(varRecord)); // 0x1A 记录 1 命中
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 2：记录未找到
    } else if (varBlob != null) {
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 逐条读取：记录未找到
      enqueue(0xB2, _sw9000(varBlob)); // 0x1A 整体读取兜底命中
    } else {
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 逐条读取：记录未找到
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 整体读取兜底：同样终止
    }
    if (cycleRecord != null) {
      enqueue(0xB2, _sw9000(cycleRecord)); // 0x1E 循环记录 1（整体读取）
    }
  }

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
        uid: '04A1B2C3',
        technologies: const ['IsoDep'],
        isoDepConnected: true,
        timestamp: DateTime(2026, 10, 8),
      );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    final ins = apdu.length > 1 ? apdu[1] : -1;
    final queue = _queues[ins];
    if (queue == null || queue.isEmpty) return const [0x6A, 0x82];
    return queue.removeAt(0);
  }
}

/// 内存资产包：按 Key 返回预置 JSON 字符串。
class _FakeBundle extends CachingAssetBundle {
  final Map<String, String> _texts;
  _FakeBundle(this._texts);

  @override
  Future<ByteData> load(String key) async {
    final text = _texts[key];
    if (text == null) throw FlutterError('资产不存在：$key');
    return ByteData.view(Uint8List.fromList(utf8.encode(text)).buffer);
  }
}

List<int> _sw9000(List<int> data) => [...data, 0x90, 0x00];

List<int> _publicFile() {
  final b = List.filled(30, 0);
  for (var i = 0; i < 8; i++) {
    b[i] = 0x11 * (i + 1);
  }
  b[8] = 0x01;
  b[9] = 0x01;
  const serial = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x00];
  for (var i = 0; i < 10; i++) {
    b[10 + i] = serial[i];
  }
  b[20] = 0x20;
  b[21] = 0x24;
  b[22] = 0x01;
  b[23] = 0x01; // 20240101
  b[24] = 0x20;
  b[25] = 0x29;
  b[26] = 0x12;
  b[27] = 0x31; // 20291231
  b[28] = 0xAA;
  b[29] = 0xBB;
  return b;
}

List<int> _holderFile() {
  final b = List.filled(55, 0);
  b[0] = 0x01;
  b[54] = 0x01;
  return b;
}

List<int> _managementFile() {
  final b = List.filled(60, 0);
  b[6] = 0x39;
  b[7] = 0x10; // 城市代码 3910
  b[10] = 0x01;
  return b;
}

/// 23 字节交易明细记录（SFI 0x18），终端号为 6 字节 BCD。
List<int> _record({
  int seq = 1,
  int amountFen = 4660,
  int day = 1,
  String terminal = '123456789012',
  int rawType = 0x06,
}) =>
    [
      (seq >> 8) & 0xFF,
      seq & 0xFF,
      0,
      0,
      0,
      (amountFen >> 24) & 0xFF,
      (amountFen >> 16) & 0xFF,
      (amountFen >> 8) & 0xFF,
      amountFen & 0xFF,
      rawType,
      ..._bcd(terminal),
      0x20,
      0x24,
      0x05,
      day, // 2024050d
      0x08,
      0x30,
      0x00, // 08:30:00
    ];

List<int> _bcd(String digits) => [
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];

/// 7 字节 BCD 时间戳（YYYYMMDDhhmmss，如 0x20 0x26 … 即 2026 年）。
List<int> _bcdTime(DateTime t) => [
      0x20,
      _bcd2(t.year % 100),
      _bcd2(t.month),
      _bcd2(t.day),
      _bcd2(t.hour),
      _bcd2(t.minute),
      _bcd2(t.second),
    ];

int _bcd2(int v) => ((v ~/ 10) << 4) | (v % 10);

/// 0x1A 记录 1（城市轨道应用信息记录，85 字节裸字段体）：
/// 出闸 · 进闸城市 3910（福州市）· 出闸城市 3501（未收录）·
/// 2026-08-08 09:06:02 进站 / 09:12:31 出站 ·
/// 进站钱包余额 2500 分 · 出闸交易金额 300 分。
/// 传入 [entryTime] 时覆盖 [35-3B] 进站时间（0 元交易进站配对测试用）。
List<int> _railRecord({DateTime? entryTime}) => [
      0x02, // [00] 交易状态：出闸
      0x39, 0x10, // [01-02] 进闸城市代码 3910
      0x35, 0x01, // [03-04] 出闸城市代码 3501
      ...List.filled(7, 0), 0x10, // [05-0C] 进闸机构标识
      ...List.filled(7, 0), 0x08, // [0D-14] 出闸机构标识
      0x08, 0x00, 0x19, 0x00, 0x30, 0x00, 0x01, 0x23, // [15-1C] 进闸站点
      0x08, 0x00, 0x19, 0x00, 0x30, 0x00, 0x04, 0x56, // [1D-24] 出闸站点
      ...List.filled(7, 0), 0x0A, // [25-2C] 进闸终端编号
      ...List.filled(7, 0), 0x0B, // [2D-34] 出闸终端编号
      ..._bcdTime(entryTime ?? DateTime(2026, 8, 8, 9, 6, 2)), // [35-3B] 进站时间
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // [3C-42] 出站时间
      0x00, 0x00, 0x01, 0x2C, // [43-46] 标注金额 300 分
      0x02, // [47] 入站线路号
      0x02, // [48] 出站线路号
      0x00, 0x00, 0x00, 0x00, // [49-4C] 进站交易金额
      0x00, 0x00, 0x01, 0x2C, // [4D-50] 进站钱包余额 2500 分
      0x00, 0x00, 0x01, 0x2C, // [51-54] 出闸交易金额 300 分
    ];

/// 0x1A 记录 2（公共汽电车应用信息记录，88 字节裸记录体）：
/// 交易状态 0x02（未收录，显式未知）· 上车城市 3910 · 下车城市 3501（未收录）·
/// 2026-08-08 09:06:02 上车 / 09:12:31 下车 · 交易金额 300 分 · 乘车里程 5。
List<int> _busRecord() => [
      0x02, // [00] 交易状态
      0x39, 0x10, // [01-02] 上车城市代码 3910
      ...List.filled(7, 0), 0x10, // [03-0A] 上车机构标识
      0x00, 0x01, // [0B-0C] 上车运营商代码
      0x00, 0x08, // [0D-0E] 上车线路号
      0x02, // [0F] 上车站点
      ...List.filled(7, 0), 0x23, // [10-17] 上车车辆号
      ...List.filled(6, 0), 0x1A, 0x5A, // [18-1F] 上车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x06, 0x02, // [20-26] 上车时间
      0x00, 0x00, 0x01, 0x2C, // [27-2A] 标注金额 300 分
      0x00, // [2B] 方向标识
      0x35, 0x01, // [2C-2D] 下车城市代码 3501
      ...List.filled(7, 0), 0x08, // [2E-35] 下车机构标识
      0x00, 0x01, // [36-37] 下车运营商代码
      0x00, 0x08, // [38-39] 下车线路号
      0x03, // [3A] 下车站点
      ...List.filled(7, 0), 0x36, // [3B-42] 下车车辆号
      ...List.filled(6, 0), 0x15, 0x68, // [43-4A] 下车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // [4B-51] 下车时间
      0x00, 0x00, 0x01, 0x2C, // [52-55] 交易金额 300 分
      0x00, 0x05, // [56-57] 乘车里程 5
    ];

/// 0x1E 循环记录（48 字节）：出站 · 2024-05-01 08:30:00 · 4660 分 ·
/// 应用分类码 [appTypeCode]（默认 0x01 城市轨道交通）。线路站点字段
/// "90020031000000" 按福州布局解析（第 3-4 位线路 "02" + 第 7-8 位站点
/// "31" → 编码 "0231" 查表得 2号线 · 苏洋）；城市代码 3910。
List<int> _cycleRecord({
  int typeCode = 0x04,
  int amountFen = 4660,
  int day = 1,
  int appTypeCode = 0x01,
}) {
  const balanceFen = 5340;
  return [
    typeCode, // [00] 交易类型：出站
    ..._bcd('0000300089000340'), // [01-08] 终端编号
    appTypeCode, // [09] 应用分类码（0x01 城市轨道交通 / 0x02 公共汽电车）
    ..._bcd('90020031000000'), // [0A-10] 线路和站点代码
    (amountFen >> 24) & 0xFF,
    (amountFen >> 16) & 0xFF,
    (amountFen >> 8) & 0xFF,
    amountFen & 0xFF, // [11-14] 交易金额（分）
    (balanceFen >> 24) & 0xFF,
    (balanceFen >> 16) & 0xFF,
    (balanceFen >> 8) & 0xFF,
    balanceFen & 0xFF, // [15-18] 交易后余额
    0x20, 0x24, 0x05, day, 0x08, 0x30, 0x00, // [19-1F] 交易时间
    ..._bcd('3910'), // [20-21] 城市代码
    ..._bcd('0000000000000000'), // [22-29] 收单机构
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // [2A-2F] 保留
  ];
}
