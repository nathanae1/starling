import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/mocks/mock_clock.dart';
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

  /// When > 0, the next N [pushEvents] calls 507 (cap exhausted).
  int pushEvents507s = 0;

  /// Receipt-level rejections per batch (A5: malformed items the relay
  /// refuses while still answering 202).
  int rejectedPerBatch = 0;

  /// Recorded delete batches, in call order.
  final List<List<String>> deletedEventBatches = [];
  final List<List<String>> deletedMediaBatches = [];
  Object? deleteEventsError;
  Object? deleteMediaError;

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
    if (pushEvents507s > 0) {
      pushEvents507s--;
      throw RelayPushException('simulated cap 507', statusCode: 507);
    }
    final err = pushEventsError;
    if (err != null) {
      pushEventsError = null;
      throw err;
    }
    pushedBatches.add(items);
    return RelayPushReceipt(
      accepted: items.length - rejectedPerBatch,
      rejected: rejectedPerBatch,
    );
  }

  @override
  Future<void> unpairRelay({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
  }) async {}

  @override
  Future<RelayDeleteReceipt> deleteEvents({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return const RelayDeleteReceipt(deleted: 0, missing: 0);
    final err = deleteEventsError;
    if (err != null) {
      deleteEventsError = null;
      throw err;
    }
    deletedEventBatches.add(List.of(ids));
    return RelayDeleteReceipt(deleted: ids.length, missing: 0);
  }

  @override
  Future<RelayDeleteReceipt> deleteMedia({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<String> hashes,
  }) async {
    if (hashes.isEmpty) return const RelayDeleteReceipt(deleted: 0, missing: 0);
    final err = deleteMediaError;
    if (err != null) {
      deleteMediaError = null;
      throw err;
    }
    deletedMediaBatches.add(List.of(hashes));
    return RelayDeleteReceipt(deleted: hashes.length, missing: 0);
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
    return mediaManifestPages[idx < mediaManifestPages.length
        ? idx
        : mediaManifestPages.length - 1];
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
  final ownPubkey = crockfordBase32Encode(
    Uint8List.fromList(List.filled(32, 7)),
  );

  late _CountingStorage storage;
  late _FakePushService push;

  /// `/manifest` pages served by the raw-HTTP client, recorded with their
  /// query params.
  late List<Map<String, dynamic>> manifestPages;
  late List<Map<String, String>> manifestRequests;
  int manifestStatus = 200;

  Event event(
    String id,
    int createdAt, {
    List<MediaRef> media = const [],
    EventKind kind = EventKind.post,
    String? ref,
  }) => Event(
    version: kStarlingProtocolVersion,
    id: id,
    pubkey: ownPubkey,
    createdAt: createdAt,
    kind: kind,
    ref: ref,
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

  Future<void> saveOwnEvent(
    String id,
    int createdAt, {
    List<MediaRef> media = const [],
    EventKind kind = EventKind.post,
    String? ref,
  }) async {
    await storage.saveOwnEventWithEncrypted(
      event(id, createdAt, media: media, kind: kind, ref: ref),
      wireBytes(id, createdAt),
    );
  }

  RelayPushCoordinator coordinator({
    Future<Uint8List?> Function(String hash)? mediaBytesLookup,
    Clock? clock,
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
      clock: clock ?? MockClock(),
    );
  }

  Map<String, dynamic> manifestPage(
    List<Event> events, {
    required bool hasOlder,
  }) => <String, dynamic>{
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
    manifestPages = [manifestPage(const [], hasOlder: false)];
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

  test(
    'pages the relay manifest to completion via until/until_id (D7)',
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
    },
  );

  test(
    'only events past the first page are recognized (D7 regression)',
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
    },
  );

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

  test('convergence flips backfillComplete; an event-push failure leaves it '
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

  test('one media failure does not strand the rest, but blocks '
      'backfillComplete until it heals (D8 + D2c)', () async {
    await saveOwnEvent(
      'e1',
      100,
      media: const [
        MediaRef(hash: 'aaa', mimeType: 'image/jpeg', size: 3),
        MediaRef(hash: 'bbb', mimeType: 'image/jpeg', size: 3),
      ],
    );
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
    await saveOwnEvent(
      'e1',
      100,
      media: const [
        MediaRef(hash: 'aaa', mimeType: 'image/jpeg', size: 3),
        MediaRef(hash: 'bbb', mimeType: 'image/jpeg', size: 3),
      ],
    );
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    push.mediaManifestPages = const [
      RelayMediaManifestPage(hashes: ['aaa'], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.pushedMedia, ['bbb']);
  });

  test(
    'media manifest pages with the last hash as the after cursor (D8)',
    () async {
      await saveOwnEvent(
        'e1',
        100,
        media: const [MediaRef(hash: 'ccc', mimeType: 'image/jpeg', size: 3)],
      );
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
    },
  );

  test('unreachable relay manifest → no pushes, flag untouched', () async {
    await saveOwnEvent('e1', 100);
    manifestStatus = 503;

    await coordinator().reconcile();

    expect(push.pushedBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);
  });

  test(
    'media blobs missing on disk are skipped, not counted as failures',
    () async {
      await saveOwnEvent(
        'e1',
        100,
        media: const [MediaRef(hash: 'gone', mimeType: 'image/jpeg', size: 3)],
      );
      manifestPages = [
        manifestPage([event('e1', 100)], hasOlder: false),
      ];

      await coordinator(mediaBytesLookup: (hash) async => null).reconcile();

      expect(push.pushedMedia, isEmpty);
      // A blob we can never produce must not block convergence forever.
      expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
    },
  );

  test('pushPublished pushes the event and its media', () async {
    final e = event(
      'fresh',
      500,
      media: const [MediaRef(hash: 'mmm', mimeType: 'image/jpeg', size: 3)],
    );

    await coordinator().pushPublished(e, wireBytes('fresh', 500));

    expect(push.pushedBatches, hasLength(1));
    expect(push.pushedBatches.single.single.id, 'fresh');
    expect(push.pushedMedia, ['mmm']);
  });

  // --- Phase 3: deletion & retention ---

  test('pushPublished of a tombstone withdraws its target and the target\'s '
      'exclusive media; shared media survives', () async {
    // Target references two hashes; a LIVE sibling still references
    // "shared", so only "only" is exclusively dead.
    await saveOwnEvent(
      'target',
      100,
      media: const [
        MediaRef(hash: 'shared', mimeType: 'image/jpeg', size: 3),
        MediaRef(hash: 'only', mimeType: 'image/jpeg', size: 3),
      ],
    );
    await saveOwnEvent(
      'sibling',
      150,
      media: const [MediaRef(hash: 'shared', mimeType: 'image/jpeg', size: 3)],
    );
    await saveOwnEvent('tomb', 200, kind: EventKind.delete, ref: 'target');

    await coordinator().pushPublished(
      event('tomb', 200, kind: EventKind.delete, ref: 'target'),
      wireBytes('tomb', 200),
    );

    // Tombstone itself was pushed…
    expect(push.pushedBatches.single.single.id, 'tomb');
    // …the target withdrawn, and only the exclusive hash deleted.
    expect(push.deletedEventBatches, [
      ['target'],
    ]);
    expect(push.deletedMediaBatches, [
      ['only'],
    ]);
  });

  test('reconcile withdraws tombstoned events still present on the relay '
      'and never re-pushes them', () async {
    await saveOwnEvent('e1', 100);
    await saveOwnEvent('t1', 200, kind: EventKind.delete, ref: 'e1');
    manifestPages = [
      manifestPage([event('e1', 100), event('t1', 200)], hasOlder: false),
    ];

    await coordinator().reconcile();

    // The dead target is deleted, nothing is pushed (the tombstone is
    // already present), convergence is reached.
    expect(push.deletedEventBatches, [
      ['e1'],
    ]);
    expect(push.pushedBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('reconcile never deletes un-tombstoned relay-extras (restored-phone '
      'protection)', () async {
    // The relay holds an id the phone has no row and no tombstone for —
    // e.g. after a recovery-phrase restore. It must survive.
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100), event('ghost', 50)], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.deletedEventBatches, isEmpty);
    expect(push.deletedMediaBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('reconcile deletes dead-only media but keeps hashes any live event '
      'references', () async {
    await saveOwnEvent(
      'dead',
      100,
      media: const [
        MediaRef(hash: 'shared', mimeType: 'image/jpeg', size: 3),
        MediaRef(hash: 'only', mimeType: 'image/jpeg', size: 3),
      ],
    );
    await saveOwnEvent(
      'live',
      150,
      media: const [MediaRef(hash: 'shared', mimeType: 'image/jpeg', size: 3)],
    );
    await saveOwnEvent('t1', 200, kind: EventKind.delete, ref: 'dead');
    manifestPages = [
      manifestPage([
        event('dead', 100),
        event('live', 150),
        event('t1', 200),
      ], hasOlder: false),
    ];
    push.mediaManifestPages = const [
      RelayMediaManifestPage(hashes: ['only', 'shared'], hasOlder: false),
    ];

    await coordinator().reconcile();

    expect(push.deletedEventBatches, [
      ['dead'],
    ]);
    expect(push.deletedMediaBatches, [
      ['only'],
    ]);
    expect(push.pushedMedia, isEmpty);
  });

  test('a failing delete blocks backfillComplete until it heals', () async {
    await saveOwnEvent('e1', 100);
    await saveOwnEvent('t1', 200, kind: EventKind.delete, ref: 'e1');
    manifestPages = [
      manifestPage([event('e1', 100), event('t1', 200)], hasOlder: false),
    ];

    push.deleteEventsError = RelayPushException('tor flap', statusCode: 500);
    final coord = coordinator();
    await coord.reconcile();
    // The relay still serves a deleted post — NOT converged.
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);

    // Error cleared → next pass withdraws it and converges.
    await coord.reconcile();
    expect(push.deletedEventBatches, [
      ['e1'],
    ]);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('prune-on-507 persists the horizon BEFORE deleting, prunes oldest '
      'posts only, and retries the push once', () async {
    // p1/p2 already on the relay; pNew doesn't fit (507). All payloads are
    // equal-sized, so 2× the needed bytes ≈ two old posts.
    await saveOwnEvent('p1', 100);
    await saveOwnEvent('p2', 200);
    await saveOwnEvent('profile', 50, kind: EventKind.profile);
    await saveOwnEvent('pNew', 300);
    manifestPages = [
      manifestPage([
        event('p1', 100),
        event('p2', 200),
        event('profile', 50),
      ], hasOlder: false),
    ];
    push.pushEvents507s = 1;

    await coordinator().reconcile();

    // Horizon = newestPruned.createdAt + 1, persisted.
    final relay = (await storage.getPairedRelay())!;
    expect(relay.relayPruneBefore, 201);
    // The two oldest POSTS were withdrawn — never the (older) profile.
    expect(push.deletedEventBatches, [
      ['p1', 'p2'],
    ]);
    // The retry landed the new post.
    expect(push.pushedBatches, hasLength(1));
    expect(push.pushedBatches.single.map((i) => i.id), ['pNew']);
    expect(relay.backfillComplete, isTrue);
  });

  test('crash-safe ordering: the horizon is persisted even when the prune '
      'deletes fail', () async {
    await saveOwnEvent('p1', 100);
    await saveOwnEvent('pNew', 300);
    manifestPages = [
      manifestPage([event('p1', 100)], hasOlder: false),
    ];
    push.pushEvents507s = 1;
    push.deleteEventsError = RelayPushException('died mid-prune');

    await coordinator().reconcile();

    // The delete never landed, but the horizon is already durable — the
    // next pass re-derives the same pruned set instead of re-pushing p1.
    expect((await storage.getPairedRelay())!.relayPruneBefore, 101);
    expect(push.pushedBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);
  });

  test('a second 507 (host cap) gives up the pass without looping', () async {
    await saveOwnEvent('p1', 100);
    await saveOwnEvent('pNew', 300);
    manifestPages = [
      manifestPage([event('p1', 100)], hasOlder: false),
    ];
    push.pushEvents507s = 2;

    await coordinator().reconcile();

    // One prune attempt, no push landed, flag stays down.
    expect(push.deletedEventBatches, hasLength(1));
    expect(push.pushedBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isFalse);
  });

  test('a persisted prune horizon keeps sub-horizon posts off the relay on '
      'later passes', () async {
    await saveOwnEvent('old', 100);
    await saveOwnEvent('new', 300);
    await storage.setRelayPruneBefore('relay-1', 250);

    await coordinator().reconcile();

    // Only the post above the horizon is pushed; the pruned one stays
    // local-only and is never deleted (it's already absent).
    expect(push.pushedBatches.single.map((i) => i.id), ['new']);
    expect(push.deletedEventBatches, isEmpty);
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);
  });

  test('overlapping reconciles are skipped by the in-flight guard (A4)',
      () async {
    await saveOwnEvent('e1', 100);
    final coord = coordinator();

    await Future.wait([coord.reconcile(), coord.reconcile()]);

    // Only one pass ran: one manifest walk, one push of the missing event.
    expect(manifestRequests, hasLength(1));
    expect(push.pushedBatches, hasLength(1));
  });

  test('a converged pass short-circuits the next reconcile until local '
      'state changes (A4)', () async {
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    final coord = coordinator();

    await coord.reconcile();
    expect(manifestRequests, hasLength(1));

    // Converged + no local change + inside the cooldown → no Tor traffic.
    await coord.reconcile();
    expect(manifestRequests, hasLength(1), reason: 'second pass skipped');

    // A new local event breaks the signature → the next pass runs in full.
    await saveOwnEvent('e2', 200);
    await coord.reconcile();
    expect(manifestRequests, hasLength(2));
    expect(push.pushedBatches.single.map((i) => i.id), ['e2']);
  });

  test('the cooldown lapsing re-runs a full pass even when nothing local '
      'changed (A4)', () async {
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    final clock = MockClock();
    final coord = coordinator(clock: clock);

    await coord.reconcile();
    await coord.reconcile();
    expect(manifestRequests, hasLength(1));

    clock.advance(kReconcileCooldown.inSeconds);
    await coord.reconcile();
    expect(manifestRequests, hasLength(2), reason: 'cooldown lapsed');
  });

  test('backfill() always runs in full — pair-time backfill must not be '
      'short-circuited (A4)', () async {
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    final coord = coordinator();
    await coord.reconcile();
    await coord.backfill();
    expect(manifestRequests, hasLength(2));
  });

  test('receipt rejections block convergence and un-flip a stale '
      'backfillComplete (A5)', () async {
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    final coord = coordinator();
    await coord.reconcile();
    expect((await storage.getPairedRelay())!.backfillComplete, isTrue);

    // A later pass pushes a new event the relay rejects: the flag clears
    // and stays down until the divergence is resolved.
    await saveOwnEvent('e2', 200);
    push.rejectedPerBatch = 1;
    await coord.reconcile();
    final relay = (await storage.getPairedRelay())!;
    expect(relay.backfillComplete, isFalse);
    expect(relay.lastError, contains('1 rejected'));
  });

  test('a converged pass records lastPushAt and clears lastError; an '
      'unreachable relay records the error WITHOUT un-flipping the flag '
      '(A7 + A5)', () async {
    await saveOwnEvent('e1', 100);
    manifestPages = [
      manifestPage([event('e1', 100)], hasOlder: false),
    ];
    final clock = MockClock(5000);
    final coord = coordinator(clock: clock);
    await coord.reconcile();
    var relay = (await storage.getPairedRelay())!;
    expect(relay.backfillComplete, isTrue);
    expect(relay.lastPushAt, 5000);
    expect(relay.lastError, isNull);

    // Relay unreachable: error surfaced, convergence state untouched.
    await saveOwnEvent('e2', 200); // break the short-circuit signature
    manifestStatus = 503;
    await coord.reconcile();
    relay = (await storage.getPairedRelay())!;
    expect(relay.backfillComplete, isTrue, reason: 'not divergence');
    expect(relay.lastError, contains('unreachable'));
    expect(relay.lastPushAt, 5000);

    // Reachable again → error clears, lastPushAt freshens.
    manifestStatus = 200;
    manifestPages = [
      manifestPage([event('e1', 100), event('e2', 200)], hasOlder: false),
    ];
    clock.advance(60);
    await coord.reconcile();
    relay = (await storage.getPairedRelay())!;
    expect(relay.lastError, isNull);
    expect(relay.lastPushAt, 5060);
  });
}
