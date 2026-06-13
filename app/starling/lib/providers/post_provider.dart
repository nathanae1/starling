import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/post_service.dart';
import 'identity_provider.dart';
import 'media_provider.dart';
import 'relay_providers.dart';
import 'service_providers.dart';
import 'sync_provider.dart';

part 'post_provider.g.dart';

@riverpod
PostService postService(Ref ref) {
  // Resolved at build time: the publish callback below fires unawaited,
  // often after this autoDispose provider is torn down (the compose flow
  // pops right after publish), so it must not touch `ref`. The coordinator
  // provider is keepAlive, so the captured future stays valid.
  final relayPush = ref.watch(relayPushCoordinatorProvider.future);
  return DefaultPostService(
    contentKey: ref.watch(contentKeyServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    storage: ref.watch(storageServiceProvider),
    media: ref.watch(mediaServiceProvider),
    clock: ref.watch(clockProvider),
    identityLookup: () => ref.read(identityControllerProvider.future),
    fanout: ref.watch(postFanoutServiceProvider),
    // Plan 15: mirror each freshly-published event to the paired relay
    // (if any). Best-effort — the coordinator no-ops when no relay is
    // paired or Tor isn't ready.
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
