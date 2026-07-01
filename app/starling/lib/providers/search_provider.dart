import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/models.dart';
import '../services/types.dart';
import 'feed_provider.dart';

part 'search_provider.g.dart';

/// Local-only search query. Debounced so each keystroke doesn't fan out to
/// a fresh storage scan + UI rebuild.
@riverpod
class SearchQuery extends _$SearchQuery {
  Timer? _debounce;

  @override
  String build() {
    ref.onDispose(() => _debounce?.cancel());
    return '';
  }

  void set(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      state = value;
    });
  }

  void clear() {
    _debounce?.cancel();
    state = '';
  }
}

class SearchResults {
  const SearchResults({required this.events, required this.follows});
  final List<Event> events;
  final List<Follow> follows;

  bool get isEmpty => events.isEmpty && follows.isEmpty;
}

/// Filters the feed events (caption substring) and follows (display-name
/// substring) by the current [searchQueryProvider]. Empty query returns
/// empty results so the feed list-view falls back to its normal source.
@riverpod
Future<SearchResults> searchResults(Ref ref) async {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) {
    return const SearchResults(events: [], follows: []);
  }
  // Subscribe synchronously before the await — using `ref` after an await is
  // illegal if the provider was invalidated during it.
  final feed = await ref.watch(feedProvider.future);

  final matchedEvents = feed.where((e) {
    if (e.content.isEmpty) return false;
    final caption = utf8.decode(e.content, allowMalformed: true).toLowerCase();
    return caption.contains(query);
  }).toList();

  // Friend-name matching previously read the follow row's cached display name,
  // which is vestigial — a friend's name now comes from their kind=2 profile
  // (followProfileProvider), not the follow row. Resolving profile names in
  // search is a separate enhancement; until then friend results stay empty.
  return SearchResults(events: matchedEvents, follows: const []);
}
