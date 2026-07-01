import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/room_provider.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/feature_flags.dart';
import '../../widgets/buttons.dart';
import '../../widgets/top_bar.dart';

/// Rooms hub. With chatrooms enabled (Plan 17) this is the durable chatroom
/// list; otherwise it's the Plan 16 recent voice-call history.
class RoomListScreen extends ConsumerWidget {
  const RoomListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return kChatroomsEnabled
        ? _buildChatrooms(context, ref)
        : _buildRecentCalls(context, ref);
  }

  Widget _buildChatrooms(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final roomsAsync = ref.watch(roomsProvider);

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            StarlingTopBar(
              title: 'Rooms',
              right: StarlingIconButton(
                onPressed: () => context.push('/voice/settings'),
                semanticLabel: 'Voice settings',
                child: const Icon(LucideIcons.settings, size: 20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PrimaryButton(
                label: 'New room',
                block: true,
                leading: const Icon(LucideIcons.plus, size: 18),
                onPressed: () => context.push('/voice/create'),
              ),
            ),
            Expanded(
              child: roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Couldn\'t load rooms',
                    style: starling.typography.small,
                  ),
                ),
                data: (rooms) {
                  if (rooms.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No rooms yet. Start one with your friends.',
                          textAlign: TextAlign.center,
                          style: starling.typography.small,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      for (final r in rooms)
                        InkWell(
                          onTap: () => context.push('/voice/room/${r.id}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: starling.colors.hairline,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.messagesSquare,
                                  size: 18,
                                  color: starling.colors.stone,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    r.name.isEmpty ? 'Room' : r.name,
                                    style: starling.typography.body.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (r.lastActivityAt > r.lastReadAt)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: starling.colors.sage,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCalls(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final recent = ref.watch(recentVoiceRoomsProvider);

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            StarlingTopBar(
              title: 'Rooms',
              right: StarlingIconButton(
                onPressed: () => context.push('/voice/settings'),
                semanticLabel: 'Voice settings',
                child: const Icon(LucideIcons.settings, size: 20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PrimaryButton(
                label: 'Start a room',
                block: true,
                leading: const Icon(LucideIcons.phone, size: 18),
                onPressed: () => context.push('/voice/create'),
              ),
            ),
            Expanded(
              child: recent.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Couldn\'t load history',
                    style: starling.typography.small,
                  ),
                ),
                data: (rooms) {
                  if (rooms.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No recent calls yet. Start a room with a friend.',
                          textAlign: TextAlign.center,
                          style: starling.typography.small,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text('Recent', style: starling.typography.micro),
                      ),
                      for (final r in rooms)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: starling.colors.hairline,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.phoneCall,
                                size: 18,
                                color: starling.colors.stone,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      style: starling.typography.body.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r.participants.length} '
                                      'participant'
                                      '${r.participants.length == 1 ? '' : 's'}'
                                      ' · ${_ago(r.createdAt)}',
                                      style: starling.typography.micro,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ago(int unixSeconds) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final d = now - unixSeconds;
    if (d < 60) return 'just now';
    if (d < 3600) return '${d ~/ 60}m ago';
    if (d < 86400) return '${d ~/ 3600}h ago';
    return '${d ~/ 86400}d ago';
  }
}
