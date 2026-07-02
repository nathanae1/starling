import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Event makeEvent({
    String? ref,
    List<MediaRef> media = const [],
    Map<String, Uint8List> extensions = const {},
  }) => Event(
    version: '2026-03-24',
    id: 'test-id-123',
    pubkey: 'test-pubkey-abc',
    createdAt: 1711324800,
    kind: EventKind.post,
    ref: ref,
    content: Uint8List.fromList([72, 101, 108, 108, 111]), // "Hello"
    media: media,
    extensions: extensions,
    sig: Uint8List.fromList(List.filled(64, 0xFF)),
  );

  group('Event CBOR serialization', () {
    test('round-trips through bytes', () {
      final event = makeEvent();
      final bytes = event.toBytes();
      final decoded = Event.fromBytes(bytes);
      expect(decoded, equals(event));
    });

    test('preserves non-null ref', () {
      final event = makeEvent(ref: 'referenced-event-id');
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.ref, equals('referenced-event-id'));
    });

    test('preserves null ref', () {
      final event = makeEvent();
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.ref, isNull);
    });

    test('preserves media list with entries', () {
      final event = makeEvent(
        media: [
          const MediaRef(hash: 'abc123', mimeType: 'image/jpeg', size: 1024),
          const MediaRef(hash: 'def456', mimeType: 'image/png', size: 2048),
        ],
      );
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.media, hasLength(2));
      expect(decoded.media[0].hash, equals('abc123'));
      expect(decoded.media[1].mimeType, equals('image/png'));
    });

    test('preserves empty media list', () {
      final event = makeEvent();
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.media, isEmpty);
    });

    test('round-trips with non-empty extensions', () {
      final event = makeEvent(
        extensions: {
          'custom': Uint8List.fromList([1, 2, 3]),
          'another': Uint8List.fromList([4, 5]),
        },
      );
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.extensions, hasLength(2));
      expect(
        decoded.extensions['custom'],
        equals(Uint8List.fromList([1, 2, 3])),
      );
      expect(decoded.extensions['another'], equals(Uint8List.fromList([4, 5])));
      expect(decoded, equals(event));
    });

    test('round-trips with empty extensions', () {
      final event = makeEvent();
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.extensions, isEmpty);
      expect(decoded, equals(event));
    });

    test(
      'toIdFields contains version, pubkey, created_at, kind, ref, content, media, extensions',
      () {
        final event = makeEvent(ref: 'some-ref');
        final idFields = event.toIdFields();
        expect(
          idFields.keys.toSet(),
          equals({
            'version',
            'pubkey',
            'created_at',
            'kind',
            'ref',
            'content',
            'media',
            'extensions',
          }),
        );
        expect(idFields['version'], equals('2026-03-24'));
        expect(idFields['pubkey'], equals('test-pubkey-abc'));
        expect(idFields['created_at'], equals(1711324800));
        expect(idFields['kind'], equals(EventKind.post.value));
        expect(idFields['ref'], equals('some-ref'));
      },
    );

    test('toIdFields excludes ref when null', () {
      final event = makeEvent();
      final idFields = event.toIdFields();
      expect(idFields.containsKey('ref'), isFalse);
      expect(
        idFields.keys.toSet(),
        equals({
          'version',
          'pubkey',
          'created_at',
          'kind',
          'content',
          'media',
          'extensions',
        }),
      );
    });

    test('toIdFields includes version', () {
      final event = makeEvent();
      final idFields = event.toIdFields();
      expect(idFields['version'], equals('2026-03-24'));
    });

    test('toIdFields includes extensions', () {
      final event = makeEvent(
        extensions: {
          'key': Uint8List.fromList([42]),
        },
      );
      final idFields = event.toIdFields();
      expect(idFields.containsKey('extensions'), isTrue);
    });

    test('all known EventKind values round-trip', () {
      for (final kind in EventKind.values) {
        expect(EventKind.fromValue(kind.value), equals(kind));
      }
    });

    test('unknown EventKind does not throw', () {
      final kind = EventKind.fromValue(999);
      expect(kind.value, equals(999));
      expect(kind.isKnown, isFalse);
    });

    test('unknown EventKind round-trips through Event', () {
      final event = Event(
        version: '2026-03-24',
        id: 'test-id',
        pubkey: 'test-pk',
        createdAt: 1000,
        kind: EventKind.fromValue(42),
        content: Uint8List(0),
        sig: Uint8List(64),
      );
      final decoded = Event.fromBytes(event.toBytes());
      expect(decoded.kind.value, equals(42));
    });
  });
}
