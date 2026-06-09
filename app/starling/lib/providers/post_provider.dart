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
      final coord = await ref.read(relayPushCoordinatorProvider.future);
      await coord?.pushPublished(signed, bytes);
    },
    publishLock: ref.watch(publishLockProvider),
  );
}
