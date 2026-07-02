import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/second_ticker_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/call_duration.dart';

/// A floating mini-banner shown over the tab shell while a call is active but
/// the user has navigated away from the room screen. Tapping returns to it.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceRoomStateProvider).value;
    if (state == null) return const SizedBox.shrink();

    final starling = StarlingTheme.of(context);
    final colors = starling.colors;
    // Honest count (connecting invitees aren't "in call") + ticking mm:ss.
    final total = state.room.participants.length;
    final connected = state.connectedCount;
    final countLabel = connected == total
        ? '$connected in call'
        : '$connected of $total connected';
    ref.watch(secondTickerProvider);
    final elapsed =
        ref.read(clockProvider).nowUnixSeconds() - state.room.createdAt;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Material(
          color: colors.sageDeep,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/voice/room'),
            child: Semantics(
              button: true,
              label: 'Return to call: ${state.room.name}, $countLabel',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.phoneCall,
                      size: 18,
                      color: Color(0xFFFDFBF5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${state.room.name} · $countLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: starling.typography.body.copyWith(
                          color: const Color(0xFFFDFBF5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      state.anyReconnecting
                          ? 'Reconnecting…'
                          : formatCallDuration(elapsed),
                      style: starling.typography.small.copyWith(
                        color: const Color(0xFFFDFBF5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
