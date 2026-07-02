// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'minute_ticker_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shared 60 s heartbeat for relative-time labels ("synced 4m ago", post
/// timestamps, friend last-seen). Widgets watch this next to `clockProvider`
/// so their labels re-compute each minute without every widget owning its
/// own `Timer`. Auto-disposes when no relative-time label is on screen.

@ProviderFor(minuteTicker)
final minuteTickerProvider = MinuteTickerProvider._();

/// Shared 60 s heartbeat for relative-time labels ("synced 4m ago", post
/// timestamps, friend last-seen). Widgets watch this next to `clockProvider`
/// so their labels re-compute each minute without every widget owning its
/// own `Timer`. Auto-disposes when no relative-time label is on screen.

final class MinuteTickerProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// Shared 60 s heartbeat for relative-time labels ("synced 4m ago", post
  /// timestamps, friend last-seen). Widgets watch this next to `clockProvider`
  /// so their labels re-compute each minute without every widget owning its
  /// own `Timer`. Auto-disposes when no relative-time label is on screen.
  MinuteTickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'minuteTickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$minuteTickerHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return minuteTicker(ref);
  }
}

String _$minuteTickerHash() => r'88931b450d92502e1a5d79ef3ba0a8a7b50d8fb9';
