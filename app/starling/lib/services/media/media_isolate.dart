import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Input for [compressImageIsolate]. Must contain only bytes and primitives so
/// it's safe to hand to `compute()` — no `Sodium`, no `Ref`, no Drift handle.
class CompressRequest {
  const CompressRequest({
    required this.sourceBytes,
    this.maxDimension = 1080,
    this.quality = 80,
    this.square = false,
  });

  final Uint8List sourceBytes;
  final int maxDimension;
  final int quality;

  /// When true, center-crop the source to a square before resizing — used
  /// for avatars so they fill a circular frame without distortion.
  final bool square;
}

/// Output of [compressImageIsolate]. Only bytes/primitives — isolate-safe.
class CompressResult {
  const CompressResult({
    required this.compressedBytes,
    required this.compressedMime,
    required this.compressedWidth,
    required this.compressedHeight,
    required this.sourceMime,
  });

  final Uint8List compressedBytes;
  final String compressedMime;
  final int compressedWidth;
  final int compressedHeight;
  final String sourceMime;
}

/// Decodes [req.sourceBytes], resizes the longest edge to at most
/// [req.maxDimension] pixels (preserving aspect ratio), and re-encodes as JPEG
/// at [req.quality]. Runs entirely in a compute() isolate: package:image is
/// pure Dart, and we deliberately keep libsodium off this thread (its FFI
/// resources don't cross isolate boundaries without re-init).
CompressResult compressImageIsolate(CompressRequest req) {
  final sourceMime = _sniffMime(req.sourceBytes);
  final decoded = img.decodeImage(req.sourceBytes);
  if (decoded == null) {
    throw const FormatException('unable to decode image');
  }

  // Optional square center-crop (avatars). Done before the resize so the
  // longest-edge cap then yields an exact maxDimension square.
  img.Image source = decoded;
  if (req.square && decoded.width != decoded.height) {
    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final x = (decoded.width - side) ~/ 2;
    final y = (decoded.height - side) ~/ 2;
    source = img.copyCrop(decoded, x: x, y: y, width: side, height: side);
  }

  img.Image resized;
  final longest = source.width >= source.height ? source.width : source.height;
  if (longest > req.maxDimension) {
    if (source.width >= source.height) {
      resized = img.copyResize(source, width: req.maxDimension);
    } else {
      resized = img.copyResize(source, height: req.maxDimension);
    }
  } else {
    resized = source;
  }

  final encoded = img.encodeJpg(resized, quality: req.quality);
  return CompressResult(
    compressedBytes: Uint8List.fromList(encoded),
    compressedMime: 'image/jpeg',
    compressedWidth: resized.width,
    compressedHeight: resized.height,
    sourceMime: sourceMime,
  );
}

String _sniffMime(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'application/octet-stream';
}
