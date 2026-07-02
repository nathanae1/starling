import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/voice_room.dart';
import '../../providers/voice_provider.dart';
import '../../services/voice/room_manager.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../avatar.dart';
import '../buttons.dart';
import '../sheet.dart';

/// Present the inbound-invite modal. Rings (platform ringtone + vibration)
/// while up; Join accepts + opens the room, Decline notifies the creator.
/// An unanswered dismissal — 60s expiry, swipe-down, or the creator ending
/// the call — retires the invite via [RoomManager.expireInvite] so the
/// creator's tile resolves to "No answer" instead of spinning.
Future<void> showIncomingInviteSheet(BuildContext context, VoiceRoom invite) {
  return showStarlingSheet<void>(
    context: context,
    builder: (_) => _IncomingInviteBody(invite: invite),
  );
}

class _IncomingInviteBody extends ConsumerStatefulWidget {
  const _IncomingInviteBody({required this.invite});
  final VoiceRoom invite;

  @override
  ConsumerState<_IncomingInviteBody> createState() =>
      _IncomingInviteBodyState();
}

class _IncomingInviteBodyState extends ConsumerState<_IncomingInviteBody> {
  Timer? _expiry;
  Timer? _vibration;
  final _ringtone = FlutterRingtonePlayer();
  // Cached so dispose() can retire the invite without touching `ref`
  // (Riverpod marks the element disposed before our dispose() runs).
  late final RoomManager _manager;
  bool _joining = false;
  // Set once the invite's fate is decided (join/decline/expiry/retired) —
  // guards double-pops and tells dispose() not to expire a handled invite.
  bool _answered = false;
  String? _error;
  bool _showOpenSettings = false;

  @override
  void initState() {
    super.initState();
    _manager = ref.read(roomManagerProvider);
    // There is no push path — a ring only works while the app is open, so
    // make the one we have audible. Platform default ringtone + a vibration
    // loop for silent mode.
    _ringtone.playRingtone(looping: true, volume: 1.0);
    _vibration = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => HapticFeedback.vibrate(),
    );
    _expiry = Timer(const Duration(seconds: 60), () {
      if (!mounted || _answered) return;
      _answered = true;
      unawaited(_manager.expireInvite(widget.invite.id));
      Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _vibration?.cancel();
    unawaited(_ringtone.stop());
    if (!_answered) {
      // Swipe-dismiss (or any unhandled teardown): don't leave the
      // creator's spinner running for 60s — retire the invite now.
      unawaited(_manager.expireInvite(widget.invite.id));
    }
    super.dispose();
  }

  void _stopRinging() {
    _vibration?.cancel();
    unawaited(_ringtone.stop());
  }

  Future<void> _join() async {
    if (_joining || _answered) return;
    setState(() => _joining = true);
    _stopRinging();
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Mic first: a denied join must fail visibly, not enter a call that
    // transmits nothing (the creator path already does this).
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _showOpenSettings = mic.isPermanentlyDenied;
        _error = mic.isPermanentlyDenied
            ? 'Microphone blocked — allow it in Settings to join.'
            : 'Starling needs the microphone to join calls.';
      });
      return;
    }

    try {
      await manager.acceptInvite(widget.invite.id);
      if (!mounted) return;
      _answered = true;
      navigator.pop();
      unawaited(router.push('/voice/room'));
    } on StateError {
      // The invite was retired while we deliberated (creator hung up or
      // the TTL sweep expired it).
      if (!mounted) return;
      _answered = true;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('This call has ended')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = friendlyError(e, tag: 'voice_join');
      });
    }
  }

  Future<void> _decline() async {
    if (_joining || _answered) return;
    _answered = true;
    _stopRinging();
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    await manager.declineInvite(widget.invite.id);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    // Resolved locally from the creator's synced profile; the pubkey prefix
    // is the identity of last resort.
    final creatorName =
        widget.invite.creatorDisplayName ??
        widget.invite.creatorPubkey.substring(0, 8);

    // The creator ended the call before we answered — close the ring.
    ref.listen(retiredVoiceInvitesProvider, (_, next) {
      if (next.value != widget.invite.id || _answered || !mounted) return;
      _answered = true;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This call has ended')),
      );
    });

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
          '$creatorName is calling',
          textAlign: TextAlign.center,
          style: starling.typography.small,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: starling.typography.small.copyWith(
              color: starling.colors.danger,
            ),
          ),
          if (_showOpenSettings) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Open Settings',
              block: true,
              onPressed: openAppSettings,
            ),
          ],
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          label: _joining ? 'Joining…' : 'Join',
          block: true,
          onPressed: (_joining || _answered) ? null : _join,
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: 'Decline',
          block: true,
          onPressed: (_joining || _answered) ? null : _decline,
        ),
      ],
    );
  }
}
