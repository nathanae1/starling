import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/comments_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/own_profile_provider.dart';
import '../theme/starling_theme.dart';
import '../utils/debug_log.dart';
import 'avatar.dart';
import 'buttons.dart';
import 'encrypted_avatar.dart';
import 'inputs.dart';

/// Sticky composer for the post detail screen. Avatar.sm on the left,
/// `StarlingInput` in the middle (placeholder "Say something kind…"), and a
/// paper-plane-tilt send button on the right. Lifts above the on-screen
/// keyboard via `MediaQuery.viewInsetsOf(context).bottom`. Reserves the
/// home-indicator safe-area inset when the keyboard is closed.
class CommentInput extends ConsumerStatefulWidget {
  const CommentInput({
    super.key,
    required this.postId,
    this.focusNode,
    this.onPosted,
  });

  final String postId;

  /// Optional external focus node so the post detail's comment icon can
  /// focus the composer.
  final FocusNode? focusNode;

  /// Fired after a comment lands — the detail screen scrolls it into view.
  final VoidCallback? onPosted;

  @override
  ConsumerState<CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<CommentInput> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    // Only dispose what we own.
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(commentControllerProvider(widget.postId).notifier)
          .submit(text);
      _controller.clear();
      widget.onPosted?.call();
    } catch (e) {
      // The typed text stays in the field; just say the send didn't land
      // instead of the button silently doing nothing.
      debugLog('comment_input', 'comment submit failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text("Couldn't post your comment — try again."),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // The real profile avatar, not an anonymous "You" placeholder — this is
    // who the comment posts as.
    final profile = ref.watch(ownProfileProvider).value;
    final ownPubkey = ref.watch(identityControllerProvider).value?.pubkey;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: starling.colors.paper,
          border: Border(top: BorderSide(color: starling.colors.hairline)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (profile != null && ownPubkey != null)
                  EncryptedAvatar(
                    name: profile.displayName,
                    pubkey: ownPubkey,
                    avatarHash: profile.avatarHash,
                    avatarMsgSeq: profile.avatarMsgSeq,
                    size: AvatarSize.sm,
                  )
                else
                  const Avatar(name: 'You', size: AvatarSize.sm),
                const SizedBox(width: 10),
                Expanded(
                  child: StarlingInput(
                    controller: _controller,
                    focusNode: _focusNode,
                    placeholder: 'Say something kind…',
                    // Grows to a few lines for longer comments; send stays
                    // on the action button.
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: starling.typography.body.copyWith(fontSize: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StarlingIconButton(
                  onPressed: _sending ? null : _submit,
                  semanticLabel: 'Send comment',
                  child: Icon(
                    LucideIcons.send,
                    size: 20,
                    color: _sending
                        ? starling.colors.stone
                        : starling.colors.sageDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
