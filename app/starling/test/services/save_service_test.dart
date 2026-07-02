import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/save_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultSaveService', () {
    late MockStorageService storage;
    late DefaultSaveService service;

    setUp(() {
      storage = MockStorageService();
      service = DefaultSaveService(storage);
    });

    tearDown(() async {
      await storage.dispose();
    });

    test('isSaved is false by default', () async {
      expect(await service.isSaved('e1'), isFalse);
    });

    test('setSaved(true) flips the flag', () async {
      await service.setSaved('e1', true);
      expect(await service.isSaved('e1'), isTrue);
    });

    test('toggle round-trips and returns the new state', () async {
      expect(await service.toggle('e1'), isTrue);
      expect(await service.toggle('e1'), isFalse);
      expect(await service.toggle('e1'), isTrue);
    });

    test(
      'produces no event — toggling never inserts into events table',
      () async {
        // Seed one unrelated event to baseline.
        final e = Event(
          version: '2026-03-24',
          id: 'pre-existing',
          pubkey: 'p',
          createdAt: 1,
          kind: EventKind.post,
          content: Uint8List(0),
          sig: Uint8List(64),
        );
        await storage.saveEvent(e);
        final before = (await storage.getEvents()).length;

        await service.toggle('any-id');
        await service.toggle('another-id');
        await service.setSaved('third-id', true);

        final after = (await storage.getEvents()).length;
        expect(after, equals(before));
      },
    );
  });
}
