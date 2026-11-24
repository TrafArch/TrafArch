import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'gallery_data.dart';

/// Persistence for user-selected card faces. Image bytes are kept in separate
/// app-private files; only small crop/size/seed metadata is serialized inline.
abstract interface class GalleryFaceStore {
  Future<GalleryFaceSnapshot?> read(String cardId);
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot);
  Future<void> delete(String cardId);
}

@immutable
class GalleryFaceSnapshot {
  const GalleryFaceSnapshot({
    required this.image,
    required this.width,
    required this.height,
    required this.detail,
    required this.list,
    required this.seed,
  });

  final Uint8List image;
  final double width;
  final double height;
  final GalleryFaceCrop detail;
  final GalleryFaceCrop list;
  final int? seed;
}

/// Files live in the application documents directory and are associated with
/// a stable card id. Filenames never contain raw card identifiers.
class FileGalleryFaceStore implements GalleryFaceStore {
  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}gallery_faces',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _key(String id) =>
      base64Url.encode(utf8.encode(id)).replaceAll('=', '');
  String _path(Directory dir, String id, String extension) =>
      '${dir.path}${Platform.pathSeparator}${_key(id)}.$extension';

  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async {
    final dir = await _directory();
    final metadata = File(_path(dir, cardId, 'json'));
    final image = File(_path(dir, cardId, 'img'));
    if (!await metadata.exists() || !await image.exists()) return null;
    final data =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    GalleryFaceCrop crop(String key) {
      final values = data[key] as Map<String, dynamic>;
      return GalleryFaceCrop(
        scale: (values['scale'] as num).toDouble(),
        offsetX: (values['x'] as num).toDouble(),
        offsetY: (values['y'] as num).toDouble(),
        rotation: (values['rotation'] as num).toDouble(),
      );
    }

    return GalleryFaceSnapshot(
      image: await image.readAsBytes(),
      width: (data['width'] as num).toDouble(),
      height: (data['height'] as num).toDouble(),
      detail: crop('detail'),
      list: crop('list'),
      seed: data['seed'] as int?,
    );
  }

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {
    final dir = await _directory();
    final image = File(_path(dir, cardId, 'img'));
    final metadata = File(_path(dir, cardId, 'json'));
    Map<String, double> encodedCrop(GalleryFaceCrop crop) => {
      'scale': crop.scale,
      'x': crop.offsetX,
      'y': crop.offsetY,
      'rotation': crop.rotation,
    };
    final json = jsonEncode({
      'width': snapshot.width,
      'height': snapshot.height,
      'detail': encodedCrop(snapshot.detail),
      'list': encodedCrop(snapshot.list),
      'seed': snapshot.seed,
    });
    final temp = File('${image.path}.tmp');
    await temp.writeAsBytes(snapshot.image, flush: true);
    if (await image.exists()) await image.delete();
    await temp.rename(image.path);
    await metadata.writeAsString(json, flush: true);
  }

  @override
  Future<void> delete(String cardId) async {
    final dir = await _directory();
    for (final extension in ['img', 'json']) {
      final file = File(_path(dir, cardId, extension));
      if (await file.exists()) await file.delete();
    }
  }
}

/// The host supplies preference persistence; card-face persistence defaults to
/// app-private storage and can be replaced by an in-memory test store.
class GalleryPreferences extends ChangeNotifier {
  GalleryPreferences({
    this.readEnabled,
    this.writeEnabled,
    GalleryFaceStore? faceStore,
  }) : faceStore = faceStore ?? FileGalleryFaceStore();

  final Future<bool> Function()? readEnabled;
  final Future<void> Function(bool)? writeEnabled;
  final GalleryFaceStore faceStore;
  String? faceError;
  final Map<String, Future<GalleryFaceSnapshot?>> _faceReads = {};
  bool enabled = true;
  bool loading = false;
  String? error;
  bool _readFailed = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void>? _writes;

  Future<void> load() async {
    if (_disposed || loading || readEnabled == null) return;
    loading = true;
    final revision = _revision;
    notifyListeners();
    try {
      final value = await readEnabled!();
      if (!_disposed && revision == _revision) {
        enabled = value;
        error = null;
        _readFailed = false;
      }
    } catch (_) {
      if (!_disposed && revision == _revision) {
        error = '无法读取返回手势偏好，当前使用默认设置。';
        _readFailed = true;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setEnabled(bool value) {
    if (_disposed) return Future.value();
    enabled = value;
    final revision = ++_revision;
    _readFailed = false;
    error = null;
    notifyListeners();
    return _writes = (_writes ?? Future<void>.value()).then((_) async {
      try {
        await writeEnabled?.call(value);
        if (!_disposed && revision == _revision) error = null;
      } catch (_) {
        if (!_disposed && revision == _revision) {
          error = '返回手势偏好未保存，当前选择仅在本次会话生效。';
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> restoreFaceImages(Iterable<GalleryCard> cards) async {
    try {
      for (final card in cards) {
        if (card.image != null) continue;
        final saved = await (_faceReads[card.id] ??= faceStore.read(card.id));
        if (saved == null || card.image != null) continue;
        card.image = saved.image;
        card.imageSize = Size(saved.width, saved.height);
        card.detailCrop = saved.detail;
        card.listCrop = saved.list;
        card.monetSeed = saved.seed == null ? null : Color(saved.seed!);
      }
      faceError = null;
    } catch (_) {
      faceError = '无法恢复已保存的卡面图片。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> saveFaceImage(GalleryCard card) async {
    final bytes = card.image;
    final size = card.imageSize;
    if (bytes == null || size == null) {
      await clearFaceImage(card.id);
      return faceError == null;
    }
    try {
      await faceStore.write(
        card.id,
        GalleryFaceSnapshot(
          image: bytes,
          width: size.width,
          height: size.height,
          detail: card.detailCrop,
          list: card.listCrop,
          seed: card.monetSeed?.toARGB32(),
        ),
      );
      faceError = null;
    } catch (_) {
      faceError = '卡面图片未能保存到本机。';
    }
    if (!_disposed) notifyListeners();
    return faceError == null;
  }

  Future<void> clearFaceImage(String cardId) async {
    try {
      await faceStore.delete(cardId);
      faceError = null;
    } catch (_) {
      faceError = '已更换卡面，但旧图片未能从本机清除。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> retry() => _readFailed ? load() : setEnabled(enabled);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
