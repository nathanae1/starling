import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/events_table.dart';
import '../tables/follows_table.dart';
import '../tables/identity_table.dart';

part 'events_dao.g.dart';

@DriftAccessor(tables: [EventEntries, FollowEntries, IdentityEntries])
class EventsDao extends DatabaseAccessor<AppDatabase> with _$EventsDaoMixin {
  EventsDao(super.db);

  /// Ordered `(created_at DESC, id DESC)`. With [untilId], `(until,
  /// untilId)` is a strict keyset cursor (rows ordered after it) so
  /// same-second events truncated by [limit] are picked up by the next
  /// page; bare [until] keeps the inclusive `created_at <= until` bound.
  /// Mirrors the relay's `manifest_page` semantics (TEXT ids compare
  /// bytewise on both).
  Future<List<EventEntry>> getEvents({
    String? pubkey,
    int? since,
    int? until,
    String? untilId,
    int? limit,
  }) {
    final q = select(eventEntries);
    if (pubkey != null || since != null || until != null) {
      q.where((e) {
        Expression<bool> condition = const Constant(true);
        if (pubkey != null) {
          condition = condition & e.pubkey.equals(pubkey);
        }
        if (since != null) {
          condition = condition & e.createdAt.isBiggerOrEqualValue(since);
        }
        if (until != null) {
          if (untilId != null) {
            condition =
                condition &
                (e.createdAt.isSmallerThanValue(until) |
                    (e.createdAt.equals(until) &
                        e.id.isSmallerThanValue(untilId)));
          } else {
            condition = condition & e.createdAt.isSmallerOrEqualValue(until);
          }
        }
        return condition;
      });
    }
    q.orderBy([
      (e) => OrderingTerm.desc(e.createdAt),
      (e) => OrderingTerm.desc(e.id),
    ]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  Future<EventEntry?> getEvent(String id) =>
      (select(eventEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// The most recent kind=2 (profile) event authored by [pubkey], or null.
  /// Profiles are latest-`created_at`-wins; this returns the authoritative
  /// row without loading every event for that author.
  Future<EventEntry?> getLatestProfile(String pubkey) {
    final q = select(eventEntries)
      ..where((e) => e.pubkey.equals(pubkey) & e.kind.equals(2))
      ..orderBy([
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.desc(e.id),
      ])
      ..limit(1);
    return q.getSingleOrNull();
  }

  Future<void> upsertEvent(EventEntriesCompanion entry) =>
      into(eventEntries).insertOnConflictUpdate(entry);

  /// Returns the persisted wire-EncryptedEvent bytes for [id], if any.
  /// Set at author time on own posts; null for received events and for
  /// own posts authored before the schema v2 migration.
  Future<Uint8List?> getEncryptedPayload(String id) async {
    final row =
        await (selectOnly(eventEntries)
              ..addColumns([eventEntries.encryptedPayload])
              ..where(eventEntries.id.equals(id)))
            .getSingleOrNull();
    return row?.read(eventEntries.encryptedPayload);
  }

  Future<void> deleteEvent(String id) =>
      (delete(eventEntries)..where((e) => e.id.equals(id))).go();

  /// Feed events: kind=1 posts from own identity + active follows, with
  /// per-author kind=6 tombstones excluded. Newest first.
  Future<List<EventEntry>> getFeedEvents({int? since, int? limit}) async {
    final identity = await (select(
      identityEntries,
    )..limit(1)).getSingleOrNull();
    final follows = await (select(
      followEntries,
    )..where((f) => f.status.equals('active'))).get();

    final allPubkeys = <String>{
      if (identity != null) identity.pubkey,
      ...follows.map((f) => f.pubkey),
    };

    if (allPubkeys.isEmpty) return [];

    final q = select(eventEntries);
    q.where((e) {
      Expression<bool> condition =
          e.pubkey.isIn(allPubkeys) & e.kind.equals(1) & _notTombstoned(e);
      if (since != null) {
        condition = condition & e.createdAt.isBiggerOrEqualValue(since);
      }
      return condition;
    });
    q.orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  /// Posts authored by [pubkey] for grid display: kind=1 only, deletes
  /// (kind=6 with matching ref_id) excluded. Newest first.
  Future<List<EventEntry>> getProfilePosts(String pubkey, {int? limit}) {
    final q = select(eventEntries);
    q.where(
      (e) => e.pubkey.equals(pubkey) & e.kind.equals(1) & _notTombstoned(e),
    );
    q.orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  /// Events whose `ref_id == refId`, ordered ASC by `created_at`. Optional
  /// `kind` filter narrows to one event kind (4=comment, 5=like, 6=delete).
  Future<List<EventEntry>> getEventsByRef(String refId, {int? kind}) {
    final q = select(eventEntries);
    q.where((e) {
      Expression<bool> condition = e.refId.equals(refId);
      if (kind != null) {
        condition = condition & e.kind.equals(kind);
      }
      return condition;
    });
    q.orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    return q.get();
  }

  /// Events the local server should hand to peers fetching the owner's
  /// content: rows authored by [ownerPubkey], plus rows from anyone whose
  /// `ref_id` points to one of the owner's events. Used by `GET /events`
  /// to re-distribute received comments/likes to other followers.
  Future<List<EventEntry>> getOwnAndIncomingRefs(
    String ownerPubkey, {
    int? since,
    int? limit,
  }) {
    final ownEventIds = selectOnly(eventEntries)
      ..addColumns([eventEntries.id])
      ..where(eventEntries.pubkey.equals(ownerPubkey));

    final q = select(eventEntries);
    q.where((e) {
      // Exclude Plan 17 chatroom kinds (100-103) from the broadcast/re-serve
      // seam: they're membership-scoped (room key), so an own roomMessage —
      // or an incoming one whose ref is our roomCreate — must never be
      // re-encrypted under our feed key and handed to followers.
      Expression<bool> condition =
          (e.pubkey.equals(ownerPubkey) | e.refId.isInQuery(ownEventIds)) &
          (e.kind.isSmallerThanValue(100) | e.kind.isBiggerThanValue(103));
      if (since != null) {
        condition = condition & e.createdAt.isBiggerOrEqualValue(since);
      }
      return condition;
    });
    q.orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  Future<bool> isEventSaved(String id) async {
    final row = await (select(
      eventEntries,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    return row != null && row.isSaved == 1;
  }

  Future<void> setEventSaved(String id, bool saved) =>
      (update(eventEntries)..where((e) => e.id.equals(id))).write(
        EventEntriesCompanion(isSaved: Value(saved ? 1 : 0)),
      );

  Future<void> setLastViewed(String id, int timestamp) =>
      (update(eventEntries)..where((e) => e.id.equals(id))).write(
        EventEntriesCompanion(lastViewed: Value(timestamp)),
      );

  Future<int> evictOldEvents(
    int maxAgeSeconds,
    int graceLastViewedSeconds, {
    required int now,
  }) {
    final cutoff = now - maxAgeSeconds;
    final graceCutoff = now - graceLastViewedSeconds;

    return (delete(eventEntries)..where(
          (e) =>
              e.isOwn.equals(0) &
              e.isSaved.equals(0) &
              e.createdAt.isSmallerThanValue(cutoff) &
              (e.lastViewed.isNull() |
                  e.lastViewed.isSmallerThanValue(graceCutoff)),
        ))
        .go();
  }

  /// Returns the raw `media_refs` JSON strings for events flagged is_saved=1
  /// or is_own=1. Used by retention to compute the pin set — media hashes
  /// referenced from saved/own events must survive cache eviction.
  Future<List<String>> getPinnedMediaRefsJson() async {
    final rows =
        await (select(eventEntries)..where(
              (e) =>
                  (e.isSaved.equals(1) | e.isOwn.equals(1)) &
                  e.mediaRefs.isNotNull(),
            ))
            .get();
    return [
      for (final r in rows)
        if (r.mediaRefs != null && r.mediaRefs!.isNotEmpty) r.mediaRefs!,
    ];
  }

  /// `id NOT IN (SELECT ref_id FROM event_entries WHERE kind=6 AND
  /// pubkey=outer.pubkey AND ref_id IS NOT NULL)` — covered by `idx_events_ref`.
  Expression<bool> _notTombstoned($EventEntriesTable e) {
    final inner = alias(eventEntries, 'tomb');
    final tombstones = selectOnly(inner)
      ..addColumns([inner.refId])
      ..where(
        inner.kind.equals(6) &
            inner.pubkey.equalsExp(e.pubkey) &
            inner.refId.isNotNull(),
      );
    return e.id.isNotInQuery(tombstones);
  }
}
