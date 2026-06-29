import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/profile_service.dart';
import 'media_provider.dart';
import 'relay_providers.dart';
import 'service_providers.dart';
import 'sync_provider.dart';

part 'profile_service_provider.g.dart';

@riverpod
ProfileService profileService(Ref ref) {
  // Mirrors postServiceProvider. The onPublished callback fires unawaited,
  // often after this autoDispose provider is torn down (the edit/onboarding
  // flow pops right after publish), so it must not touch `ref`. The
  // coordinator provider is keepAlive, so the captured future stays valid.
  final relayPush = ref.watch(relayPushCoordinatorProvider.future);
  return DefaultProfileService(
    contentKey: ref.watch(contentKeyServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    storage: ref.watch(storageServiceProvider),
    media: ref.watch(mediaServiceProvider),
    clock: ref.watch(clockProvider),
    // Storage-based lookup (like commentService) so this resolves during
    // onboarding before the identity controller has refreshed.
    identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
    fanout: ref.watch(postFanoutServiceProvider),
    // Plan 15: mirror the freshly-published profile to the paired relay (if
    // any). Best-effort — no-ops when no relay is paired or Tor isn't ready.
    onPublished: (signed, bytes) async {
      try {
        final coord = await relayPush;
        await coord?.pushPublished(signed, bytes);
      } catch (_) {
        // Best-effort; the next reconcile pass heals a missed mirror.
      }
    },
    publishLock: ref.watch(publishLockProvider),
  );
}
