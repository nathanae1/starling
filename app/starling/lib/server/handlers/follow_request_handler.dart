import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:shelf/shelf.dart';

import '../../services/clock.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';

/// `POST /follow-request` — accepts a CBOR-encoded follow request and
/// stores it for the owner to act on. Body shape:
///
/// ```
/// {
///   requester_pubkey: string,
///   encrypted_return_endpoints: bytes,
///   nonce: bytes (24),
///   timestamp: int,           // requester's send time, used by both
///                             // sides to derive the same shared key
/// }
/// ```
///
/// The body-size middleware caps reads at 1 MB. The raw bytes are stored
/// verbatim — Plan 08's accept flow decrypts the exact bytes the requester
/// sent.
Handler followRequestHandler({
  required StorageService storage,
  required Clock clock,
}) {
  return (Request request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
    }
    final bodyBytes = builder.toBytes();
    final result = await ingestFollowRequestBytes(
      storage: storage,
      clock: clock,
      bodyBytes: bodyBytes,
    );
    if (!result.ok) {
      return Response(400, body: result.error ?? 'invalid body');
    }
    return Response(202, body: '');
  };
}

class FollowRequestIngestResult {
  const FollowRequestIngestResult.ok() : ok = true, error = null;
  const FollowRequestIngestResult.invalid(this.error) : ok = false;
  final bool ok;
  final String? error;
}

/// Parse + persist the follow-request payload. Reused by `Libp2pStreamServer`
/// for `/starling/sync/follow-request/1`, which delivers exactly the same
/// CBOR bytes as the HTTP path.
Future<FollowRequestIngestResult> ingestFollowRequestBytes({
  required StorageService storage,
  required Clock clock,
  required Uint8List bodyBytes,
}) async {
  final Map<dynamic, dynamic> decoded;
  try {
    final raw = cbor.decode(bodyBytes);
    if (raw is! Map) {
      return const FollowRequestIngestResult.invalid('invalid body');
    }
    decoded = raw;
  } catch (_) {
    return const FollowRequestIngestResult.invalid('invalid cbor');
  }
  final requesterPubkey = decoded['requester_pubkey'];
  final endpoints = decoded['encrypted_return_endpoints'];
  final nonce = decoded['nonce'];
  final timestamp = decoded['timestamp'];
  if (requesterPubkey is! String ||
      !_isBytes(endpoints) ||
      !_isBytes(nonce) ||
      timestamp is! int) {
    return const FollowRequestIngestResult.invalid('invalid body');
  }
  await storage.saveInboundRequest(
    FollowRequest(
      pubkey: requesterPubkey,
      payload: bodyBytes,
      createdAt: clock.nowUnixSeconds(),
      requestTimestamp: timestamp,
    ),
  );
  return const FollowRequestIngestResult.ok();
}

bool _isBytes(dynamic value) => value is Uint8List || value is List<int>;
