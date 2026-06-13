import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/lan_network_service.dart'
    show NetworkException;
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/outbound_drain.dart';
import 'package:starling/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingTransport implements SyncTransport {
  final List<Envelope> sent = [];

  /// Thrown (once) by the next [pushEnvelope] call, then cleared.
  Object? nextError;

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? untilId,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async =>
      throw UnimplementedError();

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {
    sent.add(envelope);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}

Follow _follow(String pubkey) => Follow(
      pubkey: pubkey,
      connectionCard: '{}',
      feedKey: Uint8List(32),
    );

PeerConnection _peer(String pubkey) => PeerConnection(
      pubkey: pubkey,
      baseUrl: 'http://test.local',
      transport: PeerTransport.lan,
    );

/// The peer answered with an HTTP error (4xx counts toward the drop
/// threshold; 5xx is treated as transient).
NetworkException _httpError(int statusCode) =>
    NetworkException('pushEnvelope failed: $statusCode', 'alice',
        statusCode: statusCode);

void main() {
  test('empty queue: returns zeroes, no transport call', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );
    expect(result.pushed, equals(0));
    expect(result.dropped, equals(0));
    expect(transport.sent, isEmpty);
    await storage.dispose();
  });

  test('happy path: all queued blobs ship as one envelope, queue clears',
      () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    await storage.enqueue('alice', Uint8List.fromList([1, 2, 3]));
    await storage.enqueue('alice', Uint8List.fromList([4, 5, 6]));
    await storage.enqueue('bob', Uint8List.fromList([7]));

    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );

    expect(result.pushed, equals(2));
    expect(transport.sent, hasLength(1));
    expect(transport.sent.first.items, hasLength(2));

    expect(await storage.dequeue('alice'), isEmpty);
    // Bob's queue is untouched.
    expect(await storage.dequeue('bob'), hasLength(1));
    await storage.dispose();
  });

  test('4xx rejection increments retry; under threshold rows survive',
      () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport()..nextError = _httpError(401);
    await storage.enqueue('alice', Uint8List.fromList([1]));

    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );

    expect(result.pushed, equals(0));
    expect(result.retried, equals(1));
    expect(result.dropped, equals(0));
    final still = await storage.dequeue('alice');
    expect(still, hasLength(1));
    expect(still.first.retryCount, equals(1));
    await storage.dispose();
  });

  test('three 4xx rejections drop the row', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    await storage.enqueue('alice', Uint8List.fromList([1]));

    for (var i = 0; i < kOutboundMaxRetries; i++) {
      transport.nextError = _httpError(401);
      await drainOutboundQueueForPeer(
        storage: storage,
        transport: transport,
        follow: _follow('alice'),
        peer: _peer('alice'),
      );
    }
    expect(await storage.dequeue('alice'), isEmpty);
    await storage.dispose();
  });

  test(
      'transport-level failures never increment retry — rows survive '
      'arbitrarily many flaps (D9)', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    await storage.enqueue('alice', Uint8List.fromList([1]));

    for (var i = 0; i < kOutboundMaxRetries * 3; i++) {
      transport.nextError = Exception('socket closed');
      final result = await drainOutboundQueueForPeer(
        storage: storage,
        transport: transport,
        follow: _follow('alice'),
        peer: _peer('alice'),
      );
      expect(result.dropped, equals(0));
      expect(result.retried, equals(1));
    }
    final still = await storage.dequeue('alice');
    expect(still, hasLength(1));
    expect(still.first.retryCount, equals(0));
    await storage.dispose();
  });

  test('follow-accept wrappers are left for the retry pump, not shipped',
      () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    // A follow-accept wrapper { url, body } shares the queue with real
    // events keyed by the same pubkey. The drain must skip it.
    final acceptWrapper = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'url': 'http://alice.onion:80/follow-accept',
      'body': Uint8List.fromList([9, 9, 9]),
    }));
    await storage.enqueue('alice', acceptWrapper);
    await storage.enqueue('alice', Uint8List.fromList([1, 2, 3]));

    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );

    // Only the real event ships.
    expect(result.pushed, equals(1));
    expect(transport.sent, hasLength(1));
    expect(transport.sent.first.items, hasLength(1));
    expect(transport.sent.first.items.first.payload,
        equals(Uint8List.fromList([1, 2, 3])));

    // The accept wrapper survives, untouched, for the follow retry pump.
    final remaining = await storage.dequeue('alice');
    expect(remaining, hasLength(1));
    expect(remaining.single.eventBlob, equals(acceptWrapper));
    expect(remaining.single.retryCount, 0);
    await storage.dispose();
  });

  test('queue holding only accept wrappers drains as a no-op', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    final acceptWrapper = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'url': 'http://alice.onion:80/follow-accept',
      'body': Uint8List.fromList([9]),
    }));
    await storage.enqueue('alice', acceptWrapper);

    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );

    expect(result.pushed, equals(0));
    expect(transport.sent, isEmpty);
    expect(await storage.dequeue('alice'), hasLength(1));
    await storage.dispose();
  });

  test('5xx counts as transient, not a rejection', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport()..nextError = _httpError(500);
    await storage.enqueue('alice', Uint8List.fromList([1]));

    final result = await drainOutboundQueueForPeer(
      storage: storage,
      transport: transport,
      follow: _follow('alice'),
      peer: _peer('alice'),
    );

    expect(result.dropped, equals(0));
    expect(result.retried, equals(1));
    final still = await storage.dequeue('alice');
    expect(still, hasLength(1));
    expect(still.first.retryCount, equals(0));
    await storage.dispose();
  });
}
