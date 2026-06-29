import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/models.dart';
import 'identity_provider.dart';
import 'service_providers.dart';

part 'comments_provider.g.dart';

/// Comments (kind=4) on the post identified by [postId], ordered ASC by
/// `created_at`, filtered to authors the local viewer follows or is
/// themselves. Tombstoned comments (kind=6 referencing the comment id by
/// the same author) are excluded.
///
/// Storage holds every received comment regardless of follow status — the
/// filter is at the read layer so following someone retroactively reveals
/// their old comments without a backfill.
@riverpod
Future<List<Event>> comments(Ref ref, String postId) async {
  final storage = ref.watch(storageServiceProvider);
  final identity = await ref.watch(identityControllerProvider.future);
  final follows = await storage.getFollows();
  final allowed = <String>{
    if (identity != null) identity.pubkey,
    ...follows.map((f) => f.pubkey),
  };

  final raw = await storage.getEventsByRef(postId, kind: EventKind.comment);
  final visible = raw.where((e) => allowed.contains(e.pubkey)).toList();

  // Filter out comments that have a kind=6 tombstone from the same author.
  final filtered = <Event>[];
  for (final comment in visible) {
    final tombstones = await storage.getEventsByRef(
      comment.id,
      kind: EventKind.delete,
    );
    final tombstoned = tombstones.any((t) => t.pubkey == comment.pubkey);
    if (!tombstoned) filtered.add(comment);
  }
  return filtered;
}

/// Create / delete a comment on [postId]. Invalidates [commentsProvider]
/// for the same post on every successful action so the post detail
/// screen rebuilds.
@riverpod
class CommentController extends _$CommentController {
  @override
  void build(String postId) {}

  Future<String> submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('comment text must not be empty');
    }
    final id = await ref
        .read(commentServiceProvider)
        .create(targetPostId: postId, text: trimmed);
    ref.invalidate(commentsProvider(postId));
    return id;
  }

  Future<void> delete(String commentId) async {
    await ref.read(commentServiceProvider).delete(commentId);
    ref.invalidate(commentsProvider(postId));
  }
}
