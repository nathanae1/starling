import 'dart:typed_data';

import '../models/models.dart';
import 'types.dart';


/// Abstract interface for all persistent storage operations.
///
/// Default implementation uses SQLCipher via Drift (Plan 02).
/// Mock implementation uses in-memory maps.
abstract class StorageService {
  // --- Identity ---

  Future<Identity?> getIdentity();

  Future<void> saveIdentity(Identity identity);

  // --- Follows ---

  Future<List<Follow>> getFollows();

  Stream<List<Follow>> watchFollows();

  Future<Follow?> getFollow(String pubkey);

  Future<void> saveFollow(Follow follow);

  Future<void> removeFollow(String pubkey);

  Future<void> updateLastSynced(String pubkey, int timestamp);

  /// Stamp the completion of a FULL (un-windowed, paged) manifest diff
  /// for [pubkey] (D1).
  Future<void> updateLastFullSynced(String pubkey, int timestamp);

  /// Stamps the most recent decrypt-failure time on the follow row.
  /// Pass `null` to clear. Drives the "Key fresh / stale" status tile.
  Future<void> setLastDecryptFailureAt(String pubkey, int? timestamp);

  /// Clears `last_decrypt_failure_at` only if currently stamped. Single
  /// no-op UPDATE when the flag is null; lets hot success paths call
  /// freely without checking first.
  Future<void> clearLastDecryptFailureIfSet(String pubkey);

  // --- Events ---

  /// Ordered `(createdAt DESC, id DESC)`. `(until, untilId)` together form
  /// a strict keyset cursor for lossless paging (same-second events are
  /// never skipped); bare `until` stays inclusive.
  Future<List<Event>> getEvents({
    String? pubkey,
    int? since,
    int? until,
    String? untilId,
    int? limit,
  });

  Future<Event?> getEvent(String id);

  Future<void> saveEvent(Event event);

  /// Persist [event] AND its wire-format `EncryptedEvent` bytes captured at
  /// author time. Used by the publish path so `GET /events` can later serve
  /// the original encryption verbatim — preserving the author-time
  /// `msgSeq` that media blobs on disk are encrypted under. Caller is
  /// responsible for ensuring [event.pubkey] is the local identity.
  Future<void> saveOwnEventWithEncrypted(
    Event event,
    Uint8List encryptedPayload,
  );

  /// Returns the persisted wire-EncryptedEvent bytes for [id], if any.
  /// Null for received events and for own events from before schema v2.
  Future<Uint8List?> getEncryptedPayload(String id);

  Future<void> deleteEvent(String id);

  /// Feed events (own + all followed), ordered by created_at DESC.
  /// Filters to kind=1 posts and excludes posts with a kind=6 tombstone
  /// from the same author.
  Future<List<Event>> getFeedEvents({int? since, int? limit});

  /// Posts (kind=1) authored by [pubkey] for profile-grid rendering.
  /// Excludes tombstoned (kind=6 ref'd) posts. Ordered DESC.
  Future<List<Event>> getProfilePosts(String pubkey, {int? limit});

  /// Events whose `ref` points to [refId]. Used to load comments (kind=4),
  /// likes (kind=5), and tombstones (kind=6) for a single post. Ordered
  /// ASC by `created_at`. If [kind] is provided, filters to that kind.
  Future<List<Event>> getEventsByRef(String refId, {EventKind? kind});

  /// Events the local server should hand out to peers asking for the
  /// owner's content: own-authored events plus events from others whose
  /// `ref` points to an own event (received comments/likes/deletes that
  /// the owner re-distributes to other followers). Ordered DESC by
  /// `created_at`. Used by `GET /events`.
  Future<List<Event>> getOwnAndIncomingRefs(
    String ownerPubkey, {
    int? since,
    int? limit,
  });

  /// Local-only flag: has the viewer bookmarked/saved this post?
  Future<bool> isEventSaved(String id);

  /// Local-only flag toggle. Never produces a synced event.
  Future<void> setEventSaved(String id, bool saved);

  /// Updates the local `last_viewed` column used by retention's grace period.
  Future<void> setEventLastViewed(String id, int timestamp);

  // --- Media cache ---

  Future<CachedMedia?> getMedia(String hash);

  Future<void> saveMedia(CachedMedia media);

  Future<void> deleteMedia(String hash);

  Future<int> getMediaCacheSize();

  Future<void> evictMedia(int targetSize);

  // --- Followers (people whose accepted follow request lets them read my feed) ---

  /// Pubkeys of inbound followers we've accepted. These are the targets for
  /// feed-key distribution on rotation.
  Future<List<String>> getAcceptedFollowerPubkeys();

  Future<bool> isAcceptedFollower(String pubkey);

  /// Removes the accepted inbound row for [pubkey]. Used by Plan 13's
  /// removeFollower path before triggering rotation.
  Future<void> removeAcceptedFollower(String pubkey);

  // --- Feed key history (Plan 13) ---

  Future<void> appendFeedKeyHistory({
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  });

  /// Returns the retired feed key whose `[validFrom, validUntil)` window
  /// contains [timestamp], or null if none. The current (in-use) key lives
  /// on `Identity.feedKey`; this only consults retired keys.
  Future<RetiredFeedKey?> retiredFeedKeyAt(int timestamp);

  Future<List<RetiredFeedKey>> getFeedKeyHistory();

  // --- Per-follow feed-key history (MegOLM archive) ---

  /// Append a retired chain root for [followPubkey] when their rotation
  /// arrives. Caller supplies the `[validFrom, validUntil)` window the
  /// key was active. Lets cached content from before the rotation stay
  /// decryptable.
  Future<void> appendFollowFeedKeyHistory({
    required String followPubkey,
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  });

  /// All archived chain roots for [followPubkey], oldest first. Used as
  /// fallback candidates when decrypting events/media authored before the
  /// peer's most recent rotation.
  Future<List<RetiredFeedKey>> getFollowFeedKeyHistory(String followPubkey);

  // --- Pending key distributions (Plan 13) ---

  Future<void> addPendingKeyDistribution({
    required String targetPubkey,
    required Uint8List encryptedFeedKey,
    required Uint8List nonce,
    required int createdAt,
  });

  Future<PendingKeyDistribution?> latestPendingDistributionFor(
    String targetPubkey,
  );

  Future<void> markDistributionsDelivered(String targetPubkey, int upTo);

  Future<void> clearPendingDistributionsFor(String targetPubkey);

  // --- Paired relay + card distributions (Plan 15) ---

  /// The single Relay this Owner has paired with, or null if none.
  Future<PairedRelay?> getPairedRelay();

  /// Replace the paired-relay record (one Relay per Owner in v1).
  Future<void> setPairedRelay({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
  });

  /// Flip the one-shot history-backfill flag once the Owner's full event +
  /// media history has been pushed to the Relay.
  Future<void> markRelayBackfillComplete(String relayId);

  /// Forget the paired Relay (unpair).
  Future<void> clearPairedRelay();

  /// Queue a sealed Connection card update for [targetPubkey], delivered on
  /// that follower's next `/manifest` response.
  Future<void> queueCardDistribution({
    required String targetPubkey,
    required Uint8List encryptedCard,
    required Uint8List nonce,
    required int createdAt,
  });

  /// Latest undelivered card update for [targetPubkey], or null.
  Future<PendingCardDistribution?> latestPendingCardFor(String targetPubkey);

  /// Mark card distributions for [targetPubkey] with `createdAt <= upTo`
  /// as delivered. Idempotent.
  Future<void> markCardDistributionsDelivered(String targetPubkey, int upTo);

  /// Drop every queued card update for [targetPubkey] (e.g. on unfollow).
  Future<void> clearCardDistributionsFor(String targetPubkey);

  // --- Voice rooms (Plan 16, local-only call history) ---

  /// Upsert a room summary row. [VoiceRoom.participants] count is recorded.
  Future<void> saveVoiceRoom(VoiceRoom room);

  /// Stamp the time a room ended (closed or left).
  Future<void> updateVoiceRoomEnded(String roomId, int endedAt);

  /// Record (or update) a participant seen in a room.
  Future<void> saveVoiceRoomParticipant(
    String roomId,
    String pubkey, {
    String? displayName,
    required int joinedAt,
  });

  /// Most recent rooms for the "recent rooms" list, newest first.
  Future<List<VoiceRoom>> getRecentVoiceRooms({int limit});

  /// Delete rooms older than [maxAgeSeconds]. Returns rooms removed.
  Future<int> evictOldVoiceRooms(int maxAgeSeconds);

  // --- Follow requests ---

  Future<List<FollowRequest>> getInboundRequests();

  Stream<List<FollowRequest>> watchInboundRequests();

  /// Inbound rows we've already actioned (accepted / pending-send /
  /// send-failed). Powers the "Follows you" rows in the friends list.
  Stream<List<FollowRequest>> watchInboundFollowers();

  Future<List<FollowRequest>> getInboundRequestsByStatus(String status);

  Future<FollowRequest?> getInboundRequest(String pubkey);

  Future<void> saveInboundRequest(FollowRequest request);

  Future<void> updateInboundRequestStatus(String pubkey, String status);

  Future<void> deleteInboundRequest(String pubkey);

  Future<List<FollowRequest>> getOutboundRequests();

  Stream<List<FollowRequest>> watchOutboundRequests();

  Future<FollowRequest?> getOutboundRequest(String pubkey);

  Future<void> saveOutboundRequest(FollowRequest request);

  Future<void> updateOutboundRequestStatus(String pubkey, String status);

  Future<void> deleteOutboundRequest(String pubkey);

  // --- Unknown envelope items (forward compat) ---

  /// Persist an EnvelopeItem with an unrecognized `type` so it can be
  /// preserved (and, in a later plan, forwarded). v1 has no read-side
  /// consumer; this is purely receive-and-store.
  Future<void> saveUnknownEnvelopeItem(UnknownEnvelopeItem item);

  Future<List<UnknownEnvelopeItem>> getUnknownEnvelopeItemsByType(
    String type,
  );

  // --- Outbound queue ---

  Future<void> enqueue(String targetPubkey, Uint8List eventBlob);

  Future<List<QueuedEvent>> dequeue(String targetPubkey);

  Future<void> incrementRetry(int id);

  Future<void> removeFromQueue(int id);

  // --- Retention ---

  /// Returns number of events evicted.
  Future<int> evictOldEvents(int maxAgeSeconds, int graceLastViewedSeconds);

  /// Returns number of media entries evicted.
  Future<int> evictMediaOverLimit(int maxBytes);

  /// Hashes referenced by `is_saved=1` and `is_own=1` events. Used by
  /// retention and the cache-clear path to skip pinned media.
  Future<Set<String>> getPinnedMediaHashes();

  /// Hashes the caller currently has on disk.
  Future<List<String>> getAllCachedMediaHashes();

  /// Plain-text size in bytes of the on-disk DB (excluding WAL/SHM).
  /// Returns 0 if the file doesn't exist (e.g. tests using in-memory DB).
  Future<int> getDatabaseFileSize();

  /// Evict media over [maxBytes], skipping [pinned]. Returns the entries
  /// removed from the index so the caller can delete the underlying files.
  Future<List<CachedMedia>> evictMediaExcluding(
    int maxBytes,
    Set<String> pinned,
  );

  /// Delete every cached media row whose hash isn't in [pinned]. Returns
  /// the removed entries so the caller can also delete on-disk files.
  Future<List<CachedMedia>> clearCachedMediaExcluding(Set<String> pinned);
}
