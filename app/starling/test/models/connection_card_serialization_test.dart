import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionCard CBOR serialization', () {
    test('round-trips with endpoints', () {
      const card = ConnectionCard(
        pubkey: 'test-pubkey-123',
        endpoints: [
          Endpoint(type: 'onion', address: 'abc123.onion'),
          Endpoint(type: 'relay', address: 'https://relay.example.com'),
        ],
      );
      final decoded = ConnectionCard.fromBytes(card.toBytes());
      expect(decoded, equals(card));
    });

    test('round-trips with empty endpoints', () {
      const card = ConnectionCard(pubkey: 'test-pubkey-456');
      final decoded = ConnectionCard.fromBytes(card.toBytes());
      expect(decoded.pubkey, equals('test-pubkey-456'));
      expect(decoded.endpoints, isEmpty);
      expect(decoded, equals(card));
    });

    test('Endpoint round-trips through CBOR', () {
      const endpoint = Endpoint(type: 'onion', address: 'xyz.onion');
      final bytes = cbor.encode(endpoint.toMap());
      final decoded = Endpoint.fromMap(
        cbor.decode(bytes) as Map<dynamic, dynamic>,
      );
      expect(decoded, equals(endpoint));
    });

    test('both onion and relay types preserved', () {
      const card = ConnectionCard(
        pubkey: 'pk',
        endpoints: [
          Endpoint(type: 'onion', address: 'abc.onion'),
          Endpoint(type: 'relay', address: 'https://r.example.com'),
        ],
      );
      final decoded = ConnectionCard.fromBytes(card.toBytes());
      expect(decoded.endpoints[0].type, equals('onion'));
      expect(decoded.endpoints[1].type, equals('relay'));
      expect(decoded.endpoints[0].address, equals('abc.onion'));
      expect(decoded.endpoints[1].address, equals('https://r.example.com'));
    });

    test('round-trips with capabilities', () {
      const card = ConnectionCard(
        pubkey: 'pk',
        capabilities: ['pairwise-v1', 'mls-v1'],
      );
      final decoded = ConnectionCard.fromBytes(card.toBytes());
      expect(decoded.capabilities, equals(['pairwise-v1', 'mls-v1']));
      expect(decoded, equals(card));
    });

    test(
      'defaults capabilities advertise pairwise-v1 and libp2p-direct-v1',
      () {
        // Plan 11a — new ConnectionCards default-advertise libp2p-direct
        // alongside the original pairwise-v1 so DCUtR upgrades opt in by
        // default for any peer issued a card after this change.
        const card = ConnectionCard(pubkey: 'pk');
        expect(card.capabilities, equals(['pairwise-v1', 'libp2p-direct-v1']));
      },
    );

    test('missing capabilities in wire data defaults to pairwise-v1', () {
      // Simulate a v1 card serialized without capabilities field
      final map = {'pubkey': 'pk', 'endpoints': <dynamic>[]};
      final bytes = cbor.encode(map);
      final decoded = ConnectionCard.fromMap(
        cbor.decode(bytes) as Map<dynamic, dynamic>,
      );
      expect(decoded.capabilities, equals(['pairwise-v1']));
    });
  });
}
