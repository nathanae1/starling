import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/bookmark_provider.dart';
import '../theme/starling_theme.dart';
import 'buttons.dart';

/// Bookmark/save toggle for an event row. Outline graphite when unsaved,
/// sage-deep filled when saved. Pure local — no event produced, no sync.
class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({super.key, required this.eventId, this.iconSize = 22});

  final String eventId;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final savedAsync = ref.watch(eventSavedProvider(eventId));
    final isSaved = savedAsync.maybeWhen(data: (v) => v, orElse: () => false);

    return StarlingIconButton(
      onPressed: () =>
          ref.read(bookmarkControllerProvider(eventId).notifier).toggle(),
      semanticLabel: isSaved ? 'Remove bookmark' : 'Bookmark',
      child: Icon(
        isSaved ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
        size: iconSize,
        color: isSaved ? starling.colors.sageDeep : starling.colors.graphite,
      ),
    );
  }
}
