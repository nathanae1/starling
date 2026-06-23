import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/voice_room.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../avatar.dart';
import '../buttons.dart';
import '../sheet.dart';

/// Present the inbound-invite modal. Auto-dismisses after 60s (the invite
/// expires); Join accepts + opens the room, Decline notifies the creator.
Future<void> showIncomingInviteSheet(
  BuildContext context,
  VoiceRoom invite,
) {
  return showStarlingSheet<void>(
    context: context,
    builder: (_) => _IncomingInviteBody(invite: invite),
  );
}

class _IncomingInviteBody extends ConsumerStatefulWidget {
  const _IncomingInviteBody({required this.invite});
  final VoiceRoom invite;

  @override
  ConsumerState<_IncomingInviteBody> createState() => _IncomingInviteBodyState();
}

class _IncomingInviteBodyState extends ConsumerState<_IncomingInviteBody> {
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _expiry = Timer(const Duration(seconds: 60), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _join() async {
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    try {
      await manager.acceptInvite(widget.invite.id);
      if (!mounted) return;
      navigator.pop();
      unawaited(router.push('/voice/room'));
    } catch (_) {
      if (mounted) navigator.pop();
    }
  }

  Future<void> _decline() async {
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    await manager.declineInvite(widget.invite.id);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final creatorName = widget.invite.creatorPubkey.substring(0, 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Avatar(name: creatorName, size: AvatarSize.xl)),
        const SizedBox(height: 16),
        Text(
          widget.invite.name,
          textAlign: TextAlign.center,
          style: starling.typography.h2.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          'Voice call invite',
          textAlign: TextAlign.center,
          style: starling.typography.small,
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Join', block: true, onPressed: _join),
        const SizedBox(height: 10),
        SecondaryButton(label: 'Decline', block: true, onPressed: _decline),
      ],
    );
  }
}
