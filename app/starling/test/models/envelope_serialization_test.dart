import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvelopeItem CBOR serialization', () {
    test('round-trips through bytes', () {
      final item = EnvelopeItem(
        type: 'event',
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      final decoded = EnvelopeItem.fromBytes(item.toBytes());
      expect(decoded, equals(item));
    });

    test('preserves extensions', () {
      final item = EnvelopeItem(
        type: 'event',
        payload: Uint8List.fromList([10, 20]),
        extensions: {
          'hint': Uint8List.fromList([99]),
        },
      );
      final decoded = EnvelopeItem.fromBytes(item.toBytes());
      expect(decoded.extensions['hint'], equals(Uint8List.fromList([99])));
      expect(decoded, equals(item));
    });

    test('empty extensions round-trips', () {
      final item = EnvelopeItem(type: 'commit', payload: Uint8List(0));
      final decoded = EnvelopeItem.fromBytes(item.toBytes());
      expect(decoded.extensions, isEmpty);
      expect(decoded, equals(item));
    });
  });

  group('Envelope CBOR serialization', () {
    test('round-trips with one item', () {
      final envelope = Envelope(
        version: '2026-03-24',
        items: [
          EnvelopeItem(type: 'event', payload: Uint8List.fromList([1, 2, 3])),
        ],
      );
      final decoded = Envelope.fromBytes(envelope.toBytes());
      expect(decoded, equals(envelope));
      expect(decoded.items, hasLength(1));
      expect(decoded.items.first.type, equals('event'));
    });

    test('round-trips with multiple items', () {
      final envelope = Envelope(
        version: '2026-03-24',
        items: [
          EnvelopeItem(type: 'event', payload: Uint8List.fromList([1])),
          EnvelopeItem(type: 'commit', payload: Uint8List.fromList([2])),
          EnvelopeItem(type: 'receipt', payload: Uint8List.fromList([3])),
        ],
      );
      final decoded = Envelope.fromBytes(envelope.toBytes());
      expect(decoded, equals(envelope));
      expect(decoded.items, hasLength(3));
      expect(decoded.items[1].type, equals('commit'));
    });

    test('round-trips with empty items', () {
      const envelope = Envelope(version: '2026-03-24', items: []);
      final decoded = Envelope.fromBytes(envelope.toBytes());
      expect(decoded.items, isEmpty);
      expect(decoded, equals(envelope));
    });

    test('preserves envelope-level extensions', () {
      final envelope = Envelope(
        version: '2026-03-24',
        items: [EnvelopeItem(type: 'event', payload: Uint8List(0))],
        extensions: {
          'routing': Uint8List.fromList([1, 2, 3]),
        },
      );
      final decoded = Envelope.fromBytes(envelope.toBytes());
      expect(
        decoded.extensions['routing'],
        equals(Uint8List.fromList([1, 2, 3])),
      );
      expect(decoded, equals(envelope));
    });

    test('items with different types coexist', () {
      final envelope = Envelope(
        version: '2026-03-24',
        items: [
          EnvelopeItem(type: 'event', payload: Uint8List.fromList([10])),
          EnvelopeItem(
            type: 'unknown-future-type',
            payload: Uint8List.fromList([20, 30]),
            extensions: {
              'meta': Uint8List.fromList([40]),
            },
          ),
        ],
      );
      final decoded = Envelope.fromBytes(envelope.toBytes());
      expect(decoded.items[0].type, equals('event'));
      expect(decoded.items[1].type, equals('unknown-future-type'));
      expect(
        decoded.items[1].extensions['meta'],
        equals(Uint8List.fromList([40])),
      );
    });
  });
}
