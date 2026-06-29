import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar.dart';
import 'media_decrypt.dart';

/// An [Avatar] that decrypts and shows a profile photo when [avatarHash] and
/// [avatarMsgSeq] are present, falling back to initials while loading or on
/// any failure. The decrypt path is shared with [EncryptedImage] via
/// [resolveAndDecryptMedia], so it gets the same feed-key-rotation-aware
/// fetch + retry behaviour.
class EncryptedAvatar extends ConsumerStatefulWidget {
  const EncryptedAvatar({
    super.key,
    required this.name,
    required this.pubkey,
    required this.avatarHash,
    required this.avatarMsgSeq,
    this.color,
    this.size = AvatarSize.md,
  });

  final String name;
  final String pubkey;
  final String? avatarHash;
  final int? avatarMsgSeq;
  final Color? color;
  final AvatarSize size;

  @override
  ConsumerState<EncryptedAvatar> createState() => _EncryptedAvatarState();
}

class _EncryptedAvatarState extends ConsumerState<EncryptedAvatar> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant EncryptedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarHash != widget.avatarHash ||
        oldWidget.avatarMsgSeq != widget.avatarMsgSeq ||
        oldWidget.pubkey != widget.pubkey) {
      _bytes = null;
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    final hash = widget.avatarHash;
    final msgSeq = widget.avatarMsgSeq;
    if (hash == null || msgSeq == null) return;
    if (_loading) return;
    _loading = true;
    try {
      final bytes = await resolveAndDecryptMedia(
        ref,
        hash: hash,
        pubkey: widget.pubkey,
        msgSeq: msgSeq,
        mounted: () => mounted,
      );
      if (!mounted) return;
      if (bytes != null) setState(() => _bytes = bytes);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Avatar(
      name: widget.name,
      color: widget.color,
      size: widget.size,
      imageProvider: bytes != null ? MemoryImage(bytes) : null,
    );
  }
}
