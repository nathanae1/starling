import 'dart:typed_data';

class KeyPair {
  const KeyPair({required this.publicKey, required this.secretKey});
  final Uint8List publicKey; // 32 bytes
  final Uint8List secretKey; // 64 bytes (Ed25519 expanded)
}

class TorStatus {
  const TorStatus({
    required this.bootstrapPercent,
    required this.circuitCount,
    required this.isReady,
    this.onionAddress,
  });
  final int bootstrapPercent;
  final int circuitCount;
  final bool isReady;
  final String? onionAddress;

  // Value equality so pollers can emit only on change instead of
  // rebuilding watchers every tick.
  @override
  bool operator ==(Object other) =>
      other is TorStatus &&
      other.bootstrapPercent == bootstrapPercent &&
      other.circuitCount == circuitCount &&
      other.isReady == isReady &&
      other.onionAddress == onionAddress;

  @override
  int get hashCode =>
      Object.hash(bootstrapPercent, circuitCount, isReady, onionAddress);
}

class LanPeer {
  const LanPeer({required this.pubkey, required this.host, required this.port});
  final String pubkey;
  final String host;
  final int port;
}

class PeerConnection {
  const PeerConnection({
    required this.pubkey,
    required this.baseUrl,
    required this.transport,
  });
  final String pubkey;
  final String baseUrl;
  final PeerTransport transport;
}

enum PeerTransport { lan, libp2pDirect, relay, tor }

extension PeerTransportDialing on PeerTransport {
  /// Relay endpoints are .onion hosts — reachable only via Tor SOCKS, the
  /// same dialer as [PeerTransport.tor]. Single source of truth for every
  /// site that picks an HTTP client by transport (TransportRouter,
  /// PeerReachabilityMonitor); keep them on this predicate so they can't
  /// drift.
  bool get dialsViaTor =>
      this == PeerTransport.tor || this == PeerTransport.relay;
}

/// Base URL for an endpoint address off a Connection card (a host or
/// `host:port`, typically a `.onion`). Appends the `:80` default the
/// on-device servers and relays listen on when the address carries no
/// port. Shared by the reachability prober and the relay push coordinator.
String httpBaseUrlForAddress(String addr) =>
    addr.contains(':') ? 'http://$addr' : 'http://$addr:80';

class Manifest {
  const Manifest({
    required this.pubkey,
    required this.events,
    required this.hasOlder,
    this.newFeedKey,
    this.newConnectionCard,
  });
  final String pubkey;
  final List<ManifestEntry> events;
  final bool hasOlder;
  // Plan 13: when present, the requester is being told about a feed-key
  // rotation by the remote peer. The payload is the new feed key; persist
  // as `follow.feedKey` and ack via `ack_rotation_at` on the next
  // /manifest call.
  final SealedDelivery? newFeedKey;
  // Plan 15: when present, the peer has added/rotated a relay endpoint and
  // is handing us its updated Connection card (`ConnectionCard.toBytes()`),
  // sealed exactly like `newFeedKey`. Persist as `follow.connectionCard`
  // and ack via `card_seen_at` on the next /manifest call.
  final SealedDelivery? newConnectionCard;
}

class ManifestEntry {
  const ManifestEntry({required this.id, required this.createdAt});
  final String id;
  final int createdAt;
}

/// One sealed per-follower payload as it rides in a manifest response and
/// in a pending-distribution row (Plans 13 + 15): XChaCha20-Poly1305
/// ciphertext + 24-byte nonce, with [createdAt] bound into the X25519 DH
/// shared-key derivation — a replayed delivery with a tampered
/// `created_at` fails AEAD decryption, and the AEAD authenticates the
/// author (only the two DH parties can compute the key). Sealing,
/// unsealing, and the per-kind channels live in `sync/sealed_delivery.dart`.
class SealedDelivery {
  const SealedDelivery({
    required this.payload,
    required this.nonce,
    required this.createdAt,
  });
  final Uint8List payload;
  final Uint8List nonce;
  final int createdAt;
}

class Identity {
  const Identity({
    required this.pubkey,
    required this.feedKey,
    this.feedKeyEpoch = 0,
    this.feedKeyValidFrom = 0,
    this.msgSeqCounter = 0,
    this.recoveryPhrase,
    required this.createdAt,
  });
  final String pubkey;
  final Uint8List feedKey;
  final int feedKeyEpoch;
  // Unix-seconds timestamp at which `feedKey` became the current key.
  // Identities created pre-Plan-13 backfill this to `createdAt` on migration.
  final int feedKeyValidFrom;
  // MegOLM-shaped per-message counter. Bumped under PublishLock for every
  // event we publish; reset to 0 when `feedKey` rotates. The currently
  // stored value is the next `msg_seq` to allocate.
  final int msgSeqCounter;
  final String? recoveryPhrase;
  final int createdAt;

  Identity copyWith({
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? feedKeyValidFrom,
    int? msgSeqCounter,
  }) => Identity(
    pubkey: pubkey,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    feedKeyValidFrom: feedKeyValidFrom ?? this.feedKeyValidFrom,
    msgSeqCounter: msgSeqCounter ?? this.msgSeqCounter,
    recoveryPhrase: recoveryPhrase,
    createdAt: createdAt,
  );
}

/// A retired feed key (Plan 13). `feedKey` was the current key during the
/// half-open window `[validFrom, validUntil)` and was rotated out at
/// `validUntil`. Used to decrypt own content (e.g. media files) that was
/// encrypted under this key before the rotation.
class RetiredFeedKey {
  const RetiredFeedKey({
    required this.feedKey,
    required this.feedKeyEpoch,
    required this.validFrom,
    required this.validUntil,
  });
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int validFrom;
  final int validUntil;
}

/// A wrapped feed key waiting to be delivered to a follower (Plan 13).
/// The plaintext (32-byte feed key) was encrypted with the X25519 DH
/// shared key derived against [targetPubkey] at the moment of rotation.
class PendingKeyDistribution {
  const PendingKeyDistribution({
    required this.targetPubkey,
    required this.encryptedFeedKey,
    required this.nonce,
    required this.createdAt,
  });
  final String targetPubkey;
  final Uint8List encryptedFeedKey;
  final Uint8List nonce;
  final int createdAt;
}

/// A sealed Connection card waiting to be delivered to a follower (Plan
/// 15). [encryptedCard] is `ConnectionCard.toBytes()` encrypted with the
/// X25519 DH shared key derived against [targetPubkey] (with [createdAt]
/// bound into the derivation, like [PendingKeyDistribution]). Delivered
/// via the `/manifest` response and acked with `card_seen_at`.
class PendingCardDistribution {
  const PendingCardDistribution({
    required this.targetPubkey,
    required this.encryptedCard,
    required this.nonce,
    required this.createdAt,
  });
  final String targetPubkey;
  final Uint8List encryptedCard;
  final Uint8List nonce;
  final int createdAt;
}

/// The single Relay this Owner has paired with (Plan 15). [relayOnion] is
/// the per-Owner `.onion` the Relay launched at pair time; [backfillComplete]
/// flips true once the one-shot history push has finished.
/// [relayPruneBefore] is the persisted prune horizon: own posts with
/// `createdAt < relayPruneBefore` were deliberately aged off the relay
/// (prune-on-507) and are never re-pushed; 0 = nothing pruned.
/// [lastPushAt]/[lastError] surface relay health (A7): the time of the
/// last verified-converged pass and the most recent failure (null when
/// healthy).
class PairedRelay {
  const PairedRelay({
    required this.relayId,
    required this.relayOnion,
    required this.pairedAt,
    this.backfillComplete = false,
    this.relayPruneBefore = 0,
    this.lastPushAt = 0,
    this.lastError,
  });
  final String relayId;
  final String relayOnion;
  final int pairedAt;
  final bool backfillComplete;
  final int relayPruneBefore;
  final int lastPushAt;
  final String? lastError;

  PairedRelay copyWith({
    bool? backfillComplete,
    int? relayPruneBefore,
    int? lastPushAt,
    String? lastError,
    bool clearLastError = false,
  }) => PairedRelay(
    relayId: relayId,
    relayOnion: relayOnion,
    pairedAt: pairedAt,
    backfillComplete: backfillComplete ?? this.backfillComplete,
    relayPruneBefore: relayPruneBefore ?? this.relayPruneBefore,
    lastPushAt: lastPushAt ?? this.lastPushAt,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );
}

/// Singleton crash-safety markers for relay pair/unpair side effects
/// (A2/A3). [pendingCardFanout] means a Connection card update is still
/// owed to followers; [pendingUnpairOnion] names a relay not yet told
/// about its unpair, with [unpairNotifyAttempts] counting retries so the
/// heal pass eventually gives up on a relay that is simply gone.
class RelayFanoutState {
  const RelayFanoutState({
    this.pendingCardFanout = false,
    this.pendingUnpairOnion,
    this.unpairNotifyAttempts = 0,
  });
  final bool pendingCardFanout;
  final String? pendingUnpairOnion;
  final int unpairNotifyAttempts;
}

class Follow {
  const Follow({
    required this.pubkey,
    required this.connectionCard,
    required this.feedKey,
    this.feedKeyEpoch = 0,
    this.lastSyncedAt = 0,
    this.lastFullSyncAt = 0,
    this.lastReceivedRotationAt = 0,
    this.lastReceivedCardAt = 0,
    this.lastDecryptFailureAt,
    this.status = 'active',
  });
  final String pubkey;
  final String connectionCard; // serialized JSON
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int lastSyncedAt;
  // D1: when the last FULL (un-windowed, paged) manifest diff completed
  // for this peer. The windowed cursor can't see events that arrived at a
  // store out of author-time order; the periodic full pass catches them.
  // 0 means "never" — the first sync runs full.
  final int lastFullSyncAt;
  // Plan 13: `created_at` of the most recent rotated feed key we've
  // accepted from this peer. Sent back as `ack_rotation_at` on the next
  // /manifest call so the peer can mark the distribution as delivered.
  final int lastReceivedRotationAt;
  // Plan 15: `created_at` of the most recent Connection card update we've
  // accepted from this peer. Sent back as `card_seen_at` on the next
  // /manifest call so the peer can mark the card distribution delivered.
  final int lastReceivedCardAt;
  // Unix-second timestamp of the most recent decrypt failure on this
  // peer's content (event or media). Set when a stale-key signal lands;
  // cleared when a fresh rotation is applied. Drives the "Key" status
  // tile in connection settings.
  final int? lastDecryptFailureAt;
  final String status;

  Follow copyWith({
    String? connectionCard,
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? lastSyncedAt,
    int? lastFullSyncAt,
    int? lastReceivedRotationAt,
    int? lastReceivedCardAt,
    int? lastDecryptFailureAt,
    bool clearLastDecryptFailureAt = false,
    String? status,
  }) => Follow(
    pubkey: pubkey,
    connectionCard: connectionCard ?? this.connectionCard,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastFullSyncAt: lastFullSyncAt ?? this.lastFullSyncAt,
    lastReceivedRotationAt:
        lastReceivedRotationAt ?? this.lastReceivedRotationAt,
    lastReceivedCardAt: lastReceivedCardAt ?? this.lastReceivedCardAt,
    lastDecryptFailureAt: clearLastDecryptFailureAt
        ? null
        : (lastDecryptFailureAt ?? this.lastDecryptFailureAt),
    status: status ?? this.status,
  );
}

class FollowRequest {
  const FollowRequest({
    required this.pubkey,
    required this.payload,
    required this.createdAt,
    required this.requestTimestamp,
    this.status = 'pending',
  });
  final String pubkey;
  final Uint8List payload;
  // Local DB write time. For inbound rows: receive time. For outbound rows:
  // identical to requestTimestamp.
  final int createdAt;
  // Wire timestamp the requester signed into the outer CBOR. Used by both
  // sides to derive the same shared key for the handshake.
  final int requestTimestamp;
  final String status;
}

class CachedMedia {
  const CachedMedia({
    required this.hash,
    required this.path,
    required this.size,
    required this.lastAccessed,
  });
  final String hash;
  final String path;
  final int size;
  final int lastAccessed;
}

/// An EnvelopeItem whose `type` we don't recognize. Stored opaquely so we
/// can preserve and forward unknown items per the protocol-spec trust
/// model. v1 has only `type:"event"`, so this type carries no consumers
/// yet — it exists for forward compat (Plan 11 onward).
class UnknownEnvelopeItem {
  const UnknownEnvelopeItem({
    required this.sourcePubkey,
    required this.envelopeVersion,
    required this.type,
    required this.payload,
    this.extensions,
    required this.receivedAt,
  });
  final String sourcePubkey;
  final String envelopeVersion;
  final String type;
  final Uint8List payload;
  final Uint8List? extensions;
  final int receivedAt;
}

class QueuedEvent {
  const QueuedEvent({
    required this.id,
    required this.targetPubkey,
    required this.eventBlob,
    required this.createdAt,
    this.retryCount = 0,
    this.itemType,
  });
  final int id;
  final String targetPubkey;
  final Uint8List eventBlob;
  final int createdAt;
  final int retryCount;

  /// Plan 17: the EnvelopeItem `type` this row ships as when drained. Null ⇒
  /// `'event'` (all pre-Plan-17 rows). Chatroom fan-out sets
  /// `'room-key'` / `'room-event'` so the drain forwards the blob verbatim.
  final String? itemType;
}

// --- Chatrooms (Plan 17) ---

/// A durable chatroom. The per-room analogue of the identity's feed-key
/// fields: its own membership-scoped key/epoch/message-seq counter. Text
/// messages live in `event_entries` (kinds 102/103, `ref = id`).
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
    required this.lastActivityAt,
    required this.roomKey,
    required this.roomKeyEpoch,
    required this.roomKeyValidFrom,
    required this.roomMsgSeqCounter,
    required this.membershipEpoch,
    required this.isMember,
    this.lastReadAt = 0,
  });

  /// roomId = the id of the genesis `roomCreate` event.
  final String id;
  final String name;
  final String creatorPubkey;
  final int createdAt;

  /// Retention key — last activity, NOT createdAt.
  final int lastActivityAt;

  /// Current room key (chain root), its epoch, and the time it took effect.
  final Uint8List roomKey;
  final int roomKeyEpoch;
  final int roomKeyValidFrom;

  /// Next msg_seq to allocate under the current room key.
  final int roomMsgSeqCounter;

  /// Monotonic membership version — a roomMembership applies only if newer.
  final int membershipEpoch;

  /// Whether the local user is currently a member (drives retention + UI).
  final bool isMember;

  /// Local-only read cursor (unix seconds) for the unread badge.
  final int lastReadAt;

  Room copyWith({
    String? name,
    int? lastActivityAt,
    Uint8List? roomKey,
    int? roomKeyEpoch,
    int? roomKeyValidFrom,
    int? roomMsgSeqCounter,
    int? membershipEpoch,
    bool? isMember,
    int? lastReadAt,
  }) => Room(
    id: id,
    name: name ?? this.name,
    creatorPubkey: creatorPubkey,
    createdAt: createdAt,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    roomKey: roomKey ?? this.roomKey,
    roomKeyEpoch: roomKeyEpoch ?? this.roomKeyEpoch,
    roomKeyValidFrom: roomKeyValidFrom ?? this.roomKeyValidFrom,
    roomMsgSeqCounter: roomMsgSeqCounter ?? this.roomMsgSeqCounter,
    membershipEpoch: membershipEpoch ?? this.membershipEpoch,
    isMember: isMember ?? this.isMember,
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );
}

/// A chatroom member row. `removedAt == null` ⇒ currently active.
class RoomMember {
  const RoomMember({
    required this.roomId,
    required this.pubkey,
    this.displayName,
    required this.addedAt,
    this.removedAt,
    this.role = 'member',
  });
  final String roomId;
  final String pubkey;
  final String? displayName;
  final int addedAt;
  final int? removedAt;
  final String role;

  bool get isActive => removedAt == null;
}

/// A retired room key with the half-open `[validFrom, validUntil)` window it
/// was active. Lets messages authored before a rotation stay decryptable.
class RetiredRoomKey {
  const RetiredRoomKey({
    required this.roomKey,
    required this.epoch,
    required this.validFrom,
    required this.validUntil,
  });
  final Uint8List roomKey;
  final int epoch;
  final int validFrom;
  final int validUntil;
}

// --- Signaling types (Plan 16 — Voice Chatrooms) ---

/// A persistent bidirectional signaling channel to a remote peer.
///
/// Wraps a WebSocket connection. Used for exchanging ephemeral signaling
/// messages (room invites, SDP offers/answers, ICE candidates).
abstract class SignalingChannel {
  /// The remote peer's Ed25519 public key.
  String get remotePubkey;

  /// The transport used for this channel.
  PeerTransport get transport;

  /// Send a raw CBOR-encoded message to the remote peer.
  /// The message should already be encrypted as an [EphemeralEncryptedEvent].
  Future<void> send(Uint8List data);

  /// Stream of raw inbound CBOR-encoded messages from the remote peer.
  Stream<Uint8List> get messages;

  /// Whether the underlying WebSocket is still open.
  bool get isOpen;

  /// Close this channel.
  Future<void> close();
}
