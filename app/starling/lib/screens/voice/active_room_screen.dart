import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/voice_room.dart';
import '../../providers/identity_provider.dart';
import '../../providers/second_ticker_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/call_duration.dart';
import '../../widgets/starling_alert_dialog.dart';
import '../../widgets/voice/participant_avatar.dart';

/// Off-white foreground for the dark (ink) in-call surface. Established on-dark
/// text/icon color used across the app — intentionally a fixed value (the
/// theme is light-only), not a newly introduced hex.
const Color _onInk = Color(0xFFFDFBF5);

class ActiveRoomScreen extends ConsumerStatefulWidget {
  const ActiveRoomScreen({super.key});

  @override
  ConsumerState<ActiveRoomScreen> createState() => _ActiveRoomScreenState();
}

class _ActiveRoomScreenState extends ConsumerState<ActiveRoomScreen>
    with WidgetsBindingObserver {
  bool _leaving = false;
  // Mic permission verdict: null while the request is in flight. Blocked →
  // persistent banner + no "Live" label (we'd be transmitting nothing).
  bool? _micGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wakelock is tied to call state in AppShell (not this screen's mount),
    // so navigating to the overlay can't let the phone lock mid-call.
    _checkMic();
  }

  Future<void> _checkMic() async {
    // The mic prompt also fires inside getUserMedia, but request up front so
    // a denial is visible before we appear to "join".
    final status = await Permission.microphone.request();
    if (mounted) setState(() => _micGranted = status.isGranted);
  }

  /// Re-check on resume so returning from Settings clears the banner.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _micGranted == false) {
      _checkMic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _leave(VoiceRoom room, String? myPubkey) async {
    if (_leaving) return;
    final isCreator = myPubkey != null && myPubkey == room.creatorPubkey;
    // Confirm first so an accidental tap doesn't silently drop the call.
    final confirmed = await showStarlingConfirm(
      context,
      title: 'Leave call?',
      message: isCreator
          ? 'You started this call. Leaving will end it for everyone.'
          : 'You will be disconnected from this call.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!confirmed || _leaving) return;
    if (!mounted) return;
    _leaving = true;
    final manager = ref.read(roomManagerProvider);
    final navigator = Navigator.of(context);
    if (isCreator) {
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
    // A silent pop is indistinguishable from a bug — tell non-initiators
    // why the screen just closed.
    ref.listen(roomEndReasonProvider, (_, next) {
      if (next.value == RoomEndReason.closedByCreator && !_leaving) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call ended'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    final state = ref.watch(voiceRoomStateProvider).value;
    if (state == null) {
      return Scaffold(
        backgroundColor: colors.ink,
        body: const Center(child: CircularProgressIndicator(color: _onInk)),
      );
    }

    final room = state.room;
    final participants = room.participants;

    // Ticking mm:ss — the second ticker only runs while a call screen
    // watches it.
    ref.watch(secondTickerProvider);
    final elapsed =
        ref.read(clockProvider).nowUnixSeconds() - room.createdAt;
    // Honest count: connecting invitees aren't "in call".
    final connected = state.connectedCount;
    final countLabel = connected == participants.length
        ? '$connected in call'
        : '$connected of ${participants.length} connected';

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
                      color: _onInk,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$countLabel · ${formatCallDuration(elapsed)}',
                    style: starling.typography.small.copyWith(
                      color: colors.stone,
                    ),
                  ),
                ],
              ),
            ),
            if (_micGranted == false) const _MicBlockedBanner(),
            if (state.anyReconnecting) const _ReconnectingBanner(),
            // Ringing over Tor is legitimately slow — set expectations
            // instead of showing a bare spinner.
            if (!state.anyReconnecting && state.anyConnecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Connecting over Tor — this can take a minute',
                  textAlign: TextAlign.center,
                  style: starling.typography.small.copyWith(
                    color: colors.stone,
                  ),
                ),
              ),
            Expanded(
              // Center the avatars when there's room, but scroll once enough
              // participants (6+) overflow a single screen so none get clipped
              // or cramped. ConstrainedBox floors the content to the viewport
              // height so Center can vertically center the short case.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 48).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: Center(
                      child: Wrap(
                        spacing: 28,
                        runSpacing: 28,
                        alignment: WrapAlignment.center,
                        runAlignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final p in participants)
                            ParticipantAvatar(
                              participant: p,
                              isYou: p.pubkey == myPubkey,
                              onRetry: p.pubkey == myPubkey
                                  ? null
                                  : () => ref
                                        .read(roomManagerProvider)
                                        .retryParticipant(p.pubkey),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Controls(
              muted: state.localMuted,
              micBlocked: _micGranted == false,
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

/// Persistent banner while the OS mic permission is denied — the user is in
/// the call but transmitting nothing, which is otherwise invisible.
class _MicBlockedBanner extends StatelessWidget {
  const _MicBlockedBanner();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Semantics(
        liveRegion: true,
        label: 'Microphone blocked',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.danger.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.danger.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.micOff, size: 14, color: colors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Microphone blocked — others can't hear you",
                  style: starling.typography.small.copyWith(
                    color: _onInk,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: openAppSettings,
                style: TextButton.styleFrom(
                  foregroundColor: colors.sage,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Call-wide banner shown while any remote peer is mid-reconnect. Aggregates
/// the per-participant [ParticipantConnectionState.reconnecting] states that
/// each avatar already surfaces individually.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Semantics(
        liveRegion: true,
        label: 'Reconnecting',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.warning.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Reconnecting…',
                style: starling.typography.small.copyWith(
                  color: _onInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.muted,
    required this.micBlocked,
    required this.speaker,
    required this.onMute,
    required this.onSpeaker,
    required this.onLeave,
  });

  final bool muted;

  /// OS-level mic denial: never show "Live" while transmitting nothing.
  final bool micBlocked;
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
          // Labels announce the current STATE, not the action. "Live"
          // (transmitting) is the active/positive state (sage); "Muted" is
          // inactive (graphite circle, stone label).
          _CircleControl(
            icon: (muted || micBlocked) ? LucideIcons.micOff : LucideIcons.mic,
            label: micBlocked ? 'Mic blocked' : (muted ? 'Muted' : 'Live'),
            background: (muted || micBlocked) ? colors.graphite : colors.sage,
            labelColor: (muted || micBlocked) ? colors.stone : colors.sage,
            semanticLabel: micBlocked
                ? 'Microphone blocked by system settings'
                : muted
                ? 'Microphone muted. Tap to unmute'
                : 'Microphone live. Tap to mute',
            tooltip: micBlocked ? 'Microphone blocked' : (muted ? 'Unmute' : 'Mute'),
            onTap: onMute,
          ),
          _CircleControl(
            icon: LucideIcons.phoneOff,
            label: 'Leave',
            background: colors.clay,
            labelColor: colors.stone,
            semanticLabel: 'Leave call',
            tooltip: 'Leave call',
            onTap: onLeave,
          ),
          // Audio routing (where call audio plays), not an output mute:
          // speakerphone is the active route (sage), earpiece is inactive.
          _CircleControl(
            icon: speaker ? LucideIcons.volume2 : LucideIcons.ear,
            label: speaker ? 'Speakerphone' : 'Earpiece',
            background: speaker ? colors.sage : colors.graphite,
            labelColor: speaker ? colors.sage : colors.stone,
            semanticLabel: speaker
                ? 'Audio routing: speakerphone. Tap to use earpiece'
                : 'Audio routing: earpiece. Tap to use speakerphone',
            tooltip: speaker ? 'Speakerphone' : 'Earpiece',
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
    required this.background,
    required this.labelColor,
    this.semanticLabel,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color labelColor;

  /// Screen-reader label for this icon-only control. Falls back to [tooltip].
  final String? semanticLabel;

  /// Long-press / hover tooltip.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    Widget circle = Material(
      color: background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // The default ripple is white and invisible on the dark in-call
        // surface; use a translucent sage so taps give visible feedback.
        splashColor: colors.sage.withValues(alpha: 0.35),
        highlightColor: colors.sage.withValues(alpha: 0.15),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(icon, size: 24, color: _onInk),
        ),
      ),
    );
    if (tooltip != null) {
      circle = Tooltip(message: tooltip!, child: circle);
    }
    final semantics = semanticLabel ?? tooltip;
    if (semantics != null) {
      circle = Semantics(button: true, label: semantics, child: circle);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 8),
        Text(
          label,
          style: starling.typography.micro.copyWith(color: labelColor),
        ),
      ],
    );
  }
}
