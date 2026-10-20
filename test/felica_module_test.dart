import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/felica/felica.dart';

const _idm = [0x01, 0x2E, 0x3A, 0x4B, 0x5C, 0x6D, 0x7E, 0x8F];
const _pmm = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08];

List<int> _packet(List<int> payload) => [payload.length + 1, ...payload];

List<int> _suicaBalanceBlock({int balance = 1000}) {
  final block = List<int>.filled(16, 0);
  block[0] = 0x12; // 端末種：券売機
  block[1] = 0x07; // 処理：新規
  block[10] = balance & 0xFF;
  block[11] = (balance >> 8) & 0xFF;
  return block;
}

List<int> _suicaRecord({int balance = 1000}) {
  final record = List<int>.filled(16, 0);
  record[0] = 0x03;              // 端末種：清算機
  record[1] = 0x01;              // 処理：運賃支払
  record[4] = 0x7B;              // 日付：2025-10-20 打包（7 位年 | 4 位月 | 5 位日）
  record[5] = 0x54;
  record[10] = balance & 0xFF;   // 交易后残高
  record[11] = (balance >> 8) & 0xFF;
  return record;
}

class _ScriptedTag {
  _ScriptedTag({
    this.balanceBlock,
    this.historyBlock1,
    this.respond = true,
    this.serviceAvailable = true,
  });

  final List<int>? balanceBlock;
  final List<int>? historyBlock1;
  final bool respond;
  final bool serviceAvailable;

  Future<List<int>> transceive(List<int> frame) async {
    if (!respond || frame.length < 2) return const [];
    switch (frame[1] & 0xFF) {
      case 0x00:
        return _packet([0x01, ..._idm, ..._pmm]);
      case 0x0C:
        return _packet([0x0D, ..._idm, 0x01, 0x00, 0x03]);
      case 0x02:
        return _packet([
          0x03,
          ..._idm,
          serviceAvailable ? 0x01 : 0x00,
          if (serviceAvailable) ...[0x00, 0x00],
        ]);
      case 0x06:
        return _read(frame);
      default:
        return const [];
    }
  }

  List<int> _read(List<int> frame) {
    final serviceCount = frame[10] & 0xFF;
    var index = 11 + serviceCount * 2;
    final blockCount = frame[index++] & 0xFF;
    final blocks = <List<int>>[];
    for (var i = 0; i < blockCount; i++) {
      final element = ((frame[index] & 0xFF) << 8) | (frame[index + 1] & 0xFF);
      index += 2;
      final blockNumber = element & 0x0FFF;
      if (blockNumber == 0) {
        blocks.add(balanceBlock ??
            [0xE8, 0x03, ...List<int>.filled(14, 0)]);
      } else if (blockNumber == 1 && historyBlock1 != null) {
        blocks.add(historyBlock1!);
      } else {
        blocks.add(List<int>.filled(16, 0));
      }
    }
    return _packet([
      0x07,
      ..._idm,
      0x00,
      0x00,
      blocks.length,
      for (final block in blocks) ...block,
    ]);
  }
}

Future<FelicaCardAdapter> _select(
  List<int> systemCodes, {
  FelicaProtocol? protocol,
}) {
  final context = FelicaCardContext(
    idm: '012E3A4B5C6D7E8F',
    idmBytes: _idm,
    systemCodes: systemCodes,
    protocol: protocol ?? FelicaProtocol((_) async => const []),
  );
  return CardAdapterRegistry.defaults().select(context);
}

FelicaProtocol _suicaServiceProtocol() => FelicaProtocol((frame) async {
      if (frame.length < 2 || (frame[1] & 0xFF) != 0x02) {
        return const [];
      }
      return _packet([0x03, ..._idm, 0x01, 0x00, 0x00]);
    });

void main() {
  test('Polling 帧：LEN 为整帧长度、系统码通配', () {
    expect(FelicaCommand.polling(), [0x06, 0x00, 0xFF, 0xFF, 0x00, 0x00]);
  });

  test('RWE 帧：服务码小端、块元素 0x80|块号（大端）', () {
    final frame = FelicaCommand.readWithoutEncryption(
      idm: _idm,
      serviceCodes: const [0x090F],
      blockListElements: [FelicaCommand.blockListElement(0, 1)],
    );
    expect(frame[0], frame.length);
    expect(frame[1], 0x06);
    expect(frame.sublist(2, 10), _idm);
    expect(frame[10], 1);
    expect(frame.sublist(11, 13), [0x0F, 0x09]);
    expect(frame[13], 1);
    expect(frame.sublist(14), [0x80, 0x01]);
  });

  test('响应长度不符抛 FormatException', () {
    expect(
      () => FelicaResponse.parse([0x05, 0x07, ..._idm]),
      throwsFormatException,
    );
  });

  test('RWE 成功响应解析', () async {
    final block = List<int>.generate(16, (i) => i);
    final protocol = FelicaProtocol(
      (_) async => _packet([0x07, ..._idm, 0x00, 0x00, 0x01, ...block]),
    );
    final result = await protocol.readWithoutEncryption(
      idm: _idm,
      serviceCodes: const [0x090F],
      blockListElements: [0x8000],
    );
    expect(result.ok, isTrue);
    expect(result.blocks.single, block);
  });

  test('状态非零：ok=false 且保留状态码，不要求块数量字段', () async {
    final protocol = FelicaProtocol(
      (_) async => _packet([0x07, ..._idm, 0x01, 0x0A]),
    );
    final result = await protocol.readWithoutEncryption(
      idm: _idm,
      serviceCodes: const [0x090F],
      blockListElements: [0x8000],
    );
    expect(result.ok, isFalse);
    expect(result.statusCode, 0x010A);
    expect(result.blocks, isEmpty);
  });

  test('适配器选择：Suica 需服务验证，未知码回退通用模式', () async {
    expect(
      (await _select(const [0x0003], protocol: _suicaServiceProtocol()))
          .runtimeType,
      SuicaAdapter,
    );
    expect((await _select(const [0x8008])).runtimeType, OctopusAdapter);
    expect((await _select(const [0x1234])).runtimeType, GenericFelicaAdapter);
  });

  test('系统码符合但 Suica 服务不可用：回退通用模式', () async {
    expect(
      (await _select(
        const [0x0003],
        protocol: _ScriptedTag(serviceAvailable: false).transceive,
      ))
          .runtimeType,
      GenericFelicaAdapter,
    );
  });

  test('仅凭 IDm 不认定卡型', () async {
    expect(
      (await _select(const [0x12FC])).runtimeType,
      GenericFelicaAdapter,
    );
  });

  test('SuicaDetector：非 NFC-F 直接返回依据不足', () {
    const detector = SuicaDetector();
    final result = detector.detect(
      isNfcF: false,
      systemCode: '0x0003',
      idm: '012E3A4B5C6D7E8F',
      hasVerifiedSuicaService: true,
      hasVerifiedSuicaRecord: true,
    );
    expect(result.type, FelicaCardType.unknown);
    expect(result.confidence, RecognitionConfidence.insufficient);
  });

  test('SuicaDetector：系统码与 IDm 不能单独认定卡型', () {
    const detector = SuicaDetector();
    final result = detector.detect(
      isNfcF: true,
      systemCode: '0x0003',
      idm: '012E3A4B5C6D7E8F',
      hasVerifiedSuicaService: false,
      hasVerifiedSuicaRecord: false,
    );
    expect(result.type, FelicaCardType.unknown);
    expect(result.confidence, RecognitionConfidence.insufficient);
    expect(result.evidence, contains('已获取系统代码'));
    expect(result.evidence, contains('已获取 IDm'));
  });

  test('SuicaDetector：仅服务验证 → 疑似 Suica', () {
    const detector = SuicaDetector();
    final result = detector.detect(
      isNfcF: true,
      systemCode: '0x0003',
      idm: '012E3A4B5C6D7E8F',
      hasVerifiedSuicaService: true,
      hasVerifiedSuicaRecord: false,
    );
    expect(result.type, FelicaCardType.suica);
    expect(result.confidence, RecognitionConfidence.probable);
    expect(result.displayName, '疑似 Suica');
  });

  test('SuicaDetector：服务 + 记录验证 → 确认 Suica', () {
    const detector = SuicaDetector();
    final result = detector.detect(
      isNfcF: true,
      systemCode: '0x0003',
      idm: '012E3A4B5C6D7E8F',
      hasVerifiedSuicaService: true,
      hasVerifiedSuicaRecord: true,
    );
    expect(result.type, FelicaCardType.suica);
    expect(result.confidence, RecognitionConfidence.confirmed);
    expect(result.displayName, 'Suica');
  });

  test('SuicaDetector：服务返回空版本 → 未验证', () async {
    const detector = SuicaDetector();
    final protocol = FelicaProtocol(
      (_) async => _packet([0x03, ..._idm, 0x00]),
    );
    expect(
      await detector.verifyService(idmBytes: _idm, protocol: protocol),
      isFalse,
    );
  });

  test('SuicaDetector：余额块格式校验', () {
    const detector = SuicaDetector();
    expect(detector.verifiedBalanceYen(const [0xE8, 0x03]), isNull);
    expect(
      detector.verifiedBalanceYen(
        [0xFF, 0x7F, ...List<int>.filled(14, 0)],
      ),
      isNull,
    );
    expect(
      detector.verifiedBalanceYen(
        [0xE8, 0x03, ...List<int>.filled(14, 0)],
      ),
      1000,
    );
  });

  test('Suica 余额：小端有符号日元，超范围视为无效', () {
    const parser = SuicaRecordParser();
    expect(parser.parseBalanceYen(const [0xE8, 0x03]), 1000);
    expect(parser.parseBalanceYen(const [0x18, 0xFC]), -1000);
    expect(parser.parseBalanceYen(const [0xFF, 0x7F]), isNull);
    expect(parser.parseBalanceYen(const [0x00]), isNull);
  });

  test('Suica 历史记录：金额 / BCD 时间 / 类型 / 终端', () {
    const parser = SuicaRecordParser();
    final record = parser.parseBlock(blockNumber: 1, bytes: _suicaRecord());
    expect(record.decoded, isTrue);
    expect(record.amountYen, -1000);
    expect(record.time, DateTime(2025, 10, 20, 8, 30));
    expect(record.type, '0x0B');
    expect(record.terminal, '0x1234');
  });

  test('Suica 空块不产出交易记录', () {
    const parser = SuicaRecordParser();
    final record =
        parser.parseBlock(blockNumber: 2, bytes: List<int>.filled(16, 0));
    expect(record.isBlank, isTrue);
    expect(record.decoded, isFalse);
  });

  test('Suica 原始模式：只保留原始字节', () {
    const parser = SuicaRecordParser(layout: SuicaRecordLayout.rawOnly);
    final record = parser.parseBlock(blockNumber: 1, bytes: _suicaRecord());
    expect(record.decoded, isFalse);
    expect(record.amountYen, isNull);
    expect(record.time, isNull);
    expect(record.rawHex, isNotEmpty);
  });

  test('八达通：只识别卡型，不读取未知服务、不显示 0 余额', () async {
    final context = FelicaCardContext(
      idm: '012E3A4B5C6D7E8F',
      idmBytes: _idm,
      systemCodes: const [0x8008],
      protocol: FelicaProtocol((_) async => const []),
    );
    const adapter = OctopusAdapter();
    expect(await adapter.matches(context), isTrue);
    final result = await adapter.read(context);
    expect(result.state, FelicaReadState.unsupported);
    expect(result.wallets.single.balanceMinorUnits, isNull);
    expect(result.wallets.single.balanceText, isNull);
  });

  test('Suica 端到端：余额与历史记录', () async {
    final reader = FelicaReader(
      _ScriptedTag(historyBlock1: _suicaRecord()).transceive,
    );
    final result = await reader.read();
    expect(result.cardType, 'suica');
    expect(result.wallets.single.balanceMinorUnits, 1000);
    expect(result.wallets.single.balanceVerified, isTrue);
    expect(result.wallets.single.balanceText, '¥1,000');
    expect(result.transactions, hasLength(1));
    final tx = result.transactions.single;
    expect(tx.amountMinorUnits, -1000);
    expect(tx.time, DateTime(2025, 10, 20, 8, 30));
    expect(tx.decoded, isTrue);
    expect(result.rawBlocks.length, 21);
    expect(result.state, FelicaReadState.success);
  });

  test('卡片无响应：映射为 tagLost 并保留失败阶段', () async {
    final reader = FelicaReader((_) async => const []);
    final result = await reader.read();
    expect(result.state, FelicaReadState.tagLost);
    expect(result.statuses.single.stage, 'FeliCa 協議探测');
  });

  group('八达通产品模型', () {
    test('全国通卡只有港币钱包，不是双钱包', () {
      expect(FelicaCardProfiles.octopusTUnion.isDualWallet, isFalse);
      expect(
        FelicaCardProfiles.octopusTUnion.expectedWallets,
        [FelicaWalletKind.octopusHKD],
      );
    });

    test('岭南通 / 深港互通行是双钱包产品', () {
      expect(FelicaCardProfiles.octopusLingnan.isDualWallet, isTrue);
      expect(
        FelicaCardProfiles.octopusLingnan.expectedWallets,
        [FelicaWalletKind.octopusHKD, FelicaWalletKind.lingnanRmb],
      );
      expect(FelicaCardProfiles.octopusShenzhen.isDualWallet, isTrue);
      expect(
        FelicaCardProfiles.octopusShenzhen.expectedWallets,
        [FelicaWalletKind.octopusHKD, FelicaWalletKind.shenzhenTongRmb],
      );
    });

    test('钱包占位不产生已验证余额', () {
      final wallets = createWalletPlaceholders(
        FelicaCardProfiles.octopusLingnan,
      );
      expect(wallets, hasLength(2));
      expect(
        wallets.map((w) => w.readState),
        everyElement(FelicaWalletReadState.notDetected),
      );
      expect(wallets.every((w) => w.balanceMinorUnits == null), isTrue);
      expect(wallets.every((w) => w.balanceVerified), isFalse);
    });

    test('识别器：无证据 / 多证据冲突 / 非 NFC-F 均不认定产品', () {
      const detector = OctopusDetector();
      expect(
        detector.detect(const OctopusDetectionEvidence.unverified()),
        isNull,
      );
      expect(
        detector.detect(
          const OctopusDetectionEvidence(
            isNfcF: true,
            matchesOctopusTUnionProfile: true,
            matchesLingnanDualProfile: true,
          ),
        ),
        isNull,
      );
      expect(
        detector.detect(
          const OctopusDetectionEvidence(
            isNfcF: false,
            matchesOctopusTUnionProfile: true,
          ),
        ),
        isNull,
      );
    });

    test('识别器：唯一证据命中对应产品', () {
      const detector = OctopusDetector();
      expect(
        detector
            .detect(
              const OctopusDetectionEvidence(
                isNfcF: true,
                matchesOctopusTUnionProfile: true,
              ),
            )
            ?.type,
        FelicaCardType.octopusTUnion,
      );
      expect(
        detector
            .detect(
              const OctopusDetectionEvidence(
                isNfcF: true,
                matchesShenzhenTongDualProfile: true,
              ),
            )
            ?.type,
        FelicaCardType.octopusShenzhenTongDual,
      );
    });
  });

  test('八达通无产品证据：单港币钱包，不预设人民币钱包', () async {
    final context = FelicaCardContext(
      idm: '012E3A4B5C6D7E8F',
      idmBytes: _idm,
      systemCodes: const [0x8008],
      protocol: FelicaProtocol((_) async => const []),
    );
    final result = await const OctopusAdapter().read(context);
    expect(result.cardProductType, FelicaCardType.octopus);
    expect(result.wallets, hasLength(1));
    expect(result.wallets.single.kind, FelicaWalletKind.octopusHKD);
    expect(result.wallets.single.currency, 'HKD');
    expect(result.wallets.single.readState, FelicaWalletReadState.unsupported);
    expect(result.wallets.single.balanceText, isNull);
    expect(result.crossBorder, isNull);
    expect(result.transitCapability, isNull);
  });

  test('全国通卡：单港币钱包 + 跨境折算信息，无第二钱包', () async {
    final context = FelicaCardContext(
      idm: '012E3A4B5C6D7E8F',
      idmBytes: _idm,
      systemCodes: const [0x8008],
      protocol: FelicaProtocol((_) async => const []),
    );
    final adapter = OctopusAdapter(
      evidenceBuilder: (_) => const OctopusDetectionEvidence(
        isNfcF: true,
        matchesOctopusTUnionProfile: true,
      ),
    );
    final result = await adapter.read(context);
    expect(result.cardType, 'octopus_tunion');
    expect(result.wallets, hasLength(1));
    expect(result.wallets.single.kind, FelicaWalletKind.octopusHKD);
    expect(result.wallets.single.currency, 'HKD');
    expect(result.wallets.single.balanceText, isNull);

    expect(result.crossBorder?.sourceCurrency, 'HKD');
    expect(result.crossBorder?.targetCurrency, 'CNY');
    expect(result.crossBorder?.hasVerifiedExchangeRate, isFalse);
    expect(result.transitCapability, contains('交通联合'));
    expect(result.hasVerifiedBalance, isFalse);
  });

  test('岭南通双钱包：两个钱包独立展示，均不显示为 0', () async {
    final context = FelicaCardContext(
      idm: '012E3A4B5C6D7E8F',
      idmBytes: _idm,
      systemCodes: const [0x8008],
      protocol: FelicaProtocol((_) async => const []),
    );
    final adapter = OctopusAdapter(
      evidenceBuilder: (_) => const OctopusDetectionEvidence(
        isNfcF: true,
        matchesLingnanDualProfile: true,
      ),
    );
    final result = await adapter.read(context);
    expect(result.cardType, 'octopus_lingnan_dual');
    expect(result.wallets, hasLength(2));
    expect(
      result.wallets.map((w) => w.kind),
      [FelicaWalletKind.octopusHKD, FelicaWalletKind.lingnanRmb],
    );

    expect(
      result.wallets.map((w) => w.currency),
      ['HKD', 'CNY'],
    );
    expect(
      result.wallets.every(
        (w) => w.readState == FelicaWalletReadState.unsupported,
      ),
      isTrue,
    );
    expect(result.wallets.every((w) => w.balanceText == null), isTrue);
    expect(result.crossBorder, isNull);
    expect(result.transitCapability, contains('岭南通'));
  });
}