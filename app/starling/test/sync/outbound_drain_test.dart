import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/outbound_drain.dart';
import 'package:starling/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingTransport implements SyncTransport {
  final List<Envelope> sent = [];
  bool nextThrows = false;

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
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
    if (nextThrows) {
      nextThrows = false;
      throw Exception('simulated push failure');
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

  test('failure increments retry; under threshold rows survive', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport()..nextThrows = true;
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

  test('three failures drop the row', () async {
    final storage = MockStorageService();
    final transport = _CapturingTransport();
    await storage.enqueue('alice', Uint8List.fromList([1]));

    for (var i = 0; i < kOutboundMaxRetries; i++) {
      transport.nextThrows = true;
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
}
