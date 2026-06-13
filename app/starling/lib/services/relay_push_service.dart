import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/encrypted_event.dart';
import 'crypto/crockford_base32.dart';
import 'crypto_service.dart';

/// Owner-signed push of EncryptedEvents + media blobs to the paired
/// Relay (Plan 15).
///
/// All writes are authenticated by `X-Starling-Sig: base64(Ed25519.sign(
/// owner_sk, blake2b_256(request_body)))` + `X-Starling-Pubkey:
/// base64(owner_pubkey_bytes)` — matching `relay-spec.md` and the
/// social `signaling_handler` precedent.
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
  })  : _crypto = crypto,
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
    final body = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'items': items
          .map((i) => <String, dynamic>{
                'id': i.id,
                'payload': i.encryptedEvent.toBytes(),
              })
          .toList(),
    }));
    final headers = _signHeaders(
      body: body,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(
          Uri.parse('$relayBaseUrl/events'),
          headers: {
            ...headers,
            'content-type': 'application/cbor',
          },
          body: body,
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw RelayPushException(
        'pushEvents failed: ${res.statusCode} ${res.body}',
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
      body: blob,
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final res = await _http
        .post(
          Uri.parse('$relayBaseUrl/media/$hash'),
          headers: {
            ...headers,
            'content-type': 'application/octet-stream',
          },
          body: blob,
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw RelayPushException(
        'pushMedia failed: ${res.statusCode} ${res.body}',
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
      body: Uint8List(0),
      ownerPubkeyBytes: ownerPubkeyBytes,
      ownerSecretKey: ownerSecretKey,
    );
    final uri = Uri.parse('$relayBaseUrl/media-manifest')
        .replace(queryParameters: after == null ? null : {'after': after});
    final res = await _http.get(uri, headers: headers).timeout(_timeout);
    if (res.statusCode != 200) {
      throw RelayPushException(
        'fetchMediaManifest failed: ${res.statusCode} ${res.body}',
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
    required Uint8List body,
    required Uint8List ownerPubkeyBytes,
    required Uint8List ownerSecretKey,
  }) {
    final digest = _crypto.blake2b256(body);
    final sig = _crypto.sign(ownerSecretKey, digest);
    return {
      'x-starling-pubkey': base64.encode(ownerPubkeyBytes),
      'x-starling-sig': base64.encode(sig),
    };
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
  const RelayPushItem({
    required this.id,
    required this.encryptedEvent,
  });

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

class RelayPushException implements Exception {
  RelayPushException(this.message);
  final String message;
  @override
  String toString() => 'RelayPushException: $message';
}

/// Helper: decode the canonical Crockford base32 pubkey text form
/// (what's stored in `identity.pubkey`) into the raw bytes the wire
/// format requires.
Uint8List decodeStoredPubkey(String storedPubkey) =>
    crockfordBase32Decode(storedPubkey);
