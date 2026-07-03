import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/encrypted_event.dart';
import 'crypto/crockford_base32.dart';
import 'crypto_service.dart';

/// Owner-signed push of EncryptedEvents + media blobs to the paired
/// Relay (Plan 15), plus owner-initiated deletion (Phase 3).
///
/// All writes are authenticated with the request-bound scheme (M2):
/// `X-Starling-Pubkey: base64(owner_pubkey_bytes)`,
/// `X-Starling-Ts: <unix secs>`, and `X-Starling-Sig:
/// base64(Ed25519.sign(owner_sk, ownerRequestDigest(method, path, ts,
/// body)))` — binding method, path, and time so a captured signature
/// can't be replayed against another route or forever. Mirrors the
/// relay's `starling-wire/src/sig.rs`.
///
/// Separate from `LanNetworkService`/`NetworkService` because:
/// - Only the paired Relay needs Owner-sig; LAN/Tor sync to Friends
///   does not. Putting the secret key behind a generic transport
///   interface would widen the trust boundary unnecessarily.
/// - The Relay push wire format diverges from the Follower-to-Follower
///   `pushEnvelope` shape — it carries `{id, payload}` per event so the
///   Relay's `/manifest` can echo plaintext ids it never decrypts.
///
/// The supplied `http.Client` decides transport. In production it's the
/// Tor `http.Client` from Plan 11 (every Relay is reached at `.onion`).
class RelayPushService {
  RelayPushService({
    required CryptoService crypto,
    required http.Client httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) : _crypto = crypto,
       _http = httpClient,
       _timeout = timeout;

  final CryptoService _crypto;
  final http.Client _http;
  final Duration _timeout;

  /// Push a batch of EncryptedEvents to the Relay at [relayBaseUrl].
  /// Each item is `{id, payload}` where `payload` is the raw
  /// `EncryptedEvent` CBOR bytes — the Owner knows `id` from the
  /// plaintext Event before encryption.
  ///
  /// Returns `(accepted, rejected)` parsed from the Relay's response.
  Future<RelayPushReceipt> pushEvents({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<RelayPushItem> items,
  }) async {
    if (items.isEmpty) {
      return const RelayPushReceipt(accepted: 0, rejected: 0);
    }
    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'items': items
            .map(
              (i) => <String, dynamic>{
                'id': i.id,
                'payload': i.encryptedEvent.toBytes(),
              },
            )
            .toList(),
      }),
    );
    final headers = _signHeaders(
      method: 'POST',
      path: '/events',
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(
          Uri.parse('$relayBaseUrl/events'),
          headers: {...headers, 'content-type': 'application/cbor'},
          body: body,
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw RelayPushException(
        'pushEvents failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
    return _decodeReceipt(res.bodyBytes);
  }

  /// Push one encrypted media blob (`nonce || ciphertext` form on disk)
  /// to the Relay. Idempotent on [hash] — pushing the same blob twice
  /// is a no-op on the Relay side.
  Future<void> pushMedia({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required String hash,
    required Uint8List blob,
  }) async {
    final headers = _signHeaders(
      method: 'POST',
      path: '/media/$hash',
      body: blob,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(
          Uri.parse('$relayBaseUrl/media/$hash'),
          headers: {...headers, 'content-type': 'application/octet-stream'},
          body: blob,
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw RelayPushException(
        'pushMedia failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// Delete stored events by plaintext id. Idempotent: absent ids are
  /// counted in the receipt's `missing`, never an error, so a crashed or
  /// replayed delete pass converges.
  Future<RelayDeleteReceipt> deleteEvents({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return const RelayDeleteReceipt(deleted: 0, missing: 0);
    final body = Uint8List.fromList(cbor.encode(<String, dynamic>{'ids': ids}));
    return _postDelete(
      relayBaseUrl: relayBaseUrl,
      path: '/events/delete',
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
  }

  /// Delete stored media blobs by hash. Idempotent like [deleteEvents];
  /// the relay 400s the whole request if ANY hash is malformed.
  Future<RelayDeleteReceipt> deleteMedia({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    required List<String> hashes,
  }) async {
    if (hashes.isEmpty) {
      return const RelayDeleteReceipt(deleted: 0, missing: 0);
    }
    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{'hashes': hashes}),
    );
    return _postDelete(
      relayBaseUrl: relayBaseUrl,
      path: '/media/delete',
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
  }

  Future<RelayDeleteReceipt> _postDelete({
    required String relayBaseUrl,
    required String path,
    required Uint8List body,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
  }) async {
    final headers = _signHeaders(
      method: 'POST',
      path: path,
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(
          Uri.parse('$relayBaseUrl$path'),
          headers: {...headers, 'content-type': 'application/cbor'},
          body: body,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw RelayPushException(
        'delete $path failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
    return _decodeDeleteReceipt(res.bodyBytes);
  }

  /// Tell the Relay this Owner is unpairing (A3): the relay wipes the
  /// Owner's stored data and drops its onion, so relay-primary followers'
  /// probes fail fast and they fall back to the phone. Owner-signed over
  /// the empty body. Best-effort — the caller's local unpair never depends
  /// on this succeeding.
  Future<void> unpairRelay({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
  }) async {
    final body = Uint8List(0);
    final headers = _signHeaders(
      method: 'POST',
      path: '/unpair',
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(Uri.parse('$relayBaseUrl/unpair'), headers: headers, body: body)
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw RelayPushException(
        'unpair failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// One page of the media hashes the Relay holds for this Owner
  /// (`hash ASC`, keyset-paged via [after]). Owner-signed over the empty
  /// body — it's a GET. Used by the reconcile pass to diff media presence
  /// (D8) in one round trip instead of N HEADs over Tor.
  Future<RelayMediaManifestPage> fetchMediaManifest({
    required String relayBaseUrl,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
    String? after,
  }) async {
    final headers = _signHeaders(
      method: 'GET',
      path: '/media-manifest',
      body: Uint8List(0),
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final uri = Uri.parse(
      '$relayBaseUrl/media-manifest',
    ).replace(queryParameters: after == null ? null : {'after': after});
    final res = await _http.get(uri, headers: headers).timeout(_timeout);
    if (res.statusCode != 200) {
      throw RelayPushException(
        'fetchMediaManifest failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }
    final decoded = cbor.decode(res.bodyBytes);
    if (decoded is! Map) {
      throw RelayPushException('media-manifest body not a CBOR map');
    }
    return RelayMediaManifestPage(
      hashes: (decoded['hashes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      hasOlder: (decoded['has_older'] as bool?) ?? false,
    );
  }

  Map<String, String> _signHeaders({
    required String method,
    required String path,
    required Uint8List body,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest = ownerRequestDigest(
      crypto: _crypto,
      method: method,
      path: path,
      unixTs: ts,
      body: body,
    );
    final sig = _crypto.sign(ownerSecretKey, digest);
    return {
      'x-starling-pubkey': base64.encode(ownerPubkeyBytes),
      'x-starling-ts': ts.toString(),
      'x-starling-sig': base64.encode(sig),
    };
  }

  RelayDeleteReceipt _decodeDeleteReceipt(Uint8List bytes) {
    try {
      final decoded = cbor.decode(bytes);
      if (decoded is Map) {
        final deleted = decoded['deleted'];
        final missing = decoded['missing'];
        return RelayDeleteReceipt(
          deleted: deleted is int ? deleted : 0,
          missing: missing is int ? missing : 0,
        );
      }
    } catch (_) {
      // Fall through — a 200 means the delete landed; counts are advisory.
    }
    return const RelayDeleteReceipt(deleted: 0, missing: 0);
  }

  RelayPushReceipt _decodeReceipt(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const RelayPushReceipt(accepted: 0, rejected: 0);
    }
    try {
      final decoded = cbor.decode(bytes);
      if (decoded is Map) {
        final accepted = decoded['accepted'];
        final rejected = decoded['rejected'];
        return RelayPushReceipt(
          accepted: accepted is int ? accepted : 0,
          rejected: rejected is int ? rejected : 0,
        );
      }
    } catch (_) {
      // Fall through to default — receipts are advisory.
    }
    return const RelayPushReceipt(accepted: 0, rejected: 0);
  }
}

class RelayPushItem {
  const RelayPushItem({required this.id, required this.encryptedEvent});

  /// Plaintext Event id (Crockford base32). Echoed by the Relay in
  /// `/manifest` responses.
  final String id;
  final EncryptedEvent encryptedEvent;
}

class RelayPushReceipt {
  const RelayPushReceipt({required this.accepted, required this.rejected});
  final int accepted;
  final int rejected;
}

class RelayMediaManifestPage {
  const RelayMediaManifestPage({required this.hashes, required this.hasOlder});
  final List<String> hashes;
  final bool hasOlder;
}

class RelayDeleteReceipt {
  const RelayDeleteReceipt({required this.deleted, required this.missing});
  final int deleted;
  final int missing;
}

class RelayPushException implements Exception {
  RelayPushException(this.message, {this.statusCode});
  final String message;

  /// HTTP status of the failed response, or null when the failure never
  /// produced one (timeout, transport error). The coordinator branches on
  /// 507 to trigger prune-on-507.
  final int? statusCode;

  @override
  String toString() => 'RelayPushException: $message';
}

/// Domain tag for the request-bound Owner signature scheme (M2). Must
/// match `starling-wire/src/sig.rs`.
const String kOwnerReqDomain = 'starling-owner-req-v1';

/// Digest for the request-bound Owner signature:
/// `blake2b256(domain ‖ method ‖ path ‖ u64_be(unix_ts) ‖ blake2b256(body))`.
///
/// Top-level (not a private method) so the vector generator and tests pin
/// the exact production bytes. Mirrors `owner_request_digest` in
/// `starling-wire/src/sig.rs`.
Uint8List ownerRequestDigest({
  required CryptoService crypto,
  required String method,
  required String path,
  required int unixTs,
  required Uint8List body,
}) {
  final tsBytes = ByteData(8)..setUint64(0, unixTs);
  final preimage = BytesBuilder(copy: false)
    ..add(utf8.encode(kOwnerReqDomain))
    ..add(utf8.encode(method))
    ..add(utf8.encode(path))
    ..add(tsBytes.buffer.asUint8List())
    ..add(crypto.blake2b256(body));
  return crypto.blake2b256(preimage.toBytes());
}

/// Helper: decode the canonical Crockford base32 pubkey text form
/// (what's stored in `identity.pubkey`) into the raw bytes the wire
/// format requires.
Uint8List decodeStoredPubkey(String storedPubkey) =>
    crockfordBase32Decode(storedPubkey);
