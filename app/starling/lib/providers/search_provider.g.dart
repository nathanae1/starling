// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Local-only search query. Debounced so each keystroke doesn't fan out to
/// a fresh storage scan + UI rebuild.

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

/// Local-only search query. Debounced so each keystroke doesn't fan out to
/// a fresh storage scan + UI rebuild.
final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  /// Local-only search query. Debounced so each keystroke doesn't fan out to
  /// a fresh storage scan + UI rebuild.
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'e1c5350a9cd6d99e2467260cca2c613f11c88299';

/// Local-only search query. Debounced so each keystroke doesn't fan out to
/// a fresh storage scan + UI rebuild.

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Filters the feed events (caption substring) and follows (display-name
/// substring) by the current [searchQueryProvider]. Empty query returns
/// empty results so the feed list-view falls back to its normal source.

@ProviderFor(searchResults)
final searchResultsProvider = SearchResultsProvider._();

/// Filters the feed events (caption substring) and follows (display-name
/// substring) by the current [searchQueryProvider]. Empty query returns
/// empty results so the feed list-view falls back to its normal source.

final class SearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<SearchResults>,
          SearchResults,
          FutureOr<SearchResults>
        >
    with $FutureModifier<SearchResults>, $FutureProvider<SearchResults> {
  /// Filters the feed events (caption substring) and follows (display-name
  /// substring) by the current [searchQueryProvider]. Empty query returns
  /// empty results so the feed list-view falls back to its normal source.
  SearchResultsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchResultsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchResultsHash();

  @$internal
  @override
  $FutureProviderElement<SearchResults> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SearchResults> create(Ref ref) {
    return searchResults(ref);
  }
}

String _$searchResultsHash() => r'2ee5783c507445c90953c05a176ea9d10dad2c14';
