import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/compose_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/post_provider.dart';
import '../../providers/publish_activity_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sticky_action_bar.dart';

class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key});

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  bool _isPublishing = false;
  String? _error;

  Future<void> _publish() async {
    final state = ref.read(composeControllerProvider);
    final bytes = state.photoBytes;
    if (bytes == null) return;
    setState(() {
      _isPublishing = true;
      _error = null;
    });
    ref.read(composeControllerProvider.notifier).markPublishing();
    // Capture the notifier up front (the widget is popped on success, after
    // which its `ref` is unsafe) and clear the flag in `finally` so the sync
    // indicator's "Publishing…" state always resolves.
    final publishActivity = ref.read(publishActivityProvider.notifier);
    publishActivity.begin();
    try {
      await ref
          .read(postServiceProvider)
          .createPost(photoBytes: bytes, caption: state.caption);
      ref.invalidate(ownEventsProvider);
      ref.invalidate(feedProvider);
      ref.invalidate(ownPostsProvider);
      if (!mounted) return;
      // Pop preview + compose first, then invalidate the compose provider
      // after the modal is torn down. Invalidating while both screens are
      // still mounted causes a markNeedsBuild-during-build storm because
      // both subscribe to the same provider.
      context.pop();
      if (context.canPop()) context.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(composeControllerProvider);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isPublishing = false;
        _error = "Couldn't publish. Try again.";
      });
      ref.read(composeControllerProvider.notifier).markPublishFailed('$e');
    } finally {
      publishActivity.end();
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final state = ref.watch(composeControllerProvider);
    final bytes = state.photoBytes;

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                    ),
                  if (state.caption.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(state.caption, style: starling.typography.body),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: starling.typography.small.copyWith(
                        color: starling.colors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: StickyActionBar(
              child: Row(
                children: [
                  GhostButton(
                    label: 'Back to edit',
                    onPressed: _isPublishing ? null : () => context.pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: _isPublishing ? 'Posting…' : 'Post',
                      block: true,
                      onPressed: _isPublishing ? null : _publish,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
