import 'dart:convert';
import 'dart:typed_data';

import '../models/connection_card.dart';
import '../services/crypto/crockford_base32.dart';
import '../services/relay_pairing_initiator.dart';
import 'base64url.dart';

/// Result of parsing scanned/pasted invite text.
sealed class ParsedInvite {
  const ParsedInvite();
}

class ValidInvite extends ParsedInvite {
  const ValidInvite(this.card);
  final ConnectionCard card;
}

/// Recognized `starling-relay://pair?card=<base64url>` — the Owner scanned
/// a desktop Relay's first-run QR. UI branches to the relay-pairing
/// confirmation flow (Plan 15) instead of the friend-add flow.
class ValidRelayPair extends ParsedInvite {
  const ValidRelayPair(this.payload);
  final RelayPairingPayload payload;
}

class InvalidInvite extends ParsedInvite {
  const InvalidInvite(this.reason);
  final String reason;
}

/// Parses a Starling QR / invite. Accepts:
///   - `starling://connect?card=<b64url>` (or bare b64url) — a Friend's
///     Connection card.
///   - `starling-relay://pair?card=<b64url>` — a desktop Relay's first-run
///     pairing payload (Plan 15).
///
/// Whitespace is stripped before parsing. Bare b64url is treated as a
/// Friend invite for backwards-compat with shipped invite links.
ParsedInvite parseInvite(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const InvalidInvite('empty input');
  }

  String b64;
  bool relayPair = false;
  final hasScheme = trimmed.contains('://');
  if (hasScheme) {
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return const InvalidInvite('not a valid URL');
    }
    if (uri.scheme == 'starling-relay' && uri.host == 'pair') {
      relayPair = true;
    } else if (uri.scheme == 'starling' && uri.host == 'connect') {
      relayPair = false;
    } else {
      return const InvalidInvite('not a starling invite URL');
    }
    final card = uri.queryParameters['card'];
    if (card == null || card.isEmpty) {
      return const InvalidInvite('missing card parameter');
    }
    b64 = card;
  } else {
    b64 = trimmed;
  }

  if (relayPair) {
    try {
      final payload = RelayPairingPayload.fromBase64(b64);
      return ValidRelayPair(payload);
    } on FormatException catch (e) {
      return InvalidInvite(e.message);
    } catch (_) {
      return const InvalidInvite('relay pair payload is malformed');
    }
  }

  final Uint8List bytes;
  try {
    bytes = base64UrlDecode(b64);
  } catch (_) {
    return const InvalidInvite('invite is not valid base64url');
  }

  final ConnectionCard card;
  try {
    card = ConnectionCard.fromBytes(bytes);
  } catch (_) {
    return const InvalidInvite('invite payload is not a valid connection card');
  }

  if (card.pubkey.isEmpty) {
    return const InvalidInvite('invite is missing a pubkey');
  }
  try {
    final raw = crockfordBase32Decode(card.pubkey);
    if (raw.length != 32) {
      return const InvalidInvite('invite has a malformed pubkey');
    }
  } on FormatException {
    return const InvalidInvite('invite has a malformed pubkey');
  }

  return ValidInvite(card);
}

/// Builds the canonical share URL for [card]: `starling://connect?card=<b64url>`.
String inviteUrlFor(ConnectionCard card) {
  final encoded = base64Url.encode(card.toBytes()).replaceAll('=', '');
  return 'starling://connect?card=$encoded';
}
