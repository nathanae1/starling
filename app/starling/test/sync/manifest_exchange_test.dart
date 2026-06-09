import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/manifest_exchange.dart';
import 'package:starling/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns only the manifest IDs we don\'t already have', () async {
    final storage = MockStorageService();

    // Seed three local events for pubkey "alice".
    final clock = MockClock(1_000_000);
    for (var i = 0; i < 3; i++) {
      await storage.saveEvent(_event(
        id: 'id-$i',
        pubkey: 'alice',
        createdAt: clock.nowUnixSeconds() + i,
      ));
    }

    final transport = _StaticTransport(const Manifest(
      pubkey: 'alice',
      events: [
        ManifestEntry(id: 'id-0', createdAt: 1_000_000),
        ManifestEntry(id: 'id-1', createdAt: 1_000_001),
        ManifestEntry(id: 'id-2', createdAt: 1_000_002),
        ManifestEntry(id: 'id-3', createdAt: 1_000_003),
        ManifestEntry(id: 'id-4', createdAt: 1_000_004),
      ],
      hasOlder: false,
    ));

    final exchange = ManifestExchange(transport: transport, storage: storage);
    final diff = await exchange.fetchAndDiff(
      const PeerConnection(
        pubkey: 'alice',
        baseUrl: 'http://x',
        transport: PeerTransport.lan,
      ),
      Follow(
        pubkey: 'alice',
        connectionCard: '',
        feedKey: Uint8List(32),
        lastSyncedAt: 0,
      ),
    );

    expect(diff.missingIds, equals(const ['id-3', 'id-4']));
    expect(diff.peerEvents, hasLength(5));
  });

  test('drops manifest if peer\'s pubkey doesn\'t match the follow\'s pubkey',
      () async {
    final storage = MockStorageService();
    final transport = _StaticTransport(const Manifest(
      pubkey: 'eve',
      events: [
        ManifestEntry(id: 'id-evil', createdAt: 1),
      ],
      hasOlder: false,
    ));

    final exchange = ManifestExchange(transport: transport, storage: storage);
    final diff = await exchange.fetchAndDiff(
      const PeerConnection(
        pubkey: 'alice',
        baseUrl: 'http://x',
        transport: PeerTransport.lan,
      ),
      Follow(
        pubkey: 'alice',
        connectionCard: '',
        feedKey: Uint8List(32),
        lastSyncedAt: 0,
      ),
    );

    expect(diff.missingIds, isEmpty);
  });
}

Event _event({
  required String id,
  required String pubkey,
  required int createdAt,
}) =>
    Event(
      version: '2026-03-24',
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: EventKind.post,
      content: Uint8List(0),
      sig: Uint8List(64),
    );

class _StaticTransport implements SyncTransport {
  _StaticTransport(this._manifest);
  final Manifest _manifest;

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  }) async =>
      _manifest;

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) async =>
      const Envelope(version: '2026-03-24', items: []);

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async =>
      Uint8List(0);

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {}
}
