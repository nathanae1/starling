import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:starling/services/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  EventEntriesCompanion makeEvent(
    String id, {
    String pubkey = 'author-pk',
    int createdAt = 1000,
    int kind = 1,
    bool isOwn = false,
  }) => EventEntriesCompanion.insert(
    id: id,
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    content: Uint8List.fromList([72, 101, 108, 108, 111]),
    sig: Uint8List.fromList(List.filled(64, 0xFF)),
    fetchedAt: createdAt,
    isOwn: Value(isOwn ? 1 : 0),
  );

  test('saves and retrieves event by id', () async {
    await db.eventsDao.upsertEvent(makeEvent('evt-1'));
    final event = await db.eventsDao.getEvent('evt-1');
    expect(event, isNotNull);
    expect(event!.id, equals('evt-1'));
    expect(event.pubkey, equals('author-pk'));
  });

  test('returns null for nonexistent event', () async {
    final event = await db.eventsDao.getEvent('nonexistent');
    expect(event, isNull);
  });

  test('queries events by pubkey', () async {
    await db.eventsDao.upsertEvent(makeEvent('e1', pubkey: 'alice'));
    await db.eventsDao.upsertEvent(makeEvent('e2', pubkey: 'bob'));
    await db.eventsDao.upsertEvent(makeEvent('e3', pubkey: 'alice'));

    final aliceEvents = await db.eventsDao.getEvents(pubkey: 'alice');
    expect(aliceEvents, hasLength(2));
  });

  test('queries events with since/until/limit', () async {
    for (var i = 1; i <= 10; i++) {
      await db.eventsDao.upsertEvent(makeEvent('e$i', createdAt: i * 100));
    }

    final sinceEvents = await db.eventsDao.getEvents(since: 500);
    expect(sinceEvents, hasLength(6)); // 500..1000

    final untilEvents = await db.eventsDao.getEvents(until: 300);
    expect(untilEvents, hasLength(3)); // 100..300

    final limited = await db.eventsDao.getEvents(limit: 3);
    expect(limited, hasLength(3));
  });

  test('events ordered by created_at DESC', () async {
    await db.eventsDao.upsertEvent(makeEvent('e1', createdAt: 100));
    await db.eventsDao.upsertEvent(makeEvent('e2', createdAt: 300));
    await db.eventsDao.upsertEvent(makeEvent('e3', createdAt: 200));

    final events = await db.eventsDao.getEvents();
    expect(events.map((e) => e.id).toList(), equals(['e2', 'e3', 'e1']));
  });

  test('deletes event', () async {
    await db.eventsDao.upsertEvent(makeEvent('e1'));
    await db.eventsDao.deleteEvent('e1');
    expect(await db.eventsDao.getEvent('e1'), isNull);
  });

  test('getFeedEvents returns own + followed events', () async {
    // Set up identity.
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'me',
        feedKey: Uint8List(32),
        createdAt: 1,
      ),
    );

    // Set up a follow.
    await db.followsDao.upsertFollow(
      FollowEntriesCompanion.insert(
        pubkey: 'friend',
        connectionCard: '{}',
        feedKey: Uint8List(32),
      ),
    );

    // Events from me, friend, and a stranger.
    await db.eventsDao.upsertEvent(makeEvent('e1', pubkey: 'me', isOwn: true));
    await db.eventsDao.upsertEvent(makeEvent('e2', pubkey: 'friend'));
    await db.eventsDao.upsertEvent(makeEvent('e3', pubkey: 'stranger'));

    final feed = await db.eventsDao.getFeedEvents();
    expect(feed, hasLength(2));
    expect(feed.map((e) => e.pubkey).toSet(), equals({'me', 'friend'}));
  });

  group('watchFeedEvents (Plan 18 C1)', () {
    setUp(() async {
      await db.identityDao.upsertIdentity(
        IdentityEntriesCompanion.insert(
          pubkey: 'me',
          feedKey: Uint8List(32),
          createdAt: 1,
        ),
      );
      await db.followsDao.upsertFollow(
        FollowEntriesCompanion.insert(
          pubkey: 'friend',
          connectionCard: '{}',
          feedKey: Uint8List(32),
        ),
      );
    });

    test(
      'matches getFeedEvents filtering and re-emits on event writes',
      () async {
        await db.eventsDao.upsertEvent(
          makeEvent('e1', pubkey: 'me', isOwn: true, createdAt: 100),
        );

        final emissions = <List<String>>[];
        final sub = db.eventsDao.watchFeedEvents().listen(
          (rows) => emissions.add(rows.map((r) => r.id).toList()),
        );
        addTearDown(sub.cancel);

        // Initial emission.
        await pumpEventQueue();
        expect(emissions.last, equals(['e1']));

        // A write from any path (here: a plain upsert, as sync/push would do)
        // re-fires the stream — no invalidation involved.
        await db.eventsDao.upsertEvent(
          makeEvent('e2', pubkey: 'friend', createdAt: 200),
        );
        await pumpEventQueue();
        expect(emissions.last, equals(['e2', 'e1']));

        // Stranger events stay excluded.
        await db.eventsDao.upsertEvent(
          makeEvent('e3', pubkey: 'stranger', createdAt: 300),
        );
        await pumpEventQueue();
        expect(emissions.last, equals(['e2', 'e1']));
      },
    );

    test(
      're-emits when a follow is added (membership is a subquery)',
      () async {
        await db.eventsDao.upsertEvent(
          makeEvent('s1', pubkey: 'stranger', createdAt: 100),
        );

        final emissions = <List<String>>[];
        final sub = db.eventsDao.watchFeedEvents().listen(
          (rows) => emissions.add(rows.map((r) => r.id).toList()),
        );
        addTearDown(sub.cancel);

        await pumpEventQueue();
        expect(emissions.last, isEmpty);

        await db.followsDao.upsertFollow(
          FollowEntriesCompanion.insert(
            pubkey: 'stranger',
            connectionCard: '{}',
            feedKey: Uint8List(32),
          ),
        );
        await pumpEventQueue();
        expect(emissions.last, equals(['s1']));
      },
    );

    test('tombstoned posts drop out live', () async {
      await db.eventsDao.upsertEvent(
        makeEvent('post', pubkey: 'friend', createdAt: 100),
      );

      final emissions = <List<String>>[];
      final sub = db.eventsDao.watchFeedEvents().listen(
        (rows) => emissions.add(rows.map((r) => r.id).toList()),
      );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(emissions.last, equals(['post']));

      // kind=6 tombstone from the same author.
      await db.eventsDao.upsertEvent(
        EventEntriesCompanion.insert(
          id: 'tomb',
          pubkey: 'friend',
          createdAt: 200,
          kind: 6,
          refId: const Value('post'),
          content: Uint8List(0),
          sig: Uint8List.fromList(List.filled(64, 0xFF)),
          fetchedAt: 200,
        ),
      );
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    });
  });

  test('watchEventsByRef re-emits when a referencing event lands', () async {
    final emissions = <List<String>>[];
    final sub = db.eventsDao
        .watchEventsByRef('post-1', kind: 4)
        .listen((rows) => emissions.add(rows.map((r) => r.id).toList()));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    await db.eventsDao.upsertEvent(
      EventEntriesCompanion.insert(
        id: 'c1',
        pubkey: 'friend',
        createdAt: 100,
        kind: 4,
        refId: const Value('post-1'),
        content: Uint8List.fromList([104, 105]),
        sig: Uint8List.fromList(List.filled(64, 0xFF)),
        fetchedAt: 100,
      ),
    );
    await pumpEventQueue();
    expect(emissions.last, equals(['c1']));
  });

  test('watchProfilePosts re-emits on the author\'s new post', () async {
    final emissions = <List<String>>[];
    final sub = db.eventsDao
        .watchProfilePosts('alice')
        .listen((rows) => emissions.add(rows.map((r) => r.id).toList()));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    await db.eventsDao.upsertEvent(makeEvent('a1', pubkey: 'alice'));
    await pumpEventQueue();
    expect(emissions.last, equals(['a1']));
  });
}
