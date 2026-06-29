import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/feed_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/sync_provider.dart';
import '../../theme/starling_theme.dart';
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
        // Trigger a real LAN sync, then re-read local storage so any
        // newly-stored events surface in the list.
        try {
          await ref.read(syncControllerProvider.notifier).syncNow();
        } catch (_) {
          // Sync errors are surfaced through `syncStatusProvider`; the
          // refresh gesture itself shouldn't throw.
        }
        ref.invalidate(feedProvider);
        await ref.read(feedProvider.future);
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
        error: (e, _) => _ErrorState(message: '$e'),
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
      error: (e, _) => _ErrorState(message: '$e'),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: starling.typography.small.copyWith(
            color: starling.colors.danger,
          ),
        ),
      ),
    );
  }
}
