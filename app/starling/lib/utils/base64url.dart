import 'dart:convert';
import 'dart:typed_data';

/// Base64 padding helpers shared by every QR/URL payload parser
/// (connection cards, relay pairing payloads). QR generators routinely
/// strip the `=` padding; `dart:convert` requires it.

/// [input] with `=` padding restored to a multiple of 4.
String padBase64(String input) {
  final remainder = input.length % 4;
  if (remainder == 0) return input;
  return input + ('=' * (4 - remainder));
}

/// Decode base64url [input], tolerating stripped padding.
Uint8List base64UrlDecode(String input) => base64Url.decode(padBase64(input));
