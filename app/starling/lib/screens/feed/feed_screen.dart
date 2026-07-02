import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/feed_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/sync_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/buttons.dart';
import '../../widgets/empty_feed.dart';
import 'feed_sync_search_bar.dart';
import 'post_card.dart';

/// Top-level Feed tab content. The `FeedSyncSearchBar` is the only chrome
/// above the post list (no `TopBar`). When the user is searching, the list
/// switches to `searchResultsProvider` output.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final query = ref.watch(searchQueryProvider);
    final isSearching = query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const FeedSyncSearchBar(),
            Expanded(
              child: isSearching
                  ? const _SearchResultsList()
                  : const _FeedList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);
    return RefreshIndicator(
      onRefresh: () async {
        // Kick a real sync, but release the spinner after ~6 s — a full
        // multi-peer pass can take minutes over Tor with offline friends.
        // The sync keeps running; the status row's "Loading feeds…" carries
        // the long tail, and the reactive feed stream surfaces results as
        // they're stored.
        try {
          await ref
              .read(syncControllerProvider.notifier)
              .syncNow()
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          // Sync errors (and the timeout) are surfaced through
          // `syncStatusProvider`; the refresh gesture itself shouldn't throw.
        }
      },
      child: feedAsync.when(
        data: (events) {
          if (events.isEmpty) {
            final hasFollows =
                (ref.watch(followsStreamProvider).value ?? const []).isNotEmpty;
            return _EmptyScroll(
              child: hasFollows ? const _NoPostsYet() : const EmptyFeed(),
            );
          }
          return _PostListView(events: events);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: friendlyError(e, tag: 'feed'),
          onRetry: () => ref.invalidate(feedProvider),
        ),
      ),
    );
  }
}

class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final resultsAsync = ref.watch(searchResultsProvider);
    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return _EmptyScroll(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 64),
              child: Text(
                'Nothing matched.',
                textAlign: TextAlign.center,
                style: starling.typography.small,
              ),
            ),
          );
        }
        return _PostListView(events: results.events, trailing: false);
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _ErrorState(
        message: friendlyError(e, tag: 'search'),
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
    );
  }
}

class _PostListView extends StatelessWidget {
  const _PostListView({required this.events, this.trailing = true});

  final List<Event> events;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final extra = trailing ? 1 : 0;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      itemCount: events.length + extra,
      itemBuilder: (context, index) {
        if (index >= events.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
            child: Center(
              child: Text(
                "you're all caught up.",
                style: starling.typography.quote.copyWith(
                  fontSize: 16,
                  color: starling.colors.stone,
                ),
              ),
            ),
          );
        }
        final event = events[index];
        return PostCard(
          event: event,
          onTap: () => context.push('/feed/post/${event.id}'),
        );
      },
    );
  }
}

class _NoPostsYet extends StatelessWidget {
  const _NoPostsYet();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No posts yet',
            textAlign: TextAlign.center,
            style: starling.typography.h2,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to check for new posts from your friends — or share '
            'the first one yourself.',
            textAlign: TextAlign.center,
            style: starling.typography.small,
          ),
          const SizedBox(height: 24),
          Align(
            child: PrimaryButton(
              label: 'Share your first post',
              onPressed: () => context.push('/compose'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyScroll extends StatelessWidget {
  const _EmptyScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [child],
    );
  }
}

/// Scrollable (so `RefreshIndicator` can still arm on top of it) error state
/// with an in-UI retry — never a dead-end `Center`.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return _EmptyScroll(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 96, 24, 64),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: starling.typography.small.copyWith(
                color: starling.colors.danger,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              SecondaryButton(label: 'Try again', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
