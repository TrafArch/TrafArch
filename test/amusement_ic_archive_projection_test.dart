import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/amusement_ic_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';

const _code = '50101234567890123456';
const _fingerprint = 'felica:amusement_ic:access-code:$_code';
const _idm = '0102030405060708';

Map<String, dynamic> _section({
  Object? version = 1,
  Object? code = _code,
  Object? issuer = 'Aime',
  Object? idm = _idm,
}) => {
  'version': version,
  'identityKind': 'amusement-ic-access-code',
  'idm': idm,
  'data': {
    'accessCode': code,
    'issuer': issuer,
    'dataFormatCode': 0x0078,
    'spad0Hex': '893D691806ECCFEF90C8773D41EEE231',
    'idBlockHex': '01020304050607080078000000000000',
  },
};

String _payload(Object? section, {String systemId = 'felica_amusement_ic'}) =>
    CardSessionSnapshot(
      context: ArchiveContext(
        systemId: systemId,
        applicationId: 'felica-system:88B4/service:000B',
      ),
      extensions: {'amusementIc': section},
    ).encode();

ArchiveHistoryResult _history(
  List<({int time, String payload})> captures, {
  String cardType = 'amusement_ic',
  String fingerprint = _fingerprint,
  String? scalar,
}) => ArchiveHistory.project(
  ArchiveRows(
    card: SavedCard(
      id: 'aic-card',
      cardFingerprint: fingerprint,
      cardType: cardType,
      identificationSource: 'parser_only',
      createdAt: 0,
      updatedAt: 0,
      sessionDataJson: scalar,
    ),
    batches: [
      for (var i = 0; i < captures.length; i++)
        CardReadBatch(
          id: 'capture-$i',
          cardId: 'aic-card',
          cardFingerprint: fingerprint,
          readAt: captures[i].time,
          parseVersion: 1,
          payloadJson: captures[i].payload,
        ),
    ],
  ),
);

void main() {
  test(
    'latest complete AIC capture restores its own code brand IDm and time',
    () {
      final old = _payload(_section(issuer: 'Captured old brand'));
      final newest = _payload(
        _section(issuer: 'Captured latest brand', idm: '0807060504030201'),
      );
      final history = _history([
        (time: 10, payload: old),
        (time: 30, payload: newest),
      ]);
      final projection = projectAmusementIcArchive(history);
      expect(projection.hasCaptures, isTrue);
      expect(projection.data?.accessCode, _code);
      expect(projection.data?.issuer, 'Captured latest brand');
      expect(projection.idm, '0807060504030201');
      expect(projection.readAt?.millisecondsSinceEpoch, 30);
      expect(projection.issues, isEmpty);
      expect(projection.data?.spad0Hex, '893D691806ECCFEF90C8773D41EEE231');
      expect(history.batches.first.decoded.rawJson, newest);
    },
  );

  test(
    'incomplete captures cannot combine a code with another capture brand',
    () {
      final history = _history([
        (time: 30, payload: _payload(_section(issuer: null))),
        (
          time: 20,
          payload: _payload(
            _section(code: null, issuer: 'Other captured brand'),
          ),
        ),
        (
          time: 10,
          payload: _payload(_section(issuer: 'Complete captured brand')),
        ),
      ]);
      final projection = projectAmusementIcArchive(history);
      expect(projection.data?.issuer, 'Complete captured brand');
      expect(projection.data?.accessCode, _code);
      expect(projection.readAt?.millisecondsSinceEpoch, 10);
      expect(projection.issues, hasLength(2));
    },
  );

  test(
    'future section falls back to older frozen data without altering evidence',
    () {
      final future = _payload(_section(version: 99));
      final history = _history([
        (time: 20, payload: future),
        (time: 10, payload: _payload(_section())),
      ]);
      final before = history.batches.map((b) => b.decoded.rawJson).toList();
      final projection = projectAmusementIcArchive(history);
      expect(projection.data?.accessCode, _code);
      expect(projection.readAt?.millisecondsSinceEpoch, 10);
      expect(projection.issues.single, contains('capture-0'));
      expect(projection.issues.single, contains('格式'));
      expect(history.batches.map((b) => b.decoded.rawJson), before);
    },
  );

  for (final broken in <Object?>[
    'invalid section',
    _section(code: 501),
    _section(code: '5010123456789012345'),
    _section(code: null),
    _section(issuer: ''),
    _section(issuer: 123),
  ]) {
    test('broken AIC identity stays unknown: $broken', () {
      final payload = _payload(broken);
      final history = _history([(time: 10, payload: payload)]);
      final projection = projectAmusementIcArchive(history);
      expect(projection.hasCaptures, isTrue);
      expect(projection.data, isNull);
      expect(projection.idm, isNull);
      expect(projection.readAt, isNull);
      expect(projection.issues, isNotEmpty);
      expect(history.batches.single.decoded.rawJson, payload);
    });
  }

  test(
    'a different Access Code cannot be displayed under this card identity',
    () {
      final projection = projectAmusementIcArchive(
        _history([
          (time: 10, payload: _payload(_section(code: '50101234567890123457'))),
        ]),
      );
      expect(projection.hasCaptures, isTrue);
      expect(projection.data, isNull);
      expect(projection.issues.single, contains('身份'));
    },
  );

  test(
    'a transport IDm fingerprint cannot stand in for Access Code identity',
    () {
      final projection = projectAmusementIcArchive(
        _history([
          (time: 10, payload: _payload(_section())),
        ], fingerprint: 'felica:suica:idm:$_idm'),
      );
      expect(projection.data, isNull);
      expect(projection.issues, isNotEmpty);
    },
  );

  test('foreign card types do not adopt an AIC extension', () {
    final projection = projectAmusementIcArchive(
      _history([(time: 10, payload: _payload(_section()))], cardType: 'suica'),
    );
    expect(projection.data, isNull);
    expect(projection.hasCaptures, isFalse);
  });

  test('foreign snapshot context cannot supply AIC fields', () {
    final projection = projectAmusementIcArchive(
      _history([
        (time: 10, payload: _payload(_section(), systemId: 'felica_suica')),
      ]),
    );
    expect(projection.data, isNull);
    expect(projection.issues, isNotEmpty);
  });

  test('invalid optional IDm never replaces a valid frozen Access Code', () {
    final projection = projectAmusementIcArchive(
      _history([(time: 10, payload: _payload(_section(idm: 123)))]),
    );
    expect(projection.data?.accessCode, _code);
    expect(projection.idm, isNull);
    expect(projection.issues.single, contains('IDm'));
  });

  test('scalar-only archive restores its frozen AIC extension', () {
    final projection = projectAmusementIcArchive(
      _history([], scalar: _payload(_section())),
    );
    expect(projection.data?.accessCode, _code);
    expect(projection.data?.issuer, 'Aime');
    expect(projection.hasCaptures, isTrue);
  });

  test('empty and missing histories have no AIC capture', () {
    for (final history in [
      _history([]),
      const ArchiveHistoryResult(card: null),
    ]) {
      final projection = projectAmusementIcArchive(history);
      expect(projection.data, isNull);
      expect(projection.hasCaptures, isFalse);
      expect(projection.issues, isEmpty);
    }
  });
}
