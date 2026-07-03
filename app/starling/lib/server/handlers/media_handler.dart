import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../services/media/media_files.dart';
import '../../services/storage_service.dart';

/// `GET /media/<hash>` — streamed encrypted blob for a 64-char lowercase
/// hex BLAKE2b-256 hash. Body is the raw `nonce || ciphertext` form on
/// disk; receivers decrypt with the owner's feed key. Disk resolution
/// lives in `services/media/media_files.dart`.
///
/// Returned as a generic `Function` because `shelf_router` invokes it with
/// the path parameter as a second positional arg.
Function mediaHandler({
  required StorageService storage,
  required Directory appSupportDir,
}) {
  return (Request request, String hash) async {
    if (!isValidMediaHash(hash)) {
      return Response(400, body: 'invalid hash');
    }
    final file = await resolveMediaFileForHash(
      storage: storage,
      appSupportDir: appSupportDir,
      hash: hash,
    );
    if (file == null) {
      return Response.notFound('not found');
    }
    final length = await file.length();
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': length.toString(),
      },
    );
  };
}
