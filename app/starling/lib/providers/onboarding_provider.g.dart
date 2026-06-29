// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(OnboardingController)
final onboardingControllerProvider = OnboardingControllerProvider._();

final class OnboardingControllerProvider
    extends $NotifierProvider<OnboardingController, OnboardingSession> {
  OnboardingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingControllerHash();

  @$internal
  @override
  OnboardingController create() => OnboardingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnboardingSession value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnboardingSession>(value),
    );
  }
}

String _$onboardingControllerHash() =>
    r'5288597e47b6850ad69c0221a67c50df807e6ecf';

abstract class _$OnboardingController extends $Notifier<OnboardingSession> {
  OnboardingSession build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<OnboardingSession, OnboardingSession>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OnboardingSession, OnboardingSession>,
              OnboardingSession,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
