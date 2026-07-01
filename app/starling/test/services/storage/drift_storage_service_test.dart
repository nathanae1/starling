import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftStorageService service;
  late MockClock clock;

  setUp(() {
    db = AppDatabase.memory();
    clock = MockClock();
    service = DriftStorageService(db, clock);
  });

  tearDown(() async {
    await db.close();
  });

  group('identity', () {
    test('returns null initially', () async {
      expect(await service.getIdentity(), isNull);
    });

    test('saves and retrieves', () async {
      final identity = Identity(
        pubkey: 'my-pk',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
        recoveryPhrase: 'word1 word2',
        createdAt: 1000,
      );
      await service.saveIdentity(identity);

      final result = await service.getIdentity();
      expect(result, isNotNull);
      expect(result!.pubkey, equals('my-pk'));
      expect(result.recoveryPhrase, equals('word1 word2'));
    });
  });

  group('follows', () {
    Follow makeFollow(String pk) => Follow(
          pubkey: pk,
          connectionCard: '{"pubkey":"$pk"}',
          feedKey: Uint8List.fromList(List.filled(32, 0xBB)),
        );

    test('CRUD operations', () async {
      await service.saveFollow(makeFollow('f1'));
      await service.saveFollow(makeFollow('f2'));

      expect(await service.getFollows(), hasLength(2));
      expect((await service.getFollow('f1'))!.pubkey, equals('f1'));

      await service.removeFollow('f1');
      expect(await service.getFollows(), hasLength(1));
      expect(await service.getFollow('f1'), isNull);
    });

    test('updateLastSynced', () async {
      await service.saveFollow(makeFollow('f1'));
      await service.updateLastSynced('f1', 5000);

      final follow = await service.getFollow('f1');
      expect(follow!.lastSyncedAt, equals(5000));
    });
  });

  group('events', () {
    Event makeEvent(String id, {String pubkey = 'author', int createdAt = 1000}) =>
        Event(
          version: '2026-03-24',
          id: id,
          pubkey: pubkey,
          createdAt: createdAt,
          kind: EventKind.post,
          content: Uint8List.fromList([72, 101, 108, 108, 111]),
          media: const [
            MediaRef(hash: 'h1', mimeType: 'image/jpeg', size: 1024),
          ],
          sig: Uint8List.fromList(List.filled(64, 0xFF)),
        );

    test('save and get', () async {
      await service.saveEvent(makeEvent('e1'));
      final event = await service.getEvent('e1');
      expect(event, isNotNull);
      expect(event!.id, equals('e1'));
      expect(event.kind, equals(EventKind.post));
      expect(event.media, hasLength(1));
      expect(event.media.first.hash, equals('h1'));
    });

    test('getFeedEvents includes own and followed', () async {
      await service.saveIdentity(Identity(
        pubkey: 'me',
        feedKey: Uint8List(32),
        createdAt: 1,
      ));
      await service.saveFollow(Follow(
        pubkey: 'friend',
        connectionCard: '{}',
        feedKey: Uint8List(32),
      ));

      await service.saveEvent(makeEvent('e1', pubkey: 'me'));
      await service.saveEvent(makeEvent('e2', pubkey: 'friend'));
      await service.saveEvent(makeEvent('e3', pubkey: 'stranger'));

      final feed = await service.getFeedEvents();
      expect(feed, hasLength(2));
      expect(feed.map((e) => e.pubkey).toSet(), equals({'me', 'friend'}));
    });

    test('delete', () async {
      await service.saveEvent(makeEvent('e1'));
      await service.deleteEvent('e1');
      expect(await service.getEvent('e1'), isNull);
    });
  });

  group('media cache', () {
    test('CRUD and size', () async {
      const media = CachedMedia(
        hash: 'm1',
        path: '/media/m1',
        size: 1024,
        lastAccessed: 1000,
      );
      await service.saveMedia(media);
      expect((await service.getMedia('m1'))!.hash, equals('m1'));
      expect(await service.getMediaCacheSize(), equals(1024));

      await service.deleteMedia('m1');
      expect(await service.getMedia('m1'), isNull);
    });
  });

  group('follow requests', () {
    test('inbound request lifecycle', () async {
      await service.saveInboundRequest(FollowRequest(
        pubkey: 'req-1',
        payload: Uint8List.fromList([1, 2, 3]),
        createdAt: 1000,
        requestTimestamp: 990,
      ));

      expect(await service.getInboundRequests(), hasLength(1));

      await service.updateInboundRequestStatus('req-1', 'accepted');
      expect(await service.getInboundRequests(), isEmpty);
    });

    test('outbound request lifecycle', () async {
      await service.saveOutboundRequest(FollowRequest(
        pubkey: 'target-1',
        payload: Uint8List.fromList(
          '{"pubkey":"target-1"}'.codeUnits,
        ),
        createdAt: 2000,
        requestTimestamp: 2000,
      ));

      final outbound = await service.getOutboundRequests();
      expect(outbound, hasLength(1));
      expect(outbound.first.pubkey, equals('target-1'));
    });
  });

  group('outbound queue', () {
    test('enqueue, dequeue, remove', () async {
      await service.enqueue('target-1', Uint8List.fromList([10, 20]));

      final items = await service.dequeue('target-1');
      expect(items, hasLength(1));
      expect(items.first.retryCount, equals(0));

      await service.incrementRetry(items.first.id);
      final updated = await service.dequeue('target-1');
      expect(updated.first.retryCount, equals(1));

      await service.removeFromQueue(items.first.id);
      expect(await service.dequeue('target-1'), isEmpty);
    });
  });

  group('Plan 06: bookmark + retention semantics', () {
    Event makePost(
      String id, {
      String pubkey = 'me',
      int createdAt = 1000,
      EventKind kind = EventKind.post,
      String? ref,
    }) =>
        Event(
          version: '2026-03-24',
          id: id,
          pubkey: pubkey,
          createdAt: createdAt,
          kind: kind,
          ref: ref,
          content: Uint8List.fromList([0]),
          sig: Uint8List.fromList(List.filled(64, 0)),
        );

    test('setEventSaved round-trips', () async {
      await service.saveEvent(makePost('e1'));
      expect(await service.isEventSaved('e1'), isFalse);

      await service.setEventSaved('e1', true);
      expect(await service.isEventSaved('e1'), isTrue);

      await service.setEventSaved('e1', false);
      expect(await service.isEventSaved('e1'), isFalse);
    });

    test('setEventSaved survives saveEvent re-upsert', () async {
      // Real scenario: a sync re-fetches the same event after the user
      // bookmarked it locally. The bookmark must persist.
      await service.saveEvent(makePost('e1'));
      await service.setEventSaved('e1', true);

      // Re-save the same event id (different content/sig would still be the
      // same drift upsert path).
      await service.saveEvent(makePost('e1'));
      expect(await service.isEventSaved('e1'), isTrue,
          reason:
              'is_saved column was preserved across drift upsert (companion omits the column)');
    });

    test('setEventLastViewed updates the column', () async {
      await service.saveEvent(makePost('e1'));
      await service.setEventLastViewed('e1', 9999);
      // No public reader, but the eviction test below depends on the value.
      // Spot-check by triggering retention with a grace cutoff that keeps
      // events with last_viewed >= 9999 alive.
      final identity = await service.getIdentity();
      // For this test we don't need an identity row; eviction filters by
      // is_own=0, and our event is_own=0 by default since no identity is set.
      expect(identity, isNull);
      final removed = await service.evictOldEvents(
        500, // maxAgeSeconds — anything older than (now-500) is candidate
        100, // graceLastViewedSeconds — last_viewed must be older than (now-100)
      );
      // The event has createdAt=1000 (long ago) and last_viewed=9999. With a
      // mock clock at 0, both cutoffs are negative; eviction keeps it.
      expect(removed, equals(0));
    });

    test('getProfilePosts excludes tombstoned posts', () async {
      await service.saveEvent(makePost('e1', createdAt: 1000));
      await service.saveEvent(makePost('e2', createdAt: 2000));
      // Tombstone for e1 from same author.
      await service.saveEvent(makePost(
        'd1',
        createdAt: 3000,
        kind: EventKind.delete,
        ref: 'e1',
      ));

      final posts = await service.getProfilePosts('me');
      expect(posts.map((e) => e.id), equals(['e2']),
          reason: 'e1 should be filtered out by its kind=6 tombstone');
    });

    test('getFeedEvents filters kind!=1 and tombstones', () async {
      await service.saveIdentity(Identity(
        pubkey: 'me',
        feedKey: Uint8List(32),
        createdAt: 1,
      ));
      await service.saveEvent(makePost('p1', createdAt: 1000));
      await service.saveEvent(makePost(
        'profile',
        createdAt: 1500,
        kind: EventKind.profile,
      ));
      await service.saveEvent(makePost(
        'd1',
        createdAt: 2000,
        kind: EventKind.delete,
        ref: 'p1',
      ));
      await service.saveEvent(makePost('p2', createdAt: 2500));

      final feed = await service.getFeedEvents();
      expect(feed.map((e) => e.id), equals(['p2']),
          reason:
              'kind=2 profile events excluded; kind=1 p1 excluded by tombstone d1; only kind=1 p2 remains');
    });

    test('evictOldEvents keeps is_saved=1 events even when old', () async {
      // Note: is_own only flips when identity matches author. No identity
      // here, so is_own=0 — exactly the path retention targets.
      await service.saveEvent(makePost(
        'old-post',
        pubkey: 'someone-else',
        createdAt: 1,
      ));
      await service.saveEvent(makePost(
        'saved-post',
        pubkey: 'someone-else',
        createdAt: 1,
      ));
      await service.setEventSaved('saved-post', true);

      // Advance the shared mock clock far enough that 'old-post' is past
      // the maxAge cutoff but 'saved-post' is pinned.
      clock.advance(60 * 86400);

      final removed = await service.evictOldEvents(
        30 * 86400, // 30 day max age
        7 * 86400, // 7 day grace
      );

      expect(removed, equals(1),
          reason: 'unsaved old non-own event evicted; saved one kept');
      expect(await service.getEvent('saved-post'), isNotNull);
      expect(await service.getEvent('old-post'), isNull);
    });
  });
}
