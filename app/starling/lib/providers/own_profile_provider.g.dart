// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'own_profile_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reads the latest kind=2 event for own pubkey and decodes its JSON content
/// into a profile snapshot. Falls back to "You" with no avatar when no
/// profile event has been written yet (e.g. a restore that hasn't re-synced)
/// or the content is malformed.

@ProviderFor(ownProfile)
final ownProfileProvider = OwnProfileProvider._();

/// Reads the latest kind=2 event for own pubkey and decodes its JSON content
/// into a profile snapshot. Falls back to "You" with no avatar when no
/// profile event has been written yet (e.g. a restore that hasn't re-synced)
/// or the content is malformed.

final class OwnProfileProvider
    extends
        $FunctionalProvider<
          AsyncValue<OwnProfileSnapshot>,
          OwnProfileSnapshot,
          FutureOr<OwnProfileSnapshot>
        >
    with
        $FutureModifier<OwnProfileSnapshot>,
        $FutureProvider<OwnProfileSnapshot> {
  /// Reads the latest kind=2 event for own pubkey and decodes its JSON content
  /// into a profile snapshot. Falls back to "You" with no avatar when no
  /// profile event has been written yet (e.g. a restore that hasn't re-synced)
  /// or the content is malformed.
  OwnProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownProfileProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownProfileHash();

  @$internal
  @override
  $FutureProviderElement<OwnProfileSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<OwnProfileSnapshot> create(Ref ref) {
    return ownProfile(ref);
  }
}

String _$ownProfileHash() => r'17823a230154a3d4859948541b1f06e4aa5068f9';
