import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/server/handlers/events_handler.dart';
import 'package:starling/server/handlers/manifest_handler.dart';
import 'package:starling/services/mocks/mock_content_key_service.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';

/// Plan 17 §Required isolation: chatroom kinds (100-103) MUST NOT be served on
/// the feed-broadcast seams. An own `roomMessage` (`isOwn=1`) — or an incoming
/// one whose `ref` is our `roomCreate` — would otherwise be re-encrypted under
/// our feed key and handed to every follower via `GET /events` / `/manifest`.
void main() {
  late MockStorageService storage;
  late MockContentKeyService contentKey;
  late MockCryptoService crypto;
  late Identity me;
  var seq = 0;

  Event unsigned(EventKind kind, String pubkey, {String? ref, int at = 1000}) =>
      Event(
        version: kStarlingProtocolVersion,
        id: '',
        pubkey: pubkey,
        createdAt: at,
        kind: kind,
        ref: ref,
        content: Uint8List.fromList(utf8.encode('x')),
        sig: Uint8List(0),
      );

  Future<Event> saveOwn(EventKind kind, {String? ref, int at = 1000}) async {
    final r = contentKey.signAndEncryptForAudience(
      unsigned(kind, me.pubkey, ref: ref, at: at),
      Audience.broadcast,
      msgSeq: seq++,
    );
    await storage.saveOwnEventWithEncrypted(r.signed, r.encrypted.toBytes());
    return r.signed;
  }

  Future<Event> saveIncoming(
    EventKind kind,
    String author, {
    String? ref,
    int at = 1000,
  }) async {
    final r = contentKey.signAndEncryptForAudience(
      unsigned(kind, author, ref: ref, at: at),
      Audience.broadcast,
      msgSeq: seq++,
    );
    await storage.saveEvent(r.signed);
    return r.signed;
  }

  setUp(() async {
    storage = MockStorageService();
    contentKey = MockContentKeyService();
    crypto = MockCryptoService();
    me = Identity(
      pubkey: 'MEPUBKEY',
      feedKey: Uint8List(32),
      feedKeyEpoch: 0,
      feedKeyValidFrom: 0,
      msgSeqCounter: 0,
      createdAt: 0,
    );
    await storage.saveIdentity(me);
  });

  test(
    'room kinds are excluded from GET /events, feed kinds survive',
    () async {
      final post = await saveOwn(EventKind.post);
      final roomCreate = await saveOwn(EventKind.roomCreate);
      final ownRoomMsg = await saveOwn(
        EventKind.roomMessage,
        ref: roomCreate.id,
      );
      // Incoming comment on our post — must still be re-served.
      final incomingComment = await saveIncoming(
        EventKind.comment,
        'BPUBKEY',
        ref: post.id,
      );
      // Incoming room message referencing our roomCreate — the trap: it matches
      // getOwnAndIncomingRefs by ref, and must be dropped by the kind filter.
      final incomingRoomMsg = await saveIncoming(
        EventKind.roomMessage,
        'BPUBKEY',
        ref: roomCreate.id,
      );

      final envelope = await buildEventsEnvelope(
        storage: storage,
        contentKey: contentKey,
        identity: me,
      );
      final served = envelope.items
          .map(
            (i) => contentKey.decryptEvent(
              EncryptedEvent.fromBytes(i.payload),
              me.feedKey,
            ),
          )
          .toList();
      final servedKinds = served.map((e) => e.kind.value).toSet();
      final servedIds = served.map((e) => e.id).toSet();

      expect(servedKinds.contains(EventKind.post.value), isTrue);
      expect(servedKinds.contains(EventKind.comment.value), isTrue);
      expect(servedIds.contains(incomingComment.id), isTrue);

      for (final v in [100, 101, 102, 103]) {
        expect(servedKinds.contains(v), isFalse, reason: 'kind $v leaked');
      }
      expect(servedIds.contains(roomCreate.id), isFalse);
      expect(servedIds.contains(ownRoomMsg.id), isFalse);
      expect(servedIds.contains(incomingRoomMsg.id), isFalse);
    },
  );

  test('room kinds are excluded from the /manifest event list', () async {
    final post = await saveOwn(EventKind.post);
    final roomCreate = await saveOwn(EventKind.roomCreate);
    final ownRoomMsg = await saveOwn(EventKind.roomMessage, ref: roomCreate.id);

    final bytes = await buildManifestResponseBytes(
      storage: storage,
      crypto: crypto,
      identity: me,
    );
    final decoded = cbor.decode(bytes) as Map<dynamic, dynamic>;
    final ids = (decoded['events'] as List)
        .map((e) => (e as Map)['id'] as String)
        .toSet();

    expect(ids.contains(post.id), isTrue);
    expect(ids.contains(roomCreate.id), isFalse);
    expect(ids.contains(ownRoomMsg.id), isFalse);
  });
}
