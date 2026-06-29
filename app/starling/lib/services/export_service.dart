import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:path/path.dart' as p;

import 'crypto_service.dart';
import 'media/encrypted_media_paths.dart';
import 'storage/keychain_manager.dart';
import 'storage_service.dart';

/// Result of an export run. The bundle file lives at [path] and is ready
/// to hand to a share-sheet. [eventCount] / [mediaCount] feed the success
/// snackbar.
class ExportResult {
  const ExportResult({
    required this.path,
    required this.eventCount,
    required this.mediaCount,
    required this.byteSize,
  });

  final String path;
  final int eventCount;
  final int mediaCount;
  final int byteSize;
}

/// Produces a signed CBOR bundle of every own event plus the media blobs
/// they reference. Format (top-level CBOR map):
///
/// ```text
/// {
///   "version":  "starling-export-1",
///   "pubkey":   "<crockford32 ed25519 pubkey>",
///   "exported": <unix seconds>,
///   "events":   [<event-bytes>, ...],   // each entry is canonical CBOR
///                                       // bytes from Event.toBytes()
///   "media":    [{ "hash": "...", "blob": <bytes> }, ...],
///   "sig":      <ed25519 signature over the bundle without "sig">
/// }
/// ```
///
/// The signature covers the same map with `sig` removed, re-encoded with
/// `cbor.encode`, so a future importer can verify authenticity using only
/// the [pubkey] field.
class ExportService {
  ExportService({
    required StorageService storage,
    required CryptoService crypto,
    required Future<Directory> exportRoot,
    required Future<Directory> mediaRoot,
    KeychainManager? keychain,
  }) : _storage = storage,
       _crypto = crypto,
       _exportRoot = exportRoot,
       _mediaRoot = mediaRoot,
       _keychain = keychain ?? KeychainManager();

  final StorageService _storage;
  final CryptoService _crypto;
  final Future<Directory> _exportRoot;
  final Future<Directory> _mediaRoot;
  final KeychainManager _keychain;

  static const String exportVersion = 'starling-export-1';

  Future<ExportResult> exportOwnContent({int? nowUnixSeconds}) async {
    final identity = await _storage.getIdentity();
    if (identity == null) {
      throw StateError('No identity to export');
    }
    final secretKeyB64 = await _keychain.read(
      KeychainManager.identitySecretKeyName,
    );
    if (secretKeyB64 == null) {
      throw StateError('Identity secret key missing from keychain');
    }
    final secretKey = Uint8List.fromList(base64Decode(secretKeyB64));

    // Pull own events. `getEvents(pubkey: ...)` returns *all* kinds for the
    // pubkey, which is what an export should preserve (posts + comments
    // the user authored + their own likes/deletes/etc.).
    final events = await _storage.getEvents(pubkey: identity.pubkey);

    // Resolve media: every hash referenced by an own event, dedup'd.
    final hashes = <String>{};
    for (final e in events) {
      for (final m in e.media) {
        if (m.hash.isNotEmpty) hashes.add(m.hash);
      }
    }

    final mediaRoot = await _mediaRoot;
    final mediaEntries = <Map<String, dynamic>>[];
    for (final hash in hashes) {
      final file = File(p.join(mediaRoot.path, mediaRelativePath(hash)));
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      mediaEntries.add({'hash': hash, 'blob': bytes});
    }

    final exportedAt =
        nowUnixSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    // The "to be signed" map: identical to the final bundle minus `sig`.
    final unsigned = <String, dynamic>{
      'version': exportVersion,
      'pubkey': identity.pubkey,
      'exported': exportedAt,
      'events': [for (final e in events) e.toBytes()],
      'media': mediaEntries,
    };

    final tbs = Uint8List.fromList(cbor.encode(unsigned));
    final sig = _crypto.sign(secretKey, tbs);

    final signed = <String, dynamic>{...unsigned, 'sig': sig};
    final bundleBytes = Uint8List.fromList(cbor.encode(signed));

    final dir = await _exportRoot;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final fileName = 'starling-export-$exportedAt.cbor';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bundleBytes, flush: true);

    return ExportResult(
      path: file.path,
      eventCount: events.length,
      mediaCount: mediaEntries.length,
      byteSize: bundleBytes.length,
    );
  }
}
