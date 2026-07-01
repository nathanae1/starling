import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/follow_requests_provider.dart';
import '../providers/room_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/voice_provider.dart';
import '../services/background/foreground_service_controller.dart';
import '../theme/starling_theme.dart';
import '../utils/feature_flags.dart';
import '../widgets/tab_bar.dart';
import '../widgets/voice/call_overlay.dart';
import '../widgets/voice/incoming_invite_sheet.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  // The shell has four branches (feed, friends, rooms, you); compose is a FAB.
  static const _branchToTab = [
    StarlingTab.feed,
    StarlingTab.friends,
    StarlingTab.rooms,
    StarlingTab.you,
  ];
  static const _tabToBranch = {
    StarlingTab.feed: 0,
    StarlingTab.friends: 1,
    StarlingTab.rooms: 2,
    StarlingTab.you: 3,
  };

  StarlingTab get _current => _branchToTab[navigationShell.currentIndex];

  Future<void> _kickSync(WidgetRef ref) async {
    try {
      await ref.read(syncControllerProvider.notifier).syncNow();
    } catch (_) {
      // Errors are surfaced through syncStatusProvider.
    }
  }

  void _onTap(BuildContext context, WidgetRef ref, StarlingTab tab) {
    if (tab == StarlingTab.feed) {
      // Tapping Feed always kicks a pull. syncNow() coalesces concurrent
      // calls so rapid taps are safe; errors surface via syncStatusProvider.
      unawaited(_kickSync(ref));
    }
    final targetIndex = _tabToBranch[tab]!;
    navigationShell.goBranch(
      targetIndex,
      initialLocation: targetIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final inboundCount =
        ref.watch(inboundRequestsStreamProvider).value?.length ?? 0;
    // Plan 17: unread chatroom activity badge on the Rooms tab.
    final unreadRooms = kChatroomsEnabled
        ? (ref.watch(unreadRoomsCountProvider).value ?? 0)
        : 0;
    // Hide the compose FAB while a voice call is active so it can't collide
    // with the CallOverlay banner pinned above the tab bar.
    final inCall =
        kVoiceEnabled && ref.watch(voiceRoomStateProvider).value != null;

    if (kVoiceEnabled) {
      // Surface an inbound voice invite as a modal sheet from anywhere in the
      // tab shell (Plan 16). The room manager auto-declines if we're busy, so
      // no invite reaches here mid-call.
      ref.listen(incomingVoiceInvitesProvider, (_, next) {
        final invite = next.value;
        if (invite != null) {
          showIncomingInviteSheet(context, invite);
        }
      });

      // Keep the Android foreground-service microphone type in sync with call
      // state (Plan 16): a live call (non-null state) advertises `microphone`
      // so audio survives backgrounding on Android 14+; ending the call
      // downgrades to dataSync-only or stops. No-op on iOS/desktop.
      ref.listen(voiceRoomStateProvider, (_, next) {
        unawaited(
          ForegroundServiceController.instance.setCallActive(
            next.value != null,
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: Column(
        children: [
          Expanded(child: navigationShell),
          if (kVoiceEnabled) const CallOverlay(),
        ],
      ),
      floatingActionButton: inCall
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/compose'),
              backgroundColor: starling.colors.sage,
              foregroundColor: const Color(0xFFFDFBF5),
              elevation: 2,
              tooltip: 'New post',
              child: const Icon(LucideIcons.plus),
            ),
      bottomNavigationBar: StarlingBottomTabBar(
        current: _current,
        onTap: (t) => _onTap(context, ref, t),
        badges: {
          StarlingTab.friends: inboundCount,
          if (unreadRooms > 0) StarlingTab.rooms: unreadRooms,
        },
      ),
    );
  }
}
