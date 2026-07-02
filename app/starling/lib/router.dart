import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/identity_provider.dart';
import 'screens/compose/compose_screen.dart';
import 'screens/compose/preview_screen.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/feed/post_detail_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/friends/scan_screen.dart';
import 'screens/onboarding/done_screen.dart';
import 'screens/onboarding/recovery_phrase_screen.dart';
import 'screens/onboarding/restore_screen.dart';
import 'screens/onboarding/setup_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/other_profile_screen.dart';
import 'screens/profile/own_profile_screen.dart';
import 'screens/settings/connection_settings_screen.dart';
import 'screens/settings/network_settings_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/storage_settings_screen.dart';
import 'screens/settings/voice_settings_screen.dart';
import 'screens/voice/active_room_screen.dart';
import 'screens/voice/create_room_screen.dart';
import 'screens/voice/room_list_screen.dart';
import 'screens/voice/room_screen.dart';
import 'shell/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _feedNavigatorKey = GlobalKey<NavigatorState>();
final _friendsNavigatorKey = GlobalKey<NavigatorState>();
final _roomsNavigatorKey = GlobalKey<NavigatorState>();
final _youNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/feed',
    refreshListenable: _IdentityRefresh(ref),
    redirect: (context, state) {
      final identity = ref.read(identityControllerProvider);
      final hasIdentity = identity.value != null;
      final isOnboarding = state.matchedLocation.startsWith('/onboarding');

      if (identity.isLoading) return null;
      if (!hasIdentity && !isOnboarding) return '/onboarding/welcome';
      // `/onboarding/recovery` and `/onboarding/done` are post-signup — the
      // identity already exists by the time we land on them, so exempt them
      // from the bounce that sends every other onboarding route to the feed
      // once onboarded. Without the recovery exemption, the identity
      // provider's async reload (kicked off inside `createIdentity()`)
      // re-fires this redirect via `_IdentityRefresh` and yanks the user off
      // the one screen that shows their recovery phrase.
      if (hasIdentity &&
          isOnboarding &&
          state.matchedLocation != '/onboarding/recovery' &&
          state.matchedLocation != '/onboarding/done') {
        return '/feed';
      }
      // iOS reports `/` as the platform's initial route, which overrides
      // `initialLocation`. We don't define a `/` route, so bounce it to
      // the feed for already-onboarded users.
      if (hasIdentity && state.matchedLocation == '/') return '/feed';
      return null;
    },
    routes: [
      // Onboarding (no shell)
      GoRoute(
        path: '/onboarding/welcome',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/setup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const SetupScreen(),
      ),
      GoRoute(
        path: '/onboarding/recovery',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const RecoveryPhraseScreen(),
      ),
      GoRoute(
        path: '/onboarding/restore',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const RestoreScreen(),
      ),
      GoRoute(
        path: '/onboarding/done',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const DoneScreen(),
      ),

      // Compose (root-level modal, pushed from the "Post" tab). The preview
      // screen is a nested push above the same root navigator, not another
      // fullscreen dialog — it slides in from the right, inside the same
      // modal chrome, so popping it returns to Compose.
      GoRoute(
        path: '/compose',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: ComposeScreen()),
        routes: [
          GoRoute(
            path: 'preview',
            parentNavigatorKey: _rootNavigatorKey,
            pageBuilder: (_, _) => const MaterialPage(child: PreviewScreen()),
          ),
        ],
      ),

      // Settings (root-level push, dismissed with back)
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'network',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (_, _) => const NetworkSettingsScreen(),
          ),
          GoRoute(
            path: 'storage',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (_, _) => const StorageSettingsScreen(),
          ),
          GoRoute(
            path: 'connection',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (_, _) => const ConnectionSettingsScreen(),
          ),
        ],
      ),

      // Profile editor (root-level push, dismissed with back). /invite was
      // removed in Plan 08 — share-invite opens QrInviteSheet directly.
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const EditProfileScreen(),
      ),

      // Plan 08 — fullscreen scan (modal over the Friends tab).
      GoRoute(
        path: '/friends/scan',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: ScanScreen()),
      ),
      GoRoute(
        path: '/friends/profile/:pubkey',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            OtherProfileScreen(pubkey: state.pathParameters['pubkey']!),
      ),

      // Tab shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _feedNavigatorKey,
            routes: [
              GoRoute(
                path: '/feed',
                builder: (_, _) => const FeedScreen(),
                routes: [
                  GoRoute(
                    path: 'post/:id',
                    builder: (_, state) =>
                        PostDetailScreen(eventId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'profile/:pubkey',
                    builder: (_, state) => OtherProfileScreen(
                      pubkey: state.pathParameters['pubkey']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _friendsNavigatorKey,
            routes: [
              GoRoute(
                path: '/friends',
                builder: (_, _) => const FriendsScreen(),
              ),
            ],
          ),
          // Plan 16 — voice rooms, promoted to a top-level tab. The active-call
          // screen stays pinned to the root navigator so it covers the tab bar
          // and CallOverlay can re-enter it from anywhere.
          StatefulShellBranch(
            navigatorKey: _roomsNavigatorKey,
            routes: [
              GoRoute(
                path: '/voice',
                builder: (_, _) => const RoomListScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (_, _) => const CreateRoomScreen(),
                  ),
                  GoRoute(
                    path: 'room',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (_, _) => const MaterialPage(
                      fullscreenDialog: true,
                      child: ActiveRoomScreen(),
                    ),
                  ),
                  // Plan 17 — the durable chatroom (text timeline + call
                  // affordance). Distinct from the root-pinned live-mesh
                  // screen above.
                  GoRoute(
                    path: 'room/:roomId',
                    builder: (context, state) =>
                        RoomScreen(roomId: state.pathParameters['roomId']!),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const VoiceSettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _youNavigatorKey,
            routes: [
              GoRoute(
                path: '/you',
                builder: (_, _) => const OwnProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'post/:id',
                    builder: (_, state) =>
                        PostDetailScreen(eventId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Bridges Riverpod's `identityControllerProvider` into GoRouter's
/// `refreshListenable`, so writing an identity in onboarding causes the
/// redirect rule to reevaluate and navigate to the feed.
class _IdentityRefresh extends ChangeNotifier {
  _IdentityRefresh(this._ref) {
    _sub = _ref.listen<AsyncValue<dynamic>>(
      identityControllerProvider,
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
