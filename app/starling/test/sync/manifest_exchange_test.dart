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
      await storage.saveEvent(
        _event(
          id: 'id-$i',
          pubkey: 'alice',
          createdAt: clock.nowUnixSeconds() + i,
        ),
      );
    }

    final transport = _StaticTransport(
      const Manifest(
        pubkey: 'alice',
        events: [
          ManifestEntry(id: 'id-0', createdAt: 1_000_000),
          ManifestEntry(id: 'id-1', createdAt: 1_000_001),
          ManifestEntry(id: 'id-2', createdAt: 1_000_002),
          ManifestEntry(id: 'id-3', createdAt: 1_000_003),
          ManifestEntry(id: 'id-4', createdAt: 1_000_004),
        ],
        hasOlder: false,
      ),
    );

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

  test(
    'drops manifest if peer\'s pubkey doesn\'t match the follow\'s pubkey',
    () async {
      final storage = MockStorageService();
      final transport = _StaticTransport(
        const Manifest(
          pubkey: 'eve',
          events: [ManifestEntry(id: 'id-evil', createdAt: 1)],
          hasOlder: false,
        ),
      );

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
    },
  );

  test(
    'fetchAndDiff reports maxCreatedAt and hasOlder from the manifest',
    () async {
      final storage = MockStorageService();
      final transport = _StaticTransport(
        const Manifest(
          pubkey: 'alice',
          events: [
            ManifestEntry(id: 'id-1', createdAt: 1_000_005),
            ManifestEntry(id: 'id-0', createdAt: 1_000_001),
          ],
          hasOlder: true,
        ),
      );

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

      expect(diff.maxCreatedAt, equals(1_000_005));
      expect(diff.hasOlder, isTrue);
    },
  );

  test('fetchAndDiffFull pages with until/until_id to completion and diffs '
      'against all local ids (D1/D7)', () async {
    final storage = MockStorageService();
    // Local store already holds id-2; id-1 and id-3 are missing.
    await storage.saveEvent(
      _event(id: 'id-2', pubkey: 'alice', createdAt: 200),
    );

    final transport = _PagingTransport([
      Manifest(
        pubkey: 'alice',
        events: const [
          ManifestEntry(id: 'id-3', createdAt: 300),
          ManifestEntry(id: 'id-2', createdAt: 200),
        ],
        hasOlder: true,
        newFeedKey: SealedDelivery(
          payload: Uint8List(0),
          nonce: Uint8List(0),
          createdAt: 5000,
        ),
      ),
      const Manifest(
        pubkey: 'alice',
        events: [ManifestEntry(id: 'id-1', createdAt: 100)],
        hasOlder: false,
      ),
    ]);

    final exchange = ManifestExchange(transport: transport, storage: storage);
    final diff = await exchange.fetchAndDiffFull(
      const PeerConnection(
        pubkey: 'alice',
        baseUrl: 'http://x',
        transport: PeerTransport.lan,
      ),
      Follow(
        pubkey: 'alice',
        connectionCard: '',
        feedKey: Uint8List(32),
        lastSyncedAt: 999_999, // a full diff ignores the windowed cursor
      ),
      requesterPubkey: 'bob',
      ackRotationAt: 42,
    );

    // Page 2 was cursored on page 1's oldest entry.
    expect(transport.calls, hasLength(2));
    expect(transport.calls[0].until, isNull);
    expect(transport.calls[1].until, equals(200));
    expect(transport.calls[1].untilId, equals('id-2'));
    // Acks ride the first page only.
    expect(transport.calls[0].requesterPubkey, equals('bob'));
    expect(transport.calls[0].ackRotationAt, equals(42));
    expect(transport.calls[1].requesterPubkey, isNull);
    expect(transport.calls[1].ackRotationAt, isNull);

    expect(diff.missingIds, equals(const ['id-3', 'id-1']));
    // Envelope fetch window = the oldest MISSING entry, not the oldest
    // entry overall.
    expect(diff.windowSince, equals(100));
    expect(diff.maxCreatedAt, equals(300));
    expect(diff.hasOlder, isFalse);
    // First-page deliveries are carried through.
    expect(diff.newFeedKey?.createdAt, equals(5000));
  });
}

Event _event({
  required String id,
  required String pubkey,
  required int createdAt,
}) => Event(
  version: '2026-03-24',
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: EventKind.post,
  content: Uint8List(0),
  sig: Uint8List(64),
);

/// One recorded fetchManifest invocation.
class _ManifestCall {
  const _ManifestCall({
    this.since,
    this.until,
    this.untilId,
    this.requesterPubkey,
    this.ackRotationAt,
  });
  final int? since;
  final int? until;
  final String? untilId;
  final String? requesterPubkey;
  final int? ackRotationAt;
}

/// Serves scripted manifest pages in order (last page repeats) and records
/// every call's paging/ack params.
class _PagingTransport implements SyncTransport {
  _PagingTransport(this._pages);
  final List<Manifest> _pages;
  final List<_ManifestCall> calls = [];

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
  }) async {
    calls.add(
      _ManifestCall(
        since: since,
        until: until,
        untilId: untilId,
        requesterPubkey: requesterPubkey,
        ackRotationAt: ackRotationAt,
      ),
    );
    final idx = calls.length - 1;
    return _pages[idx < _pages.length ? idx : _pages.length - 1];
  }

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) async =>
      const Envelope(version: '2026-03-24', items: []);

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async =>
      Uint8List(0);

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {}
}

class _StaticTransport implements SyncTransport {
  _StaticTransport(this._manifest);
  final Manifest _manifest;

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
  }) async => _manifest;

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) async =>
      const Envelope(version: '2026-03-24', items: []);

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async =>
      Uint8List(0);

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {}
}
