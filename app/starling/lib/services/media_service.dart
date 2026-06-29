import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/debug_log.dart';
import 'clock.dart';
import 'crypto_service.dart';
import 'media/encrypted_media_paths.dart';
import 'media/media_isolate.dart';
import 'storage_service.dart';
import 'types.dart';

/// Result of compressing, hashing, encrypting, and persisting an own photo.
/// The compressed hash is what goes into the `MediaRef` on the outgoing
/// `Event`; the original is local-only and not referenced on the wire.
class MediaProcessingResult {
  const MediaProcessingResult({
    required this.compressedHash,
    required this.compressedSize,
    required this.compressedMime,
    required this.originalHash,
    required this.originalSize,
    required this.originalMime,
  });

  /// Lowercase hex BLAKE2b-256 of the plaintext compressed JPEG.
  final String compressedHash;

  /// Plaintext size in bytes of the compressed photo (what MediaRef reports).
  final int compressedSize;

  /// Always `image/jpeg` — the compression pipeline re-encodes to JPEG.
  final String compressedMime;

  /// Lowercase hex BLAKE2b-256 of the original (pre-compression) plaintext.
  final String originalHash;

  /// Plaintext size in bytes of the original photo.
  final int originalSize;

  /// Sniffed MIME type of the original (image/jpeg, image/png, image/webp,
  /// or application/octet-stream fallback).
  final String originalMime;
}

typedef CompressFn = Future<CompressResult> Function(CompressRequest);

abstract class MediaService {
  /// Compress + hash + encrypt + persist an own photo. Returns hashes and
  /// sizes the caller needs to build a `MediaRef` and a signed `Event`.
  ///
  /// [msgKey] is the per-message AEAD key derived by the caller via
  /// `deriveMsgKey(chainRoot, msgSeq)`. The same key encrypts both the
  /// post body and every media blob attached to that post — letting the
  /// receiver re-derive once from the post's `msgSeq`.
  ///
  /// [maxDimension] caps the longest edge (post photos use 1080; avatars
  /// pass 256). When [square] is true the source is center-cropped to a
  /// square before resizing — used for avatars so they fill a circular
  /// frame without distortion.
  Future<MediaProcessingResult> processAndStoreOwnPhoto({
    required Uint8List photoBytes,
    required Uint8List msgKey,
    int maxDimension = 1080,
    bool square = false,
  });

  /// Decrypt and return the plaintext bytes for a known media hash. Returns
  /// null if the blob is not on disk. [msgKey] is the per-message AEAD
  /// key the caller derived from the owning post's chain root + msgSeq.
  Future<Uint8List?> readPlaintext(String hexHash, Uint8List msgKey);

  /// Persist an already-encrypted blob received from a peer. Atomic write
  /// + media_cache row insert, mirroring the own-photo path. Caller is
  /// responsible for verifying the plaintext hash matches [hexHash] after
  /// decryption (the wire `MediaRef.hash` is the plaintext hash, so the
  /// encrypted bytes themselves can't be hash-verified before decrypt).
  Future<void> storeReceivedBlob(String hexHash, Uint8List encryptedBytes);

  /// True if the encrypted blob for [hexHash] is present on disk. Lets the
  /// fetcher self-heal when a `CachedMedia` row outlives its file (OS-side
  /// app-cache eviction, partial retention, fresh install over old DB).
  Future<bool> hasBlobOnDisk(String hexHash);
}

class DefaultMediaService implements MediaService {
  DefaultMediaService({
    required CryptoService crypto,
    required StorageService storage,
    required Clock clock,
    required Future<Directory> appSupportDir,
    CompressFn? compressFn,
  }) : _crypto = crypto,
       _storage = storage,
       _clock = clock,
       _appSupportDir = appSupportDir,
       _compress = compressFn ?? _defaultCompress;

  final CryptoService _crypto;
  final StorageService _storage;
  final Clock _clock;
  final Future<Directory> _appSupportDir;
  final CompressFn _compress;

  static Future<CompressResult> _defaultCompress(CompressRequest req) =>
      compute(compressImageIsolate, req);

  @override
  Future<MediaProcessingResult> processAndStoreOwnPhoto({
    required Uint8List photoBytes,
    required Uint8List msgKey,
    int maxDimension = 1080,
    bool square = false,
  }) async {
    // 1. Compress in an isolate (JPEG decode + resize + re-encode is the
    //    expensive step; everything else stays on main so libsodium's
    //    per-isolate FFI resources don't have to be re-initialized).
    final compressed = await _compress(
      CompressRequest(
        sourceBytes: photoBytes,
        maxDimension: maxDimension,
        square: square,
      ),
    );

    // 2. Hash both plaintexts (microsecond-cheap on main).
    final compressedHash = _hex(_crypto.blake2b256(compressed.compressedBytes));
    final originalHash = _hex(_crypto.blake2b256(photoBytes));

    // 3. Encrypt both with the per-message key (nonce || ct framing).
    debugLog(
      'starling.media',
      'enc compressed hash=${_shortHex(compressedHash)} '
          'plainLen=${compressed.compressedBytes.length} '
          'msgKeyFp=${shortFingerprint(msgKey)}',
    );
    final compressedEncrypted = _crypto.encryptMedia(
      compressed.compressedBytes,
      msgKey,
    );
    debugLog(
      'starling.media',
      'enc original hash=${_shortHex(originalHash)} '
          'plainLen=${photoBytes.length} '
          'msgKeyFp=${shortFingerprint(msgKey)}',
    );
    final originalEncrypted = _crypto.encryptMedia(photoBytes, msgKey);
    debugLog(
      'starling.media',
      'enc result compressedLen=${compressedEncrypted.length} '
          'originalLen=${originalEncrypted.length} '
          '(includes 24-byte nonce prefix)',
    );

    // 4. Write both blobs atomically into the sharded media dir.
    //    File writes come before the DB upserts so we never end up with a
    //    media_cache row pointing to a non-existent file.
    final root = await _appSupportDir;
    await _atomicWrite(root, compressedHash, compressedEncrypted);
    await _atomicWrite(root, originalHash, originalEncrypted);

    // 5. Upsert media_cache rows (size = on-disk encrypted size; the
    //    plaintext size lives in MediaRef for wire reporting).
    final now = _clock.nowUnixSeconds();
    await _storage.saveMedia(
      CachedMedia(
        hash: compressedHash,
        path: mediaRelativePath(compressedHash),
        size: compressedEncrypted.length,
        lastAccessed: now,
      ),
    );
    await _storage.saveMedia(
      CachedMedia(
        hash: originalHash,
        path: mediaRelativePath(originalHash),
        size: originalEncrypted.length,
        lastAccessed: now,
      ),
    );

    return MediaProcessingResult(
      compressedHash: compressedHash,
      compressedSize: compressed.compressedBytes.length,
      compressedMime: compressed.compressedMime,
      originalHash: originalHash,
      originalSize: photoBytes.length,
      originalMime: compressed.sourceMime,
    );
  }

  @override
  Future<Uint8List?> readPlaintext(String hexHash, Uint8List msgKey) async {
    final root = await _appSupportDir;
    final file = File('${root.path}/${mediaRelativePath(hexHash)}');
    if (!file.existsSync()) {
      debugLog(
        'starling.media',
        'dec MISS hash=${_shortHex(hexHash)} (no file on disk)',
      );
      return null;
    }
    final bytes = await file.readAsBytes();
    final noncePreview = bytes.length >= 24
        ? shortFingerprint(bytes.sublist(0, 24))
        : 'short(${bytes.length})';
    debugLog(
      'starling.media',
      'dec attempt hash=${_shortHex(hexHash)} '
          'blobLen=${bytes.length} noncePrefix=$noncePreview '
          'msgKeyFp=${shortFingerprint(msgKey)}',
    );
    try {
      final pt = _crypto.decryptMedia(bytes, msgKey);
      debugLog(
        'starling.media',
        'dec OK hash=${_shortHex(hexHash)} ptLen=${pt.length}',
      );
      return pt;
    } catch (e) {
      debugLog(
        'starling.media',
        'dec FAIL hash=${_shortHex(hexHash)} '
            'msgKeyFp=${shortFingerprint(msgKey)} err=$e',
      );
      rethrow;
    }
  }

  @override
  Future<void> storeReceivedBlob(
    String hexHash,
    Uint8List encryptedBytes,
  ) async {
    final noncePreview = encryptedBytes.length >= 24
        ? shortFingerprint(encryptedBytes.sublist(0, 24))
        : 'short(${encryptedBytes.length})';
    debugLog(
      'starling.media',
      'rcv hash=${_shortHex(hexHash)} blobLen=${encryptedBytes.length} '
          'noncePrefix=$noncePreview',
    );
    final root = await _appSupportDir;
    await _atomicWrite(root, hexHash, encryptedBytes);
    await _storage.saveMedia(
      CachedMedia(
        hash: hexHash,
        path: mediaRelativePath(hexHash),
        size: encryptedBytes.length,
        lastAccessed: _clock.nowUnixSeconds(),
      ),
    );
  }

  @override
  Future<bool> hasBlobOnDisk(String hexHash) async {
    final root = await _appSupportDir;
    final file = File('${root.path}/${mediaRelativePath(hexHash)}');
    return file.existsSync();
  }

  Future<void> _atomicWrite(
    Directory root,
    String hexHash,
    Uint8List bytes,
  ) async {
    final file = await resolveMediaFile(root, hexHash);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}

String _hex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _shortHex(String hex) {
  if (hex.length <= 8) return hex;
  return '${hex.substring(0, 8)}…';
}
