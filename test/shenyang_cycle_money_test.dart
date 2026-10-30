import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// Exact 1E bodies from the complete 19:51 read in
// transit_card_log_20261030_195428.txt; no card identity is included.
// The same card also contains normal big-endian EC rail and EP bus records.
const _epRail = <(String, int, int)>[
  (
    '03221041310176116001000903A5000300000000000A0500002026102513241222101217221000000000000002BC0000',
    0,
    1290,
  ),
  (
    '04221041310176201101000A041F0003001C020000E80300002026101713264722101217221000000000000002BC0000',
    540,
    1000,
  ),
  (
    '032210413106297251010003014D00030000000000E80300002026101711465122101217221000000000000002BC0000',
    0,
    1000,
  ),
  (
    '03221041310183532001000A0415000300000000006E0500002026091917240322101217221000000000000002BC0000',
    0,
    1390,
  ),
  (
    '04221041310183531601000A0415000300B4000000220600002026091916181522101217221000000000000002BC0000',
    180,
    1570,
  ),
];

void main() {
  const parser = TUnionProcessParser();

  for (final (index, sample) in _epRail.indexed) {
    final (raw, amount, balance) = sample;
    test('沈阳已核实EP轨道记录${index + 1}按小端读取金额和记录余额', () {
      final trip = parser.parseCycleTrip(_hex(raw))!;
      expect(trip.amountFen, amount);
      expect(trip.balanceFen, balance);
      expect(trip.rawHex, raw);
    });
  }

  test('沈阳同卡EC轨道与EP公交仍读取大端金额和余额', () {
    const samples = <(String, int, int)>[
      (
        '1622104131060340140100010079000300000001C2000003482026102514014222101217221000000000000002BC0000',
        450,
        840,
      ),
      (
        '16000041310603400001000100790003000000021C000002E42026101719535522101217221000000000000002BC0000',
        540,
        740,
      ),
      (
        '0600004131012174870200030250000000000000B40000050020261017141825221012172210FFFFFFFF000000000000',
        180,
        1280,
      ),
    ];
    for (final (raw, amount, balance) in samples) {
      final trip = parser.parseCycleTrip(_hex(raw))!;
      expect(trip.amountFen, amount);
      expect(trip.balanceFen, balance);
      expect(trip.rawHex, raw);
    }
  });

  test('北京与杭州EP轨道实测记录保留大端金额和余额', () {
    // Existing real-log regression bodies; EP alone does not imply little endian.
    const samples = <(String, int, int)>[
      (
        '040000300089000344010800190030000000000258000042FE20260920131930100001011000FFFFFFFF000000000000',
        600,
        17150,
      ),
      (
        '030000300949000227015E0021004A000000000000000042FE20260920123400100001011000FFFFFFFF000000000000',
        0,
        17150,
      ),
      (
        '040000413106146227010001001500000000000000000005DC20261029180110331001663310FFFFFFFF000000000000',
        0,
        1500,
      ),
    ];
    for (final (raw, amount, balance) in samples) {
      final trip = parser.parseCycleTrip(_hex(raw))!;
      expect(trip.amountFen, amount);
      expect(trip.balanceFen, balance);
    }
  });

  test('合成边界：缺少独立受理城市终端机构及轨道EP证据时不切换字节序', () {
    // Explicitly synthetic mutations of the observed EP exit. These are
    // rejection cases, not claims about records actually written by a city.
    final original = _hex(_epRail[1].$1);
    final rejected = <List<int>>[
      [...original]..[0] = 0x02,
      [...original]..[9] = 0x02,
      [...original]..[1] = 0x00,
      [...original]..[3] = 0x30,
      [...original]..[0x20] = 0x10,
      [...original]..[0x22] = 0x01,
      [...original]..[0x29] = 0x01,
      original.sublist(0, 0x22),
    ];
    for (final raw in rejected) {
      final trip = parser.parseCycleTrip(raw)!;
      expect(trip.amountFen, 469893120);
      expect(trip.balanceFen, 3892510720);
    }
  });

  test('合成边界：已确认格式不根据金额大小选择字节序', () {
    final raw = _hex(_epRail[1].$1)
      ..setRange(0x11, 0x15, [0x00, 0x00, 0x01, 0x00])
      ..setRange(0x15, 0x19, [0x00, 0x00, 0x02, 0x00]);
    final trip = parser.parseCycleTrip(raw)!;
    expect(trip.amountFen, 65536);
    expect(trip.balanceFen, 131072);
  });

  test('70模板中的已核实沈阳EP轨道仍按小端读取且保留字段体原文', () {
    final raw = _hex(_epRail[1].$1);
    final trip = parser.parseCycleTrip([0x70, raw.length, ...raw])!;
    expect(trip.amountFen, 540);
    expect(trip.balanceFen, 1000);
    expect(trip.rawHex, _epRail[1].$1);
  });
}

List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
