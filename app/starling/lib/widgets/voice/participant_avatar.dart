import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/voice_room.dart';
import '../../theme/starling_theme.dart';
import '../avatar.dart';

/// A participant tile for the active-room grid: avatar with a speaking ring,
/// a mute badge, and a connection-state hint. Terminal states carry an
/// honest label ("No answer" / "Declined" / …) and — where a retry can
/// help — a per-tile Retry action.
class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({
    super.key,
    required this.participant,
    this.isYou = false,
    this.onRetry,
  });

  final VoiceParticipant participant;
  final bool isYou;

  /// Re-sends the invite/offer for a tile that resolved to "No answer" /
  /// "Couldn't reach". Not shown for declined/busy/full — no instant
  /// re-ring of someone who said no.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    final name =
        participant.displayName ??
        (isYou ? 'You' : participant.pubkey.substring(0, 6));
    final speaking =
        participant.isSpeaking &&
        participant.connectionState == ParticipantConnectionState.connected;

    final connecting =
        participant.connectionState == ParticipantConnectionState.connecting;
    final reconnecting =
        participant.connectionState == ParticipantConnectionState.reconnecting;
    final disconnected =
        participant.connectionState == ParticipantConnectionState.disconnected;
    final endLabel = switch (participant.endReason) {
      ParticipantEndReason.noAnswer => 'No answer',
      ParticipantEndReason.unreachable => "Couldn't reach",
      ParticipantEndReason.declined => 'Declined',
      ParticipantEndReason.busy => 'Busy',
      ParticipantEndReason.roomFull => 'Room full',
      null => 'unreachable',
    };
    final retryable =
        disconnected &&
        onRetry != null &&
        switch (participant.endReason) {
          ParticipantEndReason.declined ||
          ParticipantEndReason.busy ||
          ParticipantEndReason.roomFull => false,
          _ => true,
        };

    // Signal bars only for a live peer with a fair/poor sample; good and
    // no-sample stay clean (the grid shows only exceptional states).
    final quality =
        participant.connectionState == ParticipantConnectionState.connected
        ? participant.quality
        : null;
    final showBars =
        quality == ConnectionQuality.fair || quality == ConnectionQuality.poor;

    // One spoken summary for the whole tile — name, connection state, and
    // mute/speaking flags a sighted user reads off the visuals.
    final semanticState = disconnected
        ? endLabel
        : reconnecting
        ? 'reconnecting'
        : connecting
        ? 'connecting'
        : [
            'connected',
            if (participant.isMuted) 'muted',
            if (speaking) 'speaking',
          ].join(', ');

    return Semantics(
      label: '$name, $semanticState',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking ? colors.sage : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Opacity(
                  opacity: disconnected ? 0.4 : 1,
                  child: Avatar(name: name, size: AvatarSize.lg),
                ),
              ),
              if (connecting || reconnecting)
                SizedBox(
                  width: 78,
                  height: 78,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    // Reconnecting is a degraded live link, not a fresh ring —
                    // give it the warning tint the call-wide banner uses.
                    color: reconnecting ? colors.warning : colors.stone,
                  ),
                ),
              if (participant.isMuted)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colors.clay,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.paper, width: 2),
                    ),
                    child: const Icon(
                      LucideIcons.micOff,
                      size: 12,
                      color: Color(0xFFFDFBF5),
                    ),
                  ),
                ),
              if (showBars)
                Positioned(
                  left: 2,
                  bottom: 2,
                  child: _SignalBars(quality: quality!),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: starling.typography.small.copyWith(
              color: colors.ink,
              fontWeight: isYou ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          if (reconnecting)
            Text(
              'Reconnecting…',
              style: starling.typography.micro.copyWith(color: colors.warning),
            ),
          if (disconnected) Text(endLabel, style: starling.typography.micro),
          if (retryable)
            Semantics(
              button: true,
              label: 'Retry calling $name',
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.sage,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small signal-strength chip shown bottom-left of the avatar for a degraded
/// link. Only `fair` (2 warning bars) and `poor` (1 danger bar) render — a
/// good or not-yet-sampled link shows nothing.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.quality});

  final ConnectionQuality quality;

  @override
  Widget build(BuildContext context) {
    final colors = StarlingTheme.of(context).colors;
    final lit = quality == ConnectionQuality.fair ? 2 : 1;
    final litColor = quality == ConnectionQuality.fair
        ? colors.warning
        : colors.danger;
    final dimColor = colors.stone.withValues(alpha: 0.5);
    return Semantics(
      label: quality == ConnectionQuality.fair
          ? 'Fair connection'
          : 'Weak connection',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: colors.ink.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.paper, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 3,
                height: 4 + i * 3.0,
                decoration: BoxDecoration(
                  color: i < lit ? litColor : dimColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
