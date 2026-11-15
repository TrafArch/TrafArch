import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_application.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';
import 'package:transit_card_analyzer/shared/presentation/application_evidence_panel.dart';

void main() {
  group('ApplicationEvidence 序列化', () {
    test('成功证据往返保留状态、身份、余额、记录数', () {
      final source = ApplicationEvidence.succeeded(
        'tu',
        '交通联合电子钱包（JT/T 978.2）',
        cardNumber: '310477000000000001',
        balanceFen: 10000,
        recordCount: 3,
        payload: const TUnionCardInfo(
          applicationSerial: '03104770000000000001',
          balanceFen: 10000,
        ),
      );
      final restored = ApplicationEvidence.tryParse(source.toJson())!;
      expect(restored.appId, 'tu');
      expect(restored.displayName, source.displayName);
      expect(restored.state, ApplicationProbeState.readSucceeded);
      expect(restored.probed, isTrue);
      expect(restored.confirmed, isTrue);
      expect(restored.readSucceeded, isTrue);
      expect(restored.cardNumber, '310477000000000001');
      expect(restored.balanceFen, 10000);
      expect(restored.recordCount, 3);
    });

    test('拒绝与失败证据保留原因和传输失败类型', () {
      final rejected = ApplicationEvidence.rejected(
        'macau',
        '澳门通（钱包应用）',
        reason: '澳门通钱包应用未确认',
      );
      final restoredRejected = ApplicationEvidence.tryParse(
        rejected.toJson(),
      )!;
      expect(restoredRejected.state, ApplicationProbeState.selectRejected);
      expect(restoredRejected.notes.single, '澳门通钱包应用未确认');

      final failed = ApplicationEvidence.failed(
        'bank',
        '银行卡（EMV / PBOC）',
        readError: 'synthetic error',
        transportFailure: const TransportFailure(
          kind: TransportFailureKind.tagLost,
          code: 'TAG_LOST',
          message: 'synthetic tag loss',
        ),
      );
      final restoredFailed = ApplicationEvidence.tryParse(failed.toJson())!;
      expect(restoredFailed.state, ApplicationProbeState.failed);
      expect(restoredFailed.readError, 'synthetic error');
      expect(restoredFailed.transportFailure!.kind, TransportFailureKind.tagLost);
      expect(restoredFailed.transportFailure!.code, 'TAG_LOST');
    });

    test('损坏条目返回 null，未知状态回退未探测且不抛异常', () {
      expect(ApplicationEvidence.tryParse(null), isNull);
      expect(ApplicationEvidence.tryParse('not-a-map'), isNull);
      final tolerant = ApplicationEvidence.tryParse({
        'appId': 'cu',
        'state': 'not-a-real-state',
      })!;
      expect(tolerant.appId, 'cu');
      expect(tolerant.state, ApplicationProbeState.notProbed);
    });
  });

  group('payloadSummary 载荷摘要', () {
    test('ParsedCard 摘要保留解析器与余额', () {
      final evidence = ApplicationEvidence.succeeded(
        'tu',
        '交通联合',
        payload: ParsedCard(
          parserId: CardParserIds.tunion,
          parserName: '交通联合电子钱包（JT/T 978.2）',
          info: const TUnionCardInfo(balanceFen: 3210),
          transactions: const [],
          selectedAidHex: 'A000000632010105',
        ),
      );
      final summary = evidence.toJson()['payload'] as Map<String, dynamic>;
      expect(summary['kind'], 'parsed_card');
      expect(summary['parserId'], CardParserIds.tunion);
      expect(summary['selectedAid'], 'A000000632010105');
      expect(summary['balanceFen'], 3210);
    });

    test('BankCardResult 摘要保留状态与已发现 AID', () {
      final evidence = ApplicationEvidence.succeeded(
        'bank',
        '银行卡（EMV / PBOC）',
        payload: BankCardResult(
          protocolFamily: BankCardProtocolFamily.pboc,
          analyzedAt: DateTime(2026),
          parserVersion: '0.3.2',
          status: BankCardStatus.partial,
          discoveredApplications: const [
            CardApplication(aidHex: 'A000000333010101', selected: true),
          ],
        ),
      );
      final summary = evidence.toJson()['payload'] as Map<String, dynamic>;
      expect(summary['kind'], 'bank_card');
      expect(summary['status'], 'partial');
      expect(summary['discoveredAids'], ['A000000333010101']);
    });

    test('ReadResult 摘要保留本地卡身份与卡号', () {
      final info = CardInfo()..isSZT = true;
      info.cardNumber = '4045620583';
      final evidence = ApplicationEvidence.succeeded(
        'shenzhen',
        '深圳通（PAY.SZT）',
        payload: ReadResult(info: info, records: const [], extras: CardExtras()),
      );
      final summary = evidence.toJson()['payload'] as Map<String, dynamic>;
      expect(summary['kind'], 'read_result');
      expect(summary['isLocalCard'], isTrue);
      expect(summary['cardNumber'], '4045620583');
    });
  });

  group('ApplicationEvidencePanel', () {
    testWidgets('空列表不渲染任何内容', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ApplicationEvidencePanel(applications: []),
          ),
        ),
      );
      expect(find.text('逐应用探测'), findsNothing);
    });

    testWidgets('逐应用并列展示状态、卡号、余额与记录数', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApplicationEvidencePanel(
              applications: [
                ApplicationEvidence.succeeded(
                  'tu',
                  '交通联合电子钱包（JT/T 978.2）',
                  cardNumber: '310477000000000001',
                  balanceFen: 10000,
                  recordCount: 3,
                ),
                ApplicationEvidence.rejected(
                  'macau',
                  '澳门通（钱包应用）',
                  reason: '澳门通钱包应用未确认',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('逐应用探测'), findsOneWidget);
      expect(
        find.textContaining('交通联合电子钱包（JT/T 978.2） · 读取成功'),
        findsOneWidget,
      );
      expect(find.textContaining('卡号 310477000000000001'), findsOneWidget);
      expect(find.textContaining('余额 10000 分'), findsOneWidget);
      expect(find.textContaining('3 条记录'), findsOneWidget);
      expect(find.textContaining('澳门通（钱包应用） · 应用未确认'), findsOneWidget);
    });

    test('状态标签覆盖全部状态', () {
      expect(
        applicationProbeStateLabel(ApplicationProbeState.notProbed),
        '未探测',
      );
      expect(
        applicationProbeStateLabel(ApplicationProbeState.selectRejected),
        '应用未确认',
      );
      expect(
        applicationProbeStateLabel(ApplicationProbeState.confirmed),
        '已确认',
      );
      expect(
        applicationProbeStateLabel(ApplicationProbeState.readSucceeded),
        '读取成功',
      );
      expect(
        applicationProbeStateLabel(ApplicationProbeState.partial),
        '部分读取',
      );
      expect(
        applicationProbeStateLabel(ApplicationProbeState.failed),
        '失败',
      );
    });
  });
}
