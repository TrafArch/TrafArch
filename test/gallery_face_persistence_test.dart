import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';

class _MemoryFaceStore implements GalleryFaceStore {
  final values = <String, GalleryFaceSnapshot>{};

  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => values[cardId];

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {
    values[cardId] = snapshot;
  }

  @override
  Future<void> delete(String cardId) async => values.remove(cardId);
}

void main() {
  test('restores a card image with crop geometry and Monet seed', () async {
    final store = _MemoryFaceStore();
    final first = GalleryPreferences(faceStore: store);
    final card = GalleryCard.live(
      id: 'card-a',
      saved: true,
      name: '测试卡',
      tail: '1234',
      pan: '未提供',
      rawBalance: '0',
      city: '测试',
      type: '交通卡',
      valid: '未知',
      when: '未知',
      count: '0',
      face: 'blue',
      applications: const [],
      currencyCode: null,
    );
    card.image = Uint8List.fromList([1, 2, 3, 4]);
    card.imageSize = const Size(1200, 800);
    card.detailCrop = const GalleryFaceCrop(
      scale: 1.7,
      offsetX: .25,
      offsetY: -.4,
      rotation: .1,
    );
    card.listCrop = const GalleryFaceCrop(
      scale: 2.1,
      offsetX: -.3,
      offsetY: .2,
    );
    card.monetSeed = const Color(0xff123456);
    await first.saveFaceImage(card);
    first.dispose();

    final restored = GalleryCard.live(
      id: 'card-a',
      saved: true,
      name: '测试卡',
      tail: '1234',
      pan: '未提供',
      rawBalance: '0',
      city: '测试',
      type: '交通卡',
      valid: '未知',
      when: '未知',
      count: '0',
      face: 'blue',
      applications: const [],
      currencyCode: null,
    );
    final other = GalleryCard.live(
      id: 'card-b',
      saved: true,
      name: '另一张卡',
      tail: '5678',
      pan: '未提供',
      rawBalance: '0',
      city: '测试',
      type: '交通卡',
      valid: '未知',
      when: '未知',
      count: '0',
      face: 'teal',
      applications: const [],
      currencyCode: null,
    );
    final nextLaunch = GalleryPreferences(faceStore: store);
    await nextLaunch.restoreFaceImages([restored, other]);

    expect(restored.image, [1, 2, 3, 4]);
    expect(restored.imageSize, const Size(1200, 800));
    expect(restored.detailCrop.scale, 1.7);
    expect(restored.detailCrop.offsetX, .25);
    expect(restored.detailCrop.offsetY, -.4);
    expect(restored.detailCrop.rotation, .1);
    expect(restored.listCrop.scale, 2.1);
    expect(restored.listCrop.offsetX, -.3);
    expect(restored.listCrop.offsetY, .2);
    expect(restored.monetSeed, const Color(0xff123456));
    expect(
      other.image,
      isNull,
      reason: 'image must remain associated by card id',
    );

    await nextLaunch.clearFaceImage('card-a');
    expect(await store.read('card-a'), isNull);
    expect(await store.read('card-b'), isNull);
    nextLaunch.dispose();
  });
}
