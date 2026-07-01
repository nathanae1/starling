// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Lifecycle owner for the embedded [StarlingHttpServer]. The published
/// state is the bound port (or `null` while pre-onboarding / stopped),
/// so consumers like Plan 09 (mDNS) and Plan 11 (Tor) can `ref.watch` it.

@ProviderFor(HttpServerController)
final httpServerControllerProvider = HttpServerControllerProvider._();

/// Lifecycle owner for the embedded [StarlingHttpServer]. The published
/// state is the bound port (or `null` while pre-onboarding / stopped),
/// so consumers like Plan 09 (mDNS) and Plan 11 (Tor) can `ref.watch` it.
final class HttpServerControllerProvider
    extends $AsyncNotifierProvider<HttpServerController, int?> {
  /// Lifecycle owner for the embedded [StarlingHttpServer]. The published
  /// state is the bound port (or `null` while pre-onboarding / stopped),
  /// so consumers like Plan 09 (mDNS) and Plan 11 (Tor) can `ref.watch` it.
  HttpServerControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'httpServerControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$httpServerControllerHash();

  @$internal
  @override
  HttpServerController create() => HttpServerController();
}

String _$httpServerControllerHash() =>
    r'4889733437e1c38548ef6be30666eaec9a8e467a';

/// Lifecycle owner for the embedded [StarlingHttpServer]. The published
/// state is the bound port (or `null` while pre-onboarding / stopped),
/// so consumers like Plan 09 (mDNS) and Plan 11 (Tor) can `ref.watch` it.

abstract class _$HttpServerController extends $AsyncNotifier<int?> {
  FutureOr<int?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<int?>, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int?>, int?>,
              AsyncValue<int?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
