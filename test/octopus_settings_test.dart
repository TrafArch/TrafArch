import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  for (final previouslyEnabled in [false, true]) {
    testWidgets('设置不再提供八达通官方联网入口，旧开启状态为 $previouslyEnabled', (tester) async {
      final store = _TrackedSettingsStore({
        'octopus_online_enabled_v1': '$previouslyEnabled',
        'octopus_online_consent_accepted_v1': '$previouslyEnabled',
      });
      final app = AppDependencies(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: store,
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
      await tester.pumpAndSettle();

      expect(find.text('已经存在的记录'), findsOneWidget);
      expect(find.text('八达通联网查询'), findsNothing);
      expect(find.text('开启八达通联网查询'), findsNothing);
      expect(find.text('同意并开启'), findsNothing);
      expect(find.textContaining('汇率'), findsNothing);
      expect(
        store.readKeys.where((key) => key.startsWith('octopus_online_')),
        isEmpty,
      );
      expect(store.values['octopus_online_enabled_v1'], '$previouslyEnabled');
      expect(tester.takeException(), isNull);
    });
  }
}

class _TrackedSettingsStore extends MemorySettingsStore {
  _TrackedSettingsStore(super.values);
  final readKeys = <String>[];

  @override
  Future<String?> read(String key) {
    readKeys.add(key);
    return super.read(key);
  }
}
