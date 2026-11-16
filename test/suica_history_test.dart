import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

const _idm = [1, 2, 3, 4, 5, 6, 7, 8];

// Synthetic 2026-11-16 rail record. No personal card data is used.
List<int> _record({
  int terminal = 0x16,
  int process = 0x01,
  int balance = 1000,
  int sequence = 100,
  int day = 16,
  int region = 0,
  List<int> details = const [1, 2, 1, 3],
}) => [
  terminal,
  process,
  0,
  2,
  0x35,
  0x60 | day,
  ...details,
  balance & 0xFF,
  balance >> 8,
  0x7E,
  sequence >> 8,
  sequence & 0xFF,
  region,
];

List<int> _packet(List<int> payload) => [payload.length + 1, ...payload];

class _HistoryTag {
  _HistoryTag(this.records, {this.failFrom});

  final Map<int, List<int>> records;
  final int? failFrom;
  final List<int> requestedBlocks = [];

  Future<List<int>> transceive(List<int> frame) async {
    if (frame[1] == 0x02) {
      return _packet([0x03, ..._idm, 1, 0, 0]);
    }
    if (frame[1] != 0x06) throw StateError('Unexpected command');
    final countOffset = 11 + frame[10] * 2;
    final count = frame[countOffset];
    final indices = [
      for (var i = 0; i < count; i++) frame[countOffset + 2 + i * 2],
    ];
    requestedBlocks.addAll(indices);
    if (failFrom != null && indices.any((block) => block >= failFrom!)) {
      return _packet([0x07, ..._idm, 0x01, 0xA1]);
    }
    return _packet([
      0x07,
      ..._idm,
      0,
      0,
      count,
      for (final block in indices)
        ...(records[block] ?? List<int>.filled(16, 0)),
    ]);
  }

  Future<FelicaScanResult> read() => const SuicaAdapter().read(
    FelicaCardContext(
      idm: '0102030405060708',
      idmBytes: _idm,
      systemCodes: const [0x0003],
      protocol: FelicaProtocol(transceive),
    ),
  );
}

void main() {
  const parser = SuicaRecordParser();

  test(
    'initialized Suica history slots are blank without losing raw bytes',
    () {
      final bytes = FelicaHex.hexToBytes('00000080000000000000000000000000');
      final record = parser.parseBlock(blockNumber: 1, bytes: bytes);

      expect(record.isBlank, isTrue);
      expect(record.rawHex, '00000080000000000000000000000000');
      expect(record.raw, bytes);
      expect(record.decoded, isFalse);
      expect(record.amountYen, isNull);
      expect(record.suica, isNull);
      expect(parser.toTransactions([record]), isEmpty);
    },
  );

  test('nearby nonempty or incomplete Suica blocks remain visible', () {
    final initialized = FelicaHex.hexToBytes(
      '00000080000000000000000000000000',
    );
    final blocks = <List<int>>[
      for (var offset = 0; offset < 16; offset++)
        if (offset != 3) List<int>.of(initialized)..[offset] = 1,
      List<int>.of(initialized)..[3] = 0x81,
      initialized.sublist(0, 15),
      [...initialized, 0],
    ];
    for (final bytes in blocks) {
      final record = parser.parseBlock(blockNumber: 1, bytes: bytes);
      expect(record.isBlank, isFalse, reason: record.rawHex);
      expect(parser.toTransactions([record]), hasLength(1));
      expect(record.raw, bytes);
    }
  });

  test(
    'new-card history counts one issuance while preserving all twenty blocks',
    () async {
      final result = await _HistoryTag({
        0: FelicaHex.hexToBytes('12070000351600000000F40100000100'),
        for (var block = 1; block < 20; block += 2)
          block: FelicaHex.hexToBytes('00000080000000000000000000000000'),
      }).read();

      expect(result.transactions, hasLength(1));
      final transaction = result.transactions.single;
      expect(transaction.rawHex, '12070000351600000000F40100000100');
      expect(transaction.time, DateTime(2026, 8, 22));
      expect(transaction.amountMinorUnits, 500);
      expect(transaction.suica!.processCode, 7);
      expect(transaction.suica!.recordSequence, 1);
      expect(transaction.suica!.balanceChangeYen, isNull);
      expect(result.wallets.single.balanceMinorUnits, 500);
      expect(result.rawBlocks, hasLength(20));
      expect(
        result.rawBlocks.where(
          (block) =>
              FelicaHex.bytesToHex(block.bytes) ==
              '00000080000000000000000000000000',
        ),
        hasLength(10),
      );
      expect(
        result.rawBlocks.where(
          (block) =>
              FelicaHex.bytesToHex(block.bytes) ==
              '00000000000000000000000000000000',
        ),
        hasLength(9),
      );
      expect(
        result.statuses
            .singleWhere((status) => status.stage == 'Suica 历史记录')
            .message,
        '已读取块 0-19，有效记录 1 条',
      );
    },
  );

  test(
    'rail decodes separate areas, BE16 sequence and date-only precision',
    () {
      final transaction = parser
          .parseBlock(
            blockNumber: 7,
            bytes: _record(
              sequence: 0x1234,
              region: 0x90,
              details: [0x81, 0x11, 0x82, 0x12],
            ),
          )
          .toTransaction();
      final details = transaction.suica!;
      expect(details.recordSequence, 0x1234);
      expect(transaction.sequence, 7);
      expect(details.kind, SuicaRecordKind.rail);
      expect(details.entryStation!.areaCode, 3);
      expect(details.exitStation!.areaCode, 2);
      expect(details.entryStation!.lineCode, 0x81);
      expect(details.exitStation!.stationCode, 0x12);
      expect(details.hasTime, isFalse);
      expect(transaction.time, DateTime(2026, 11, 16));
      expect(transaction.walletKind, FelicaWalletKind.suicaJpy);
      expect(transaction.currency, 'JPY');
      expect(transaction.amountIsBalance, isTrue);
      expect(details.toJson()['recordSequence'], 0x1234);
    },
  );

  test('rail line below 0x80 forces area zero independently at each end', () {
    final details = parser
        .parseBlock(
          blockNumber: 0,
          bytes: _record(region: 0xF0, details: [0x01, 2, 0x80, 3]),
        )
        .toTransaction()
        .suica!;
    expect(details.entryStation!.areaCode, 0);
    expect(details.exitStation!.areaCode, 4);
  });

  test('shopping uses operation for time even at a non-vending terminal', () {
    final transaction = parser
        .parseBlock(
          blockNumber: 0,
          bytes: _record(
            terminal: 0x16,
            process: 0x46,
            details: [0x43, 0xC0, 1, 2],
          ),
        )
        .toTransaction();
    expect(transaction.suica!.kind, SuicaRecordKind.shopping);
    expect(transaction.suica!.hasTime, isTrue);
    expect(transaction.time, DateTime(2026, 11, 16, 8, 30));
    expect(transaction.suica!.entryStation, isNull);
    expect(transaction.suica!.exitStation, isNull);
  });

  test(
    'unknown vending operation does not invent time or railway endpoints',
    () {
      final transaction = parser
          .parseBlock(
            blockNumber: 0,
            bytes: _record(
              terminal: 0xC8,
              process: 0xFE,
              details: [0x43, 0xC0, 1, 2],
            ),
          )
          .toTransaction();
      expect(transaction.suica!.kind, SuicaRecordKind.unknown);
      expect(transaction.suica!.hasTime, isFalse);
      expect(transaction.suica!.entryStation, isNull);
      expect(transaction.suica!.exitStation, isNull);
      expect(transaction.suica!.processLabel, contains('0xFE'));
      expect(transaction.time, DateTime(2026, 11, 16));
    },
  );

  test('bus uses a BE16 operator code and does not decode it as rail', () {
    for (final input in [
      _record(process: 0x1B, details: [0x0C, 0x0D, 0x12, 0x34]),
      _record(terminal: 0x35, details: [0x0C, 0x0D, 0x12, 0x34]),
    ]) {
      final details = parser
          .parseBlock(blockNumber: 0, bytes: input)
          .toTransaction()
          .suica!;
      expect(details.kind, SuicaRecordKind.bus);
      expect(details.busOperatorCode, 0x0C0D);
      expect(details.entryStation, isNull);
      expect(details.exitStation, isNull);
    }
  });

  test('charge retains one location instead of fabricating a journey', () {
    final details = parser
        .parseBlock(blockNumber: 0, bytes: _record(process: 0x02))
        .toTransaction()
        .suica!;
    expect(details.kind, SuicaRecordKind.special);
    expect(details.entryStation!.stationCode, 2);
    expect(details.exitStation, isNull);
  });

  test('reserved station combinations preserve codes but suppress lookup', () {
    for (final fields in <List<int>>[
      [0, 0x12, 1, 3],
      [0x56, 0x40, 1, 3],
      [1, 0xF0, 1, 3],
    ]) {
      final details = parser
          .parseBlock(blockNumber: 0, bytes: _record(details: fields))
          .toTransaction()
          .suica!;
      expect(details.entryStation!.canLookup, isFalse);
      expect(details.entryStation!.lineCode, fields[0]);
      expect(details.entryStation!.stationCode, fields[1]);
      expect(details.exitStation!.canLookup, isTrue);
      expect(details.entryStation!.statusLabel, isNotEmpty);
    }
  });

  test('new card at simple gate suppresses station lookup', () {
    final details = parser
        .parseBlock(blockNumber: 0, bytes: _record(process: 7, terminal: 0x17))
        .toTransaction()
        .suica!;
    expect(details.entryStation!.canLookup, isFalse);
    expect(details.exitStation, isNull);
  });

  test(
    'possible bus charge never matches its operator bytes to a JR station',
    () {
      final details = parser
          .parseBlock(
            blockNumber: 0,
            bytes: _record(
              process: 2,
              region: 0xC0,
              details: [0x0C, 0x0D, 0, 0],
            ),
          )
          .toTransaction()
          .suica!;
      expect(details.kind, SuicaRecordKind.special);
      expect(details.entryStation!.lineCode, 0x0C);
      expect(details.entryStation!.stationCode, 0x0D);
      expect(details.entryStation!.canLookup, isFalse);
      expect(details.entryStation!.statusLabel, contains('公交'));
      expect(details.exitStation, isNull);
    },
  );

  test(
    'reused 0/1/6 station code before March 2020 keeps historical uncertainty',
    () {
      final oldRecord = _record(details: [1, 6, 1, 2]);
      // 2020-03-13, the day before the current code became applicable.
      oldRecord[4] = 0x28;
      oldRecord[5] = 0x6D;
      final oldDetails = parser
          .parseBlock(blockNumber: 0, bytes: oldRecord)
          .toTransaction()
          .suica!;
      expect(oldDetails.entryStation!.areaCode, 0);
      expect(oldDetails.entryStation!.lineCode, 1);
      expect(oldDetails.entryStation!.stationCode, 6);
      expect(oldDetails.entryStation!.canLookup, isFalse);
      expect(oldDetails.entryStation!.statusLabel, contains('历史'));
      expect(oldDetails.exitStation!.canLookup, isTrue);

      final newRecord = List<int>.of(oldRecord)..[5] = 0x6E;
      expect(
        parser
            .parseBlock(blockNumber: 0, bytes: newRecord)
            .toTransaction()
            .suica!
            .entryStation!
            .canLookup,
        isTrue,
      );
      final undated = List<int>.of(oldRecord)..[5] = 0;
      expect(
        parser
            .parseBlock(blockNumber: 0, bytes: undated)
            .toTransaction()
            .suica!
            .entryStation!
            .canLookup,
        isFalse,
      );
    },
  );

  test('invalid shopping time and invalid date remain distinguishable', () {
    final badTime = parser
        .parseBlock(
          blockNumber: 0,
          bytes: _record(process: 0x46, details: [0xFF, 0xFF, 0, 0]),
        )
        .toTransaction();
    expect(badTime.time, DateTime(2026, 11, 16));
    expect(badTime.suica!.hasTime, isFalse);
    expect(badTime.note, contains('时刻'));
    final badDate = parser
        .parseBlock(blockNumber: 0, bytes: _record(day: 31))
        .toTransaction();
    expect(badDate.time, isNull);
    expect(badDate.amountMinorUnits, 1000);
    expect(badDate.suica!.recordSequence, 100);
    expect(badDate.decoded, isFalse);
  });

  test('partial and raw-only blocks do not invent Suica metadata', () {
    expect(
      parser.parseBlock(blockNumber: 2, bytes: [1, 2, 3]).toTransaction().suica,
      isNull,
    );
    expect(
      const SuicaRecordParser(layout: SuicaRecordLayout.rawOnly)
          .parseBlock(blockNumber: 2, bytes: _record())
          .toTransaction()
          .suica,
      isNull,
    );
  });

  test(
    'Suica includes newest block once and never reads beyond block 19',
    () async {
      final tag = _HistoryTag({
        for (var block = 0; block < 20; block++)
          block: _record(sequence: 100 - block, balance: 1000 + block * 10),
      });
      final result = await tag.read();
      expect(
        result.transactions.map((record) => record.sequence),
        List<int>.generate(20, (index) => index),
      );
      expect(tag.requestedBlocks, List<int>.generate(20, (index) => index));
      expect(result.transactions.first.amountMinorUnits, 1000);
      expect(result.transactions.first.suica!.balanceChangeYen, -10);
      expect(result.transactions.last.suica!.balanceChangeYen, isNull);
      expect(result.wallets.single.balanceMinorUnits, 1000);
    },
  );

  test('Suica keeps newest history record when next read fails', () async {
    final newest = _record();
    final result = await _HistoryTag({0: newest}, failFrom: 1).read();
    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.sequence, 0);
    expect(result.transactions.single.rawHex, FelicaHex.bytesToHex(newest));
    expect(result.wallets.single.balanceMinorUnits, 1000);
    expect(result.state, FelicaReadState.partial);
    expect(result.transactions.single.suica!.balanceChangeYen, isNull);
  });

  test('balance difference keeps charges positive and never treats balance as fare', () async {
    final result = await _HistoryTag({
      0: _record(process: 2, sequence: 10, balance: 2000),
      1: _record(sequence: 9, balance: 1000),
    }).read();
    expect(result.transactions.first.amountMinorUnits, 2000);
    expect(result.transactions.first.amountIsBalance, isTrue);
    expect(result.transactions.first.suica!.balanceChangeYen, 1000);
    expect(result.transactions.last.suica!.balanceChangeYen, isNull);
  });

  test('balance difference rejects gaps, reversed dates, invalid fields and sequence wrap', () async {
    for (final records in <Map<int, List<int>>>[
      {0: _record(), 2: _record(sequence: 99, balance: 1200)},
      {0: _record(), 1: _record(sequence: 98, balance: 1200)},
      {0: _record(), 1: _record(sequence: 99, day: 17, balance: 1200)},
      {0: _record(), 1: _record(sequence: 99, day: 31, balance: 1200)},
      {0: _record(), 1: _record(sequence: 99, balance: 65535)},
      {0: _record(sequence: 0), 1: _record(sequence: 65535, balance: 1200)},
    ]) {
      final result = await _HistoryTag(records).read();
      expect(result.transactions.first.suica!.balanceChangeYen, isNull);
    }
  });
}
