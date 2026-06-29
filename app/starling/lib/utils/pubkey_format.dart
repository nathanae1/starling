import 'package:flutter/material.dart';

import '../theme/starling_colors.dart';

/// Short, human-scannable rendering of a pubkey for rows where we have no
/// display name yet (pending handshakes, a friend's profile still syncing).
/// Renders `first4…last4` so the string is neither blank nor a wall of
/// base32. Use [shortPubkey] everywhere a name might be missing so the
/// fallback format stays consistent across the app.
String shortPubkey(String pubkey) {
  if (pubkey.length <= 8) return pubkey;
  return '${pubkey.substring(0, 4)}…${pubkey.substring(pubkey.length - 4)}';
}

/// Stable, hash-derived background color for an initials-fallback avatar, so
/// each peer gets a distinct-but-consistent circle when no photo is set (or
/// while one is still decrypting). Pure; no collision protection.
Color avatarColorFor(String pubkey, StarlingColors colors) {
  final palette = [colors.sage, colors.clay, colors.sageDeep, colors.clayDeep];
  return palette[pubkey.hashCode.abs() % palette.length];
}
