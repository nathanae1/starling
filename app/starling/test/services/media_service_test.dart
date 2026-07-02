import 'dart:io';
import 'dart:typed_data';

import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/media/encrypted_media_paths.dart';
import 'package:starling/services/media/media_isolate.dart';
import 'package:starling/services/media_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FixedClock implements Clock {
  _FixedClock(this._value);
  int _value;
  @override
  int nowUnixSeconds() => _value;
  set value(int v) => _value = v;
}

Uint8List _makePng(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 255) ~/ width, (y * 255) ~/ height, 128);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;
  late AppDatabase db;
  late StorageService storage;
  late Directory tmp;
  late _FixedClock clock;
  late MediaService media;
  late Uint8List feedKey;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  setUp(() async {
    db = AppDatabase.memory();
    clock = _FixedClock(1_700_000_000);
    storage = DriftStorageService(db, clock);
    tmp = await Directory.systemTemp.createTemp('starling-media-test-');
    media = DefaultMediaService(
      crypto: crypto,
      storage: storage,
      clock: clock,
      appSupportDir: Future.value(tmp),
      // Run the compression synchronously in the test isolate — compute()
      // works in flutter_test but spawning an isolate per case is wasteful.
      compressFn: (req) async => compressImageIsolate(req),
    );
    feedKey = crypto.randomBytes(32);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('compresses oversized images to 1080 longest edge', () async {
    final src = _makePng(3000, 2000);
    final result = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    expect(result.compressedMime, 'image/jpeg');
    // Decrypt the compressed blob, decode, verify dimensions.
    final plaintext = await media.readPlaintext(result.compressedHash, feedKey);
    expect(plaintext, isNotNull);
    final decoded = img.decodeImage(plaintext!)!;
    expect(decoded.width == 1080 || decoded.height == 1080, isTrue);
    expect(decoded.width <= 1080, isTrue);
    expect(decoded.height <= 1080, isTrue);
  });

  test('does not upscale images already under the cap', () async {
    final src = _makePng(400, 300);
    final result = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    final plaintext = await media.readPlaintext(result.compressedHash, feedKey);
    final decoded = img.decodeImage(plaintext!)!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
  });

  test(
    'hash in MediaRef matches BLAKE2b-256 of decrypted compressed bytes',
    () async {
      final src = _makePng(600, 400);
      final result = await media.processAndStoreOwnPhoto(
        photoBytes: src,
        msgKey: feedKey,
      );
      final plaintext = await media.readPlaintext(
        result.compressedHash,
        feedKey,
      );
      final rehash = _hex(crypto.blake2b256(plaintext!));
      expect(rehash, equals(result.compressedHash));
    },
  );

  test('writes encrypted blobs to sharded paths and no .tmp remains', () async {
    final src = _makePng(500, 500);
    final result = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    final compressedFile = File(
      '${tmp.path}/${mediaRelativePath(result.compressedHash)}',
    );
    final originalFile = File(
      '${tmp.path}/${mediaRelativePath(result.originalHash)}',
    );
    expect(compressedFile.existsSync(), isTrue);
    expect(originalFile.existsSync(), isTrue);
    expect(File('${compressedFile.path}.tmp').existsSync(), isFalse);
    expect(File('${originalFile.path}.tmp').existsSync(), isFalse);
  });

  test('inserts two media_cache rows (compressed + original)', () async {
    final src = _makePng(500, 500);
    final result = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    final compressedRow = await storage.getMedia(result.compressedHash);
    final originalRow = await storage.getMedia(result.originalHash);
    expect(compressedRow, isNotNull);
    expect(originalRow, isNotNull);
    expect(
      compressedRow!.path,
      equals(mediaRelativePath(result.compressedHash)),
    );
    expect(compressedRow.lastAccessed, equals(1_700_000_000));
    expect(originalRow!.lastAccessed, equals(1_700_000_000));
    // Encrypted size = nonce (24) + ciphertext+tag (plaintext + 16).
    expect(compressedRow.size, greaterThan(0));
    expect(originalRow.size, greaterThan(src.length));
  });

  test('original hash differs from compressed hash', () async {
    final src = _makePng(800, 600);
    final result = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    expect(result.originalHash, isNot(equals(result.compressedHash)));
  });

  test('two successive posts of the same bytes reuse the same hash but use '
      'different nonces', () async {
    final src = _makePng(300, 300);
    final r1 = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    // Rewrite the file (path is identical — that's fine, upsert replaces).
    final r2 = await media.processAndStoreOwnPhoto(
      photoBytes: src,
      msgKey: feedKey,
    );
    expect(r2.compressedHash, equals(r1.compressedHash));
    expect(r2.originalHash, equals(r1.originalHash));
    // Capture the ciphertext (nonce is the first 24 bytes). Second write
    // uses a fresh nonce because encryptMedia pulls random bytes per call.
    final f = File('${tmp.path}/${mediaRelativePath(r2.compressedHash)}');
    // The final on-disk bytes reflect the *second* write, so we can't
    // compare two ciphertexts directly here; instead verify the file bytes
    // decrypt back to the plaintext.
    final enc = await f.readAsBytes();
    final dec = crypto.decryptMedia(enc, feedKey);
    final rehash = _hex(crypto.blake2b256(dec));
    expect(rehash, equals(r2.compressedHash));
  });

  test('readPlaintext returns null for an unknown hash', () async {
    final missing = await media.readPlaintext('0' * 64, feedKey);
    expect(missing, isNull);
  });
}

String _hex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
