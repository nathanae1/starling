import 'dart:io';
import 'dart:typed_data';

import '../storage_service.dart';
import 'encrypted_media_paths.dart';

/// Read-side access to on-disk encrypted media blobs, shared by every
/// consumer that serves or ships them: the shelf `GET /media/<hash>`
/// handler (streams), `Libp2pStreamServer` (single frame), and the relay
/// push coordinator (uploads). Lives in the media service layer — A11:
/// transports must not import a server handler for a disk read.

/// True for a well-formed 64-char lowercase-hex BLAKE2b-256 media hash.
bool isValidMediaHash(String hash) =>
    hash.length == 64 && _hexPattern.hasMatch(hash);

final _hexPattern = RegExp(r'^[0-9a-f]+$');

/// Returns the on-disk media file for [hash] iff the storage layer knows
/// about it AND it exists on disk.
Future<File?> resolveMediaFileForHash({
  required StorageService storage,
  required Directory appSupportDir,
  required String hash,
}) async {
  if (!isValidMediaHash(hash)) return null;
  final cached = await storage.getMedia(hash);
  if (cached == null) return null;
  final file = await resolveMediaFile(appSupportDir, hash);
  if (!await file.exists()) return null;
  return file;
}

/// Load the entire blob into memory (`nonce || ciphertext` form on disk).
/// The current libp2p single-frame stream contract means we can't stream
/// large blobs; callers should size their FFI read buffer accordingly.
/// Returns null when the hash is invalid or the blob is unknown.
Future<Uint8List?> readMediaBytes({
  required StorageService storage,
  required Directory appSupportDir,
  required String hash,
}) async {
  final file = await resolveMediaFileForHash(
    storage: storage,
    appSupportDir: appSupportDir,
    hash: hash,
  );
  if (file == null) return null;
  return await file.readAsBytes();
}
