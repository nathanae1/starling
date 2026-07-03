import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../utils/base64url.dart';
import 'crypto/crockford_base32.dart';
import 'crypto_service.dart';

/// Phone-side initiator for the `/pair` handshake against the headless
/// Rust Relay (Plan 15 R3).
///
/// Drives the `/pair` handshake after the Owner scans the Relay's
/// `starling-relay://pair` QR. Constructs the signed claim, POSTs it over
/// Tor to the Relay's admin `.onion`, and returns the Relay-issued
/// identifiers so the caller can persist a `paired_relay` row.
///
/// Replay safety lives on both sides: the signed claim binds the
/// token to the Relay's onion (so a captured token can't redirect
/// pairing to a Relay the attacker controls), and the Relay marks the
/// token consumed on success.
class RelayPairingInitiator {
  RelayPairingInitiator({
    required CryptoService crypto,
    required http.Client httpClient,
    // The relay's onion launch alone takes ~30s before Tor RTT, so the
    // timeout must comfortably exceed it or every pair "fails" while the
    // relay actually succeeds.
    Duration timeout = const Duration(seconds: 90),
  }) : _crypto = crypto,
       _http = httpClient,
       _timeout = timeout;

  final CryptoService _crypto;
  final http.Client _http;
  final Duration _timeout;

  /// Build the signed claim, POST `/pair` to the Relay, and decode the
  /// CBOR `{relay_onion, relay_id}` response. Throws
  /// [RelayPairingException] on any non-200 status or malformed body.
  Future<RelayPairingResult> claim({
    required RelayPairingPayload payload,
    required String ownerPubkeyStoredText,
    required Uint8List ownerSecretKey,
  }) async {
    final ownerPubkeyBytes = crockfordBase32Decode(ownerPubkeyStoredText);

    final claimBytes = _buildClaimBytes(
      ownerPubkey: ownerPubkeyBytes,
      relayOnion: payload.relayOnion,
      pairingToken: payload.pairingToken,
    );
    final digest = _crypto.blake2b256(claimBytes);
    final sig = _crypto.sign(ownerSecretKey, digest);

    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'owner_pubkey': base64.encode(ownerPubkeyBytes),
        'pairing_token': payload.pairingToken,
        'sig': sig,
      }),
    );

    final res = await _http
        .post(
          Uri.parse('http://${payload.relayOnion}/pair'),
          headers: const {'content-type': 'application/cbor'},
          body: body,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw RelayPairingException(
        'pair failed: ${res.statusCode} ${res.body}',
        res.statusCode,
      );
    }
    final decoded = cbor.decode(res.bodyBytes);
    if (decoded is! Map) {
      throw const RelayPairingException('pair response not a CBOR map', 200);
    }
    final relayOnion = decoded['relay_onion'];
    final relayId = decoded['relay_id'];
    if (relayOnion is! String || relayId is! String) {
      throw const RelayPairingException('pair response missing fields', 200);
    }
    return RelayPairingResult(relayOnion: relayOnion, relayId: relayId);
  }
}

/// Decoded contents of a `starling-relay://pair?card=…` QR code.
class RelayPairingPayload {
  const RelayPairingPayload({
    required this.relayOnion,
    required this.pairingToken,
    required this.relayVersion,
  });

  final String relayOnion;
  final Uint8List pairingToken;
  final String relayVersion;

  /// Decode the base64url-encoded CBOR map carried as the `card` query
  /// parameter of a `starling-relay://pair` URL. Standard-alphabet input
  /// (no `-`/`_`) is accepted too — some encoders emit it.
  factory RelayPairingPayload.fromBase64(String input) {
    final bytes = input.contains('-') || input.contains('_')
        ? base64UrlDecode(input)
        : base64.decode(padBase64(input));
    final decoded = cbor.decode(bytes);
    if (decoded is! Map) {
      throw const FormatException('pair card not a CBOR map');
    }
    final onion = decoded['relay_onion'];
    final token = decoded['pairing_token'];
    final version = decoded['relay_version'];
    if (onion is! String || token is! List || version is! String) {
      throw const FormatException('pair card missing fields');
    }
    return RelayPairingPayload(
      relayOnion: onion,
      pairingToken: Uint8List.fromList(token.cast<int>()),
      relayVersion: version,
    );
  }
}

class RelayPairingResult {
  const RelayPairingResult({required this.relayOnion, required this.relayId});
  final String relayOnion;
  final String relayId;
}

/// What went wrong with a `/pair` handshake, typed so UI copy can branch
/// without matching on raw status codes (A11).
enum RelayPairingErrorKind {
  /// HTTP 409 — the relay already consumed this pairing token. Routinely
  /// a first attempt that timed out client-side but succeeded relay-side;
  /// retrying the same claim succeeds idempotently once the launch lands.
  tokenAlreadyClaimed,

  /// Any other failure: bad status, malformed response.
  failure,
}

class RelayPairingException implements Exception {
  const RelayPairingException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  RelayPairingErrorKind get kind => statusCode == 409
      ? RelayPairingErrorKind.tokenAlreadyClaimed
      : RelayPairingErrorKind.failure;

  @override
  String toString() => 'RelayPairingException($statusCode): $message';
}

// Domain-separation tag for the signed pairing claim. Bound into
// blake2b_256(tag || owner_pubkey || admin_onion_address || pairing_token)
// so a captured token can't be redirected to a different Relay.
// Mirrored by the Rust relay (Plan 15 R3, "Pairing flow").
const _pairingClaimTag = 'starling-relay-pair-v1';

Uint8List _buildClaimBytes({
  required Uint8List ownerPubkey,
  required String relayOnion,
  required Uint8List pairingToken,
}) {
  final builder = BytesBuilder(copy: false)
    ..add(utf8.encode(_pairingClaimTag))
    ..add(ownerPubkey)
    ..add(utf8.encode(relayOnion))
    ..add(pairingToken);
  return builder.toBytes();
}
