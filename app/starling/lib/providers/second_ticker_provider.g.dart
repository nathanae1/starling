// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'second_ticker_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A shared 1-second heartbeat for ticking call-duration displays (mm:ss).
/// The minute ticker is too coarse for that; keep this one scoped to
/// in-call UI so the app isn't rebuilding every second at rest —
/// auto-disposes when the last watcher (the call screens) unmounts.

@ProviderFor(secondTicker)
final secondTickerProvider = SecondTickerProvider._();

/// A shared 1-second heartbeat for ticking call-duration displays (mm:ss).
/// The minute ticker is too coarse for that; keep this one scoped to
/// in-call UI so the app isn't rebuilding every second at rest —
/// auto-disposes when the last watcher (the call screens) unmounts.

final class SecondTickerProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// A shared 1-second heartbeat for ticking call-duration displays (mm:ss).
  /// The minute ticker is too coarse for that; keep this one scoped to
  /// in-call UI so the app isn't rebuilding every second at rest —
  /// auto-disposes when the last watcher (the call screens) unmounts.
  SecondTickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secondTickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secondTickerHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return secondTicker(ref);
  }
}

String _$secondTickerHash() => r'd19bbe4cb02af802e77517182f7f80b1a1fe015c';
