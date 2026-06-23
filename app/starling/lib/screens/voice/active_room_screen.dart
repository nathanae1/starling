import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/voice_room.dart';
import '../../providers/identity_provider.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/voice/participant_avatar.dart';

class ActiveRoomScreen extends ConsumerStatefulWidget {
  const ActiveRoomScreen({super.key});

  @override
  ConsumerState<ActiveRoomScreen> createState() => _ActiveRoomScreenState();
}

class _ActiveRoomScreenState extends ConsumerState<ActiveRoomScreen> {
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // The mic prompt also fires inside getUserMedia, but request up front so
    // a denial is visible before we appear to "join".
    Permission.microphone.request();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _leave(VoiceRoom room, String? myPubkey) async {
    if (_leaving) return;
    _leaving = true;
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    if (myPubkey != null && myPubkey == room.creatorPubkey) {
      await manager.closeRoom();
    } else {
      await manager.leaveRoom();
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    final myPubkey = ref.watch(identityControllerProvider).value?.pubkey;

    // Pop automatically when the call ends (creator closed / we left).
    ref.listen(voiceRoomStateProvider, (prev, next) {
      if (next.value == null && (prev?.value != null)) {
        if (mounted && !_leaving) Navigator.of(context).maybePop();
      }
    });

    final state = ref.watch(voiceRoomStateProvider).value;
    if (state == null) {
      return Scaffold(
        backgroundColor: colors.ink,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFDFBF5)),
        ),
      );
    }

    final room = state.room;
    final participants = room.participants;

    return Scaffold(
      backgroundColor: colors.ink,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Text(
                    room.name,
                    style: starling.typography.h2.copyWith(
                      color: const Color(0xFFFDFBF5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${participants.length} in call',
                    style: starling.typography.small
                        .copyWith(color: colors.stone),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 28,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in participants)
                        ParticipantAvatar(
                          participant: p,
                          isYou: p.pubkey == myPubkey,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _Controls(
              muted: state.localMuted,
              speaker: state.speakerMode,
              onMute: () =>
                  ref.read(roomManagerProvider).setMuted(!state.localMuted),
              onSpeaker: () =>
                  ref.read(roomManagerProvider).setSpeaker(!state.speakerMode),
              onLeave: () => _leave(room, myPubkey),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.muted,
    required this.speaker,
    required this.onMute,
    required this.onSpeaker,
    required this.onLeave,
  });

  final bool muted;
  final bool speaker;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = StarlingTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CircleControl(
            icon: muted ? LucideIcons.micOff : LucideIcons.mic,
            label: muted ? 'Unmute' : 'Mute',
            active: muted,
            onTap: onMute,
          ),
          _CircleControl(
            icon: LucideIcons.phoneOff,
            label: 'Leave',
            background: colors.clay,
            foreground: const Color(0xFFFDFBF5),
            onTap: onLeave,
          ),
          _CircleControl(
            icon: speaker ? LucideIcons.volume2 : LucideIcons.volumeX,
            label: 'Speaker',
            active: speaker,
            onTap: onSpeaker,
          ),
        ],
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    final bg = background ?? (active ? const Color(0xFFFDFBF5) : colors.graphite);
    final fg = foreground ?? (active ? colors.ink : const Color(0xFFFDFBF5));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(icon, size: 24, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: starling.typography.micro.copyWith(color: colors.stone)),
      ],
    );
  }
}
