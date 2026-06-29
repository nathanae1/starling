import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/starling_theme.dart';
import 'media_decrypt.dart';

/// Decrypts a media blob (by hash) for the given author pubkey and renders
/// it. The author's feed key is resolved transparently — own posts use the
/// identity feed key, others use the cached `Follow.feedKey` row.
///
/// Caches up to [_kMaxCachedDecodedImages] decoded plaintexts in memory using
/// a LRU policy so scrolling back to a previously-viewed post doesn't re-hit
/// the disk. The cache is process-local and cleared on app terminate via
/// normal isolate shutdown.
class EncryptedImage extends ConsumerStatefulWidget {
  const EncryptedImage({
    super.key,
    required this.hash,
    required this.pubkey,
    required this.msgSeq,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.borderRadius,
  });

  final String hash;
  final String pubkey;
  // Per-message sequence of the post this media belongs to. Combined
  // with one of the candidate chain roots via `deriveMsgKey`, it
  // re-derives the AEAD key the publisher used to encrypt the blob.
  // Nullable for legacy rows authored before the v9 schema upgrade —
  // those won't decrypt, render the placeholder.
  final int? msgSeq;
  final BoxFit fit;
  final double? aspectRatio;
  final BorderRadius? borderRadius;

  @override
  ConsumerState<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends ConsumerState<EncryptedImage> {
  Uint8List? _bytes;
  bool _missing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant EncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash || oldWidget.pubkey != widget.pubkey) {
      setState(() {
        _bytes = null;
        _missing = false;
      });
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    final cached = _imageCache.get(widget.hash);
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      final bytes = await resolveAndDecryptMedia(
        ref,
        hash: widget.hash,
        pubkey: widget.pubkey,
        msgSeq: widget.msgSeq,
        mounted: () => mounted,
      );
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _missing = true);
      } else {
        _imageCache.put(widget.hash, bytes);
        setState(() => _bytes = bytes);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _retry() async {
    setState(() => _missing = false);
    await _loadIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.zero;

    Widget content;
    if (_bytes != null) {
      content = Image.memory(_bytes!, fit: widget.fit, gaplessPlayback: true);
    } else if (_missing) {
      content = _PlaceholderTile(
        background: starling.colors.linen,
        label: 'Tap to load',
        labelColor: starling.colors.graphite,
        onTap: _retry,
      );
    } else {
      content = _PlaceholderTile(
        background: starling.colors.linen,
        labelColor: starling.colors.stone,
      );
    }

    final clipped = ClipRRect(borderRadius: radius, child: content);

    if (widget.aspectRatio != null) {
      return AspectRatio(aspectRatio: widget.aspectRatio!, child: clipped);
    }
    return clipped;
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({
    required this.background,
    this.label,
    this.labelColor,
    this.onTap,
  });

  final Color background;
  final String? label;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      color: background,
      alignment: Alignment.center,
      child: label == null
          ? null
          : Text(
              label!,
              style: TextStyle(
                color: labelColor,
                fontSize: 13,
                fontFamily: 'IBMPlexSans',
                fontWeight: FontWeight.w500,
              ),
            ),
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

const _kMaxCachedDecodedImages = 50;

/// Process-local LRU cache for decoded image plaintexts. Exposed via
/// [resetEncryptedImageCacheForTesting] so tests can isolate.
final _imageCache = _LruImageCache(_kMaxCachedDecodedImages);

@visibleForTesting
void resetEncryptedImageCacheForTesting() => _imageCache.clear();

class _LruImageCache {
  _LruImageCache(this._capacity);

  final int _capacity;
  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  Uint8List? get(String key) {
    final v = _entries.remove(key);
    if (v == null) return null;
    _entries[key] = v;
    return v;
  }

  void put(String key, Uint8List value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= _capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void clear() => _entries.clear();
}
