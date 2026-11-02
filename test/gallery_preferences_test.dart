import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

void main() {
  GalleryPreferences stored(SettingsStore store) => GalleryPreferences(
    readEnabled: () async =>
        await store.read(SettingsKeys.galleryPredictiveBackEnabled) != 'false',
    writeEnabled: (value) =>
        store.write(SettingsKeys.galleryPredictiveBackEnabled, '$value'),
  );

  test('default is on and stored selection survives recreation without changing other settings', () async {
    final store = MemorySettingsStore({'auto_save_enabled': 'true'});
    final first = stored(store);
    await first.load();
    expect(first.enabled, isTrue);
    await first.setEnabled(false);
    first.dispose();
    final second = stored(store);
    await second.load();
    expect(second.enabled, isFalse);
    expect(store.values['auto_save_enabled'], 'true');
    second.dispose();
  });

  test('read failure retains default, does not write, and retries', () async {
    var fail = true;
    var writes = 0;
    final prefs = GalleryPreferences(
      readEnabled: () async {
        if (fail) throw StateError('unreadable');
        return false;
      },
      writeEnabled: (_) async {
        writes++;
      },
    );
    await prefs.load();
    expect(prefs.enabled, isTrue);
    expect(prefs.error, contains('无法读取'));
    expect(writes, 0);
    fail = false;
    await prefs.retry();
    expect(prefs.enabled, isFalse);
    expect(prefs.error, isNull);
    prefs.dispose();
  });

  test(
    'failed save is visible and retry saves the current selection',
    () async {
      var fail = true;
      bool? saved;
      final prefs = GalleryPreferences(
        writeEnabled: (value) async {
          if (fail) throw StateError('unwritable');
          saved = value;
        },
      );
      await prefs.setEnabled(false);
      expect(prefs.enabled, isFalse);
      expect(prefs.error, contains('未保存'));
      fail = false;
      await prefs.retry();
      expect(saved, isFalse);
      expect(prefs.error, isNull);
      prefs.dispose();
    },
  );

  test('late initial read cannot overwrite an explicit selection', () async {
    final read = Completer<bool>();
    final prefs = GalleryPreferences(readEnabled: () => read.future);
    final loading = prefs.load();
    await prefs.setEnabled(false);
    read.complete(true);
    await loading;
    expect(prefs.enabled, isFalse);
    prefs.dispose();
  });

  test(
    'rapid writes serialize and old failures do not replace newer success',
    () async {
      final gate = Completer<void>();
      final writes = <bool>[];
      final prefs = GalleryPreferences(
        writeEnabled: (value) async {
          writes.add(value);
          if (!value) {
            await gate.future;
            throw StateError('first write failed');
          }
        },
      );
      final first = prefs.setEnabled(false);
      final second = prefs.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(writes, [false]);
      gate.complete();
      await Future.wait([first, second]);
      expect(writes, [false, true]);
      expect(prefs.enabled, isTrue);
      expect(prefs.error, isNull);
      prefs.dispose();
    },
  );

  test(
    'accepted save completes after disposal without notifying a dead host',
    () async {
      final gate = Completer<void>();
      var saved = false;
      final prefs = GalleryPreferences(
        writeEnabled: (_) async {
          await gate.future;
          saved = true;
        },
      );
      final pending = prefs.setEnabled(false);
      prefs.dispose();
      gate.complete();
      await pending;
      expect(saved, isTrue);
    },
  );
}
