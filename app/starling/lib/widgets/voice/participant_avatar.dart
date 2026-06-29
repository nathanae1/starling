import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/voice_room.dart';
import '../../theme/starling_theme.dart';
import '../avatar.dart';

/// A participant tile for the active-room grid: avatar with a speaking ring,
/// a mute badge, and a connection-state hint.
class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({
    super.key,
    required this.participant,
    this.isYou = false,
  });

  final VoiceParticipant participant;
  final bool isYou;

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
        participant.connectionState == ParticipantConnectionState.connecting ||
        participant.connectionState == ParticipantConnectionState.reconnecting;
    final disconnected =
        participant.connectionState == ParticipantConnectionState.disconnected;

    return Column(
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
            if (connecting)
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.stone,
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
        if (disconnected) Text('unreachable', style: starling.typography.micro),
      ],
    );
  }
}
