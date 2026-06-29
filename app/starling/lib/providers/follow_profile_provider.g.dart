// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_profile_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(followProfile)
final followProfileProvider = FollowProfileFamily._();

final class FollowProfileProvider
    extends
        $FunctionalProvider<
          AsyncValue<FollowProfileSnapshot>,
          FollowProfileSnapshot,
          FutureOr<FollowProfileSnapshot>
        >
    with
        $FutureModifier<FollowProfileSnapshot>,
        $FutureProvider<FollowProfileSnapshot> {
  FollowProfileProvider._({
    required FollowProfileFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'followProfileProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$followProfileHash();

  @override
  String toString() {
    return r'followProfileProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<FollowProfileSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<FollowProfileSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return followProfile(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FollowProfileProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$followProfileHash() => r'd02d5ea6e4e516fa9c0385a882af62c6f1048f91';

final class FollowProfileFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<FollowProfileSnapshot>, String> {
  FollowProfileFamily._()
    : super(
        retry: null,
        name: r'followProfileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FollowProfileProvider call(String pubkey) =>
      FollowProfileProvider._(argument: pubkey, from: this);

  @override
  String toString() => r'followProfileProvider';
}
