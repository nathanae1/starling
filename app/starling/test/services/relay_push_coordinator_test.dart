import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/relay_push_coordinator.dart';
import 'package:starling/services/relay_push_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records pushes; never signs or talks HTTP (that's RelayPushService's
/// own test's job).
class _FakePushService implements RelayPushService {
  final List<List<RelayPushItem>> pushedBatches = [];
  final List<String> pushedMedia = [];
  final Set<String> failMediaHashes = {};
  Object? pushEventsError;

  /// Scripted `/media-manifest` pages, consumed in order (last one
  /// repeats). Recorded `after` cursors land in [mediaManifestAfters].
  List<RelayMediaManifestPage> mediaManifestPages = const [
    RelayMediaManifestPage(hashes: [], hasOlder: false),
  ];
  final List<String?> mediaManifestAfters = [];
  Object? mediaManifestError;

  @override
  Future<RelayPushReceipt> pushEvents({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<RelayPushItem> items,
  }) async {
    final err = pushEventsError;
    if (err != null) {
      pushEventsError = null;
      throw err;
    }
    pushedBatches.add(items);
    return RelayPushReceipt(accepted: items.length, rejected: 0);
  }

  @override
  Future<void> pushMedia({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required String hash,
    required Uint8List blob,
  }) async {
    if (failMediaHashes.contains(hash)) {
      throw RelayPushException('simulated media failure for $hash');
    }
    pushedMedia.add(hash);
  }

  @override
  Future<RelayMediaManifestPage> fetchMediaManifest({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    String? after,
  }) async {
    final err = mediaManifestError;
    if (err != null) {
      mediaManifestError = null;
      throw err;
    }
    mediaManifestAfters.add(after);
    final idx = mediaManifestAfters.length - 1;
    return mediaManifestPages[
        idx < mediaManifestPages.length ? idx : mediaManifestPages.length - 1];
  }
}

class _CountingStorage extends MockStorageService {
  int payloadLoads = 0;

  @override
  Future<Uint8List?> getEncryptedPayload(String id) {
    payloadLoads++;
    return super.getEncryptedPayload(id);
  }
}

void main() {
  final ownPubkey =
      crockfordBase32Encode(Uint8List.fromList(List.filled(32, 7)));

  late _CountingStorage storage;
  late _FakePushService push;

  /// `/manifest` pages served by the raw-HTTP client, recorded with their
  /// query params.
  late List<Map<String, dynamic>> manifestPages;
  late List<Map<String, String>> manifestRequests;
  int manifestStatus = 200;

  Event event(String id, int createdAt, {List<MediaRef> media = const []}) =>
      Event(
        version: kStarlingProtocolVersion,
        id: id,
        pubkey: ownPubkey,
        createdAt: createdAt,
        kind: EventKind.post,
        content: Uint8List.fromList('post $id'.codeUnits),
        sig: Uint8List(64),
        media: media,
      );

  Uint8List wireBytes(String id, int createdAt, {int payloadLen = 16}) =>
      EncryptedEvent(
        pubkey: ownPubkey,
        createdAt: createdAt,
        epoch: 0,
        msgSeq: 0,
        nonce: Uint8List(24),
        payload: Uint8List.fromList(List.filled(payloadLen, 0x42)),
      ).toBytes();

  Future<void> saveOwnEvent(String id, int createdAt,
      {List<MediaRef> media = const []}) async {
    await storage.saveOwnEventWithEncrypted(
      event(id, createdAt, media: media),
      wireBytes(id, createdAt),
    );
  }

  RelayPushCoordinator coordinator({
    Future<Uint8List?> Function(String hash)? mediaBytesLookup,
  }) {
    final client = MockClient((request) async {
      if (request.url.path != '/manifest') {
        return http.Response('not found', 404);
      }
      manifestRequests.add(Map.of(request.url.queryParameters));
      if (manifestStatus != 200) {
        return http.Response('boom', manifestStatus);
      }
      final page = manifestPages.length > manifestRequests.length - 1
          ? manifestPages[manifestRequests.length - 1]
          : manifestPages.last;
      return http.Response.bytes(
        cbor.encode(page),
        200,
        headers: {'content-type': 'application/cbor'},
      );
    });
    return RelayPushCoordinator(
      pushService: push,
      storage: storage,
      relayClient: client,
      identityLookup: () async => Identity(
        pubkey: ownPubkey,
        feedKey: Uint8List(32),
        feedKeyEpoch: 0,
        createdAt: 1000,
      ),
      ownSecretKeyLookup: () async => Uint8List(64),
      mediaBytesLookup:
          mediaBytesLookup ?? (hash) async => Uint8List.fromList([1, 2, 3]),
    );
  }

  Map<String, dynamic> manifestPage(List<Event> events,
          {required bool hasOlder}) =>
      <String, dynamic>{
        'pubkey': ownPubkey,
        'events': [
          for (final e in events)
            <String, dynamic>{'id': e.id, 'created_at': e.createdAt},
        ],
        'has_older': hasOlder,
      };

  setUp(() async {
    storage = _CountingStorage();
    push = _FakePushService();
    manifestPages = [
      manifestPage(const [], hasOlder: false),
    ];
    manifestRequests = [];
    manifestStatus = 200;
    await storage.setPairedRelay(
      relayId: 'relay-1',
      relayOnion: 'relayhost.onion:80',
      pairedAt: 1000,
    );
  });

  tearDown(() async {
    await storage.dispose();
  });

  test('pages the relay manifest to completion via until/until_id (D7)',
      () async {
    // Relay already holds e1..e3 split across two pages; local store has
    // the same three events → nothing to push.
    final e1 = event('e1', 300);
    final e2 = event('e2', 200);
    final e3 = event('e3', 100);
    for (final e in [e1, e2, e3]) {
      await saveOwnEvent(e.id, e.createdAt);
    }
    manifestPages = [
      manifestPage([e1, e2], hasOlder: true),
      manifestPage([e3], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(manifestRequests, hasLength(2));
    expect(manifestRequests.first, isEmpty);
    // Second page is keyset-cursored on the first page's oldest entry.
    expect(manifestRequests[1]['until'], '200');
    expect(manifestRequests[1]['until_id'], 'e2');
    // All ids were collected → nothing pushed, no payload bytes loaded.
    expect(push.pushedBatches, isEmpty);
    expect(storage.payloadLoads, 0);
  });

  test('only events past the first page are recognized (D7 regression)',
      () async {
    // 2 events on the relay across 2 pages; local store holds both plus
    // one genuinely missing. Only the missing one is pushed.
    final e1 = event('e1', 300);
    final e2 = event('e2', 200);
    final eNew = event('eNew', 400);
    for (final e in [e1, e2, eNew]) {
      await saveOwnEvent(e.id, e.createdAt);
    }
    manifestPages = [
      manifestPage([e1], hasOlder: true),
      manifestPage([e2], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.pushedBatches, hasLength(1));
    expect(push.pushedBatches.single.map((i) => i.id), ['eNew']);
    expect(storage.payloadLoads, 1);
  });

  test('missing events are pushed in bounded chunks (D2a)', () async {
    for (var i = 0; i < 250; i++) {
      await saveOwnEvent('e$i', 1000 + i);
    }

    await coordinator().reconcile();

    expect(push.pushedBatches, hasLength(3));
    expect(push.pushedBatches.map((b) => b.length), [100, 100, 50]);
    final pushedIds = push.pushedBatches.expand((b) => b.map((i) => i.id));
    expect(pushedIds.toSet(), hasLength(250));
  });

  test(
      'convergence flips backfillComplete; an event-push failure leaves it '
      'unset (D2c)', () async {
    await saveOwnEvent('e1', 100);

    // First pass: push fails mid-flight → still "syncing".
    push.pushEventsError = RelayPushException('tor flap');
    final coord = coordinator();
    await coord.backfill();
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);

    // Next reconcile heals and flips the flag (D2's stranded-state fix).
    await coord.reconcile();
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
    expect(push.pushedBatches, hasLength(1));
  });

  test(
      'one media failure does not strand the rest, but blocks '
      'backfillComplete until it heals (D8 + D2c)', () async {
    await saveOwnEvent('e1', 100, media: const [
      MediaRef(hash: 'aaa', mimeType: 'image/jpeg', size: 3),
      MediaRef(hash: 'bbb', mimeType: 'image/jpeg', size: 3),
    ]);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    push.failMediaHashes.add('aaa');

    final coord = coordinator();
    await coord.reconcile();

    // bbb shipped despite aaa failing; the flag stays down.
    expect(push.pushedMedia, ['bbb']);
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);

    // aaa heals → re-pushed (bbb now present on the relay) → converged.
    push.failMediaHashes.clear();
    push.mediaManifestPages = const [
      RelayMediaManifestPage(hashes: ['bbb'], hasOlder: false),
    ];
    await coord.reconcile();
    expect(push.pushedMedia, ['bbb', 'aaa']);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('media already on the relay is not re-pushed (D8)', () async {
    await saveOwnEvent('e1', 100, media: const [
      MediaRef(hash: 'aaa', mimeType: 'image/jpeg', size: 3),
      MediaRef(hash: 'bbb', mimeType: 'image/jpeg', size: 3),
    ]);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    push.mediaManifestPages = const [
      RelayMediaManifestPage(hashes: ['aaa'], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.pushedMedia, ['bbb']);
  });

  test('media manifest pages with the last hash as the after cursor (D8)',
      () async {
    await saveOwnEvent('e1', 100, media: const [
      MediaRef(hash: 'ccc', mimeType: 'image/jpeg', size: 3),
    ]);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    push.mediaManifestPages = const [
      RelayMediaManifestPage(hashes: ['aaa', 'bbb'], hasOlder: true),
      RelayMediaManifestPage(hashes: ['ccc'], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.mediaManifestAfters, [null, 'bbb']);
    // ccc is on the relay (page 2) → nothing pushed.
    expect(push.pushedMedia, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('unreachable relay manifest → no pushes, flag untouched', () async {
    await saveOwnEvent('e1', 100);
    manifestStatus = 503;

    await coordinator().reconcile();

    expect(push.pushedBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);
  });

  test('media blobs missing on disk are skipped, not counted as failures',
      () async {
    await saveOwnEvent('e1', 100, media: const [
      MediaRef(hash: 'gone', mimeType: 'image/jpeg', size: 3),
    ]);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];

    await coordinator(mediaBytesLookup: (hash) async => null).reconcile();

    expect(push.pushedMedia, isEmpty);
    // A blob we can never produce must not block convergence forever.
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('pushPublished pushes the event and its media', () async {
    final e = event('fresh', 500, media: const [
      MediaRef(hash: 'mmm', mimeType: 'image/jpeg', size: 3),
    ]);

    await coordinator().pushPublished(e, wireBytes('fresh', 500));

    expect(push.pushedBatches, hasLength(1));
    expect(push.pushedBatches.single.single.id, 'fresh');
    expect(push.pushedMedia, ['mmm']);
  });
}
