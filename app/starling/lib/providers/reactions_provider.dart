import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/models.dart';
import 'identity_provider.dart';
import 'service_providers.dart';

part 'reactions_provider.g.dart';

/// Aggregated reaction state for a single post. The post detail screen
/// reads this for the heart's count + filled state; the post card reads
/// it for the inline count.
class ReactionSummary {
  const ReactionSummary({
    required this.count,
    required this.likedByMe,
    this.myLikeId,
  });

  /// Number of distinct authors with an active like on the post (no
  /// tombstone). Comments from non-followed authors still count — the
  /// "people you follow" filter only applies to comment display, not to
  /// like aggregates. The number reflects social temperature, not
  /// who-you-know.
  final int count;
  final bool likedByMe;
  final String? myLikeId;
}

@riverpod
Future<ReactionSummary> reactions(Ref ref, String postId) async {
  final storage = ref.watch(storageServiceProvider);
  final identity = await ref.watch(identityControllerProvider.future);

  final likes = await storage.getEventsByRef(postId, kind: EventKind.like);

  // Per-author latest like with no tombstone wins.
  final activeByAuthor = <String, Event>{};
  for (final like in likes) {
    final tombstones = await storage.getEventsByRef(
      like.id,
      kind: EventKind.delete,
    );
    final tombstoned = tombstones.any((t) => t.pubkey == like.pubkey);
    if (tombstoned) continue;
    final prior = activeByAuthor[like.pubkey];
    if (prior == null || like.createdAt > prior.createdAt) {
      activeByAuthor[like.pubkey] = like;
    }
  }

  String? myLikeId;
  var likedByMe = false;
  if (identity != null) {
    final mine = activeByAuthor[identity.pubkey];
    if (mine != null) {
      likedByMe = true;
      myLikeId = mine.id;
    }
  }

  return ReactionSummary(
    count: activeByAuthor.length,
    likedByMe: likedByMe,
    myLikeId: myLikeId,
  );
}

@riverpod
class ReactionController extends _$ReactionController {
  @override
  void build(String postId) {}

  /// Toggle the viewer's like on [postId]. If currently liked → unlike;
  /// otherwise → like. Invalidates the reaction summary so the heart
  /// updates immediately.
  Future<void> toggle() async {
    final service = ref.read(reactionServiceProvider);
    final liked = await service.isLikedByMe(postId);
    if (liked) {
      await service.unlike(postId);
    } else {
      await service.like(postId);
    }
    ref.invalidate(reactionsProvider(postId));
  }
}
