import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:starling/models/models.dart';
import 'package:starling/models/profile_content.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/media/media_isolate.dart';
import 'package:starling/services/media_service.dart';
import 'package:starling/services/profile_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/storage_service.dart';

class _FixedClock implements Clock {
  _FixedClock(this.value);
  int value;
  @override
  int nowUnixSeconds() => value;
}

Uint8List _makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 128);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _Fixture {
  _Fixture({
    required this.db,
    required this.storage,
    required this.contentKey,
    required this.crypto,
    required this.feedKey,
    required this.pubkey,
    required this.clock,
    required this.media,
    required this.service,
    required this.tmp,
  });
  final AppDatabase db;
  final StorageService storage;
  final PairwiseContentKeyService contentKey;
  final CryptoService crypto;
  final Uint8List feedKey;
  final String pubkey;
  final _FixedClock clock;
  final MediaService media;
  final ProfileService service;
  final Directory tmp;

  Future<void> close() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  }
}

Future<_Fixture> _build(CryptoService crypto, {int now = 1_700_000_000}) async {
  final db = AppDatabase.memory();
  final kp = await crypto.generateKeyPair();
  final pubkey = crockfordBase32Encode(kp.publicKey);
  final feedKey = crypto.randomBytes(32);
  await db.identityDao.upsertIdentity(IdentityEntriesCompanion.insert(
    pubkey: pubkey,
    feedKey: feedKey,
    recoveryPhrase: const Value(null),
    createdAt: now,
  ));
  final cache = FeedKeyCache()..put(pubkey, feedKey, 0);
  final clock = _FixedClock(now);
  final storage = DriftStorageService(db, clock);
  final contentKey = PairwiseContentKeyService(
    crypto: crypto,
    cache: cache,
    ownPubkey: pubkey,
    ownSecretKey: kp.secretKey,
  );
  final tmp = await Directory.systemTemp.createTemp('starling-profile-test-');
  final media = DefaultMediaService(
    crypto: crypto,
    storage: storage,
    clock: clock,
    appSupportDir: Future.value(tmp),
    compressFn: (req) async => compressImageIsolate(req),
  );
  final service = DefaultProfileService(
    contentKey: contentKey,
    crypto: crypto,
    storage: storage,
    media: media,
    clock: clock,
    identityLookup: () => storage.getIdentity(),
  );
  return _Fixture(
    db: db,
    storage: storage,
    contentKey: contentKey,
    crypto: crypto,
    feedKey: feedKey,
    pubkey: pubkey,
    clock: clock,
    media: media,
    service: service,
    tmp: tmp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  test('name-only: writes a kind=2 with JSON content, no media, bumps counter',
      () async {
    final f = await _build(crypto);
    final id = await f.service.publishProfile(displayName: 'Sam');

    final ev = await f.storage.getLatestProfile(f.pubkey);
    expect(ev, isNotNull);
    expect(ev!.id, id);
    expect(ev.kind, EventKind.profile);
    expect(ev.ref, isNull);
    expect(ev.media, isEmpty);

    final pc = decodeProfileContent(ev.content)!;
    expect(pc.name, 'Sam');
    expect(pc.bio, isNull);
    expect(pc.avatarHash, isNull);

    final identity = await f.storage.getIdentity();
    expect(identity!.msgSeqCounter, 1);

    // Author-time wire bytes are persisted and decrypt round-trips.
    final payload = await f.storage.getEncryptedPayload(id);
    expect(payload, isNotNull);
    final enc = EncryptedEvent.fromBytes(payload!);
    final plain = f.contentKey.decryptEvent(enc, f.feedKey);
    expect(plain.kind, EventKind.profile);
    expect(decodeProfileContent(plain.content)!.name, 'Sam');

    await f.close();
  });

  test('with bio: content carries the bio', () async {
    final f = await _build(crypto);
    await f.service.publishProfile(displayName: 'Sam', bio: 'hi there');
    final ev = await f.storage.getLatestProfile(f.pubkey);
    expect(decodeProfileContent(ev!.content)!.bio, 'hi there');
    await f.close();
  });

  test('over-length bio is clamped to kBioMaxLength in the event', () async {
    final f = await _build(crypto);
    // Defensive clamp guards the service boundary regardless of the editor's
    // input cap. ASCII 'a' → one grapheme == one code unit, so length checks
    // are exact here.
    final longBio = 'a' * (kBioMaxLength + 25);
    await f.service.publishProfile(displayName: 'Sam', bio: longBio);
    final ev = await f.storage.getLatestProfile(f.pubkey);
    final bio = decodeProfileContent(ev!.content)!.bio!;
    expect(bio.length, kBioMaxLength);
    expect(bio, 'a' * kBioMaxLength);
    await f.close();
  });

  test('with avatar: stores a 256² blob + MediaRef whose hash == avatar_hash, '
      'decryptable under the event msg_seq', () async {
    final f = await _build(crypto);
    final src = _makePng(600, 400); // non-square → center-cropped square
    await f.service.publishProfile(displayName: 'Sam', avatarBytes: src);

    final ev = await f.storage.getLatestProfile(f.pubkey);
    expect(ev!.media, hasLength(1));
    final ref = ev.media.first;
    expect(ref.mimeType, 'image/jpeg');
    expect(decodeProfileContent(ev.content)!.avatarHash, ref.hash);

    // The blob is keyed to the event's msg_seq (first publish → 0).
    expect(ev.msgSeq, 0);
    final msgKey = deriveMsgKey(f.feedKey, ev.msgSeq!, f.crypto);
    final plain = await f.media.readPlaintext(ref.hash, msgKey);
    expect(plain, isNotNull);
    final decoded = img.decodeImage(plain!)!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);

    await f.close();
  });

  test('latest-wins: a newer publish supersedes the prior profile', () async {
    final f = await _build(crypto);
    final first = await f.service.publishProfile(displayName: 'Sam');
    f.clock.value += 10;
    final second = await f.service.publishProfile(displayName: 'Samantha');

    final ev = await f.storage.getLatestProfile(f.pubkey);
    expect(ev!.id, second);
    expect(ev.id, isNot(first));
    expect(decodeProfileContent(ev.content)!.name, 'Samantha');
    // Second publish allocated the next msg_seq.
    expect(ev.msgSeq, 1);
    expect((await f.storage.getIdentity())!.msgSeqCounter, 2);

    await f.close();
  });
}
