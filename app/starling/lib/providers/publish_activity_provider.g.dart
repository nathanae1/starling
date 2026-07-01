// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'publish_activity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Number of in-flight publish operations (compose → immediate fanout). Fresh
/// posts fan out on a separate path from the sync engine, so this is what lets
/// the sync indicator show "Publishing…" (vs "Loading feeds…"). A counter, not
/// a bool, so overlapping publishes don't clear the indicator early; read as
/// `> 0`. keepAlive so the count is stable across listener churn.

@ProviderFor(PublishActivity)
final publishActivityProvider = PublishActivityProvider._();

/// Number of in-flight publish operations (compose → immediate fanout). Fresh
/// posts fan out on a separate path from the sync engine, so this is what lets
/// the sync indicator show "Publishing…" (vs "Loading feeds…"). A counter, not
/// a bool, so overlapping publishes don't clear the indicator early; read as
/// `> 0`. keepAlive so the count is stable across listener churn.
final class PublishActivityProvider
    extends $NotifierProvider<PublishActivity, int> {
  /// Number of in-flight publish operations (compose → immediate fanout). Fresh
  /// posts fan out on a separate path from the sync engine, so this is what lets
  /// the sync indicator show "Publishing…" (vs "Loading feeds…"). A counter, not
  /// a bool, so overlapping publishes don't clear the indicator early; read as
  /// `> 0`. keepAlive so the count is stable across listener churn.
  PublishActivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'publishActivityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$publishActivityHash();

  @$internal
  @override
  PublishActivity create() => PublishActivity();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$publishActivityHash() => r'145eab2c106c5a214df2c95379607791155161c6';

/// Number of in-flight publish operations (compose → immediate fanout). Fresh
/// posts fan out on a separate path from the sync engine, so this is what lets
/// the sync indicator show "Publishing…" (vs "Loading feeds…"). A counter, not
/// a bool, so overlapping publishes don't clear the indicator early; read as
/// `> 0`. keepAlive so the count is stable across listener churn.

abstract class _$PublishActivity extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
