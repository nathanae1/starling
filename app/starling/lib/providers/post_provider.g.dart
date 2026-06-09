// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(postService)
final postServiceProvider = PostServiceProvider._();

final class PostServiceProvider
    extends $FunctionalProvider<PostService, PostService, PostService>
    with $Provider<PostService> {
  PostServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'postServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$postServiceHash();

  @$internal
  @override
  $ProviderElement<PostService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PostService create(Ref ref) {
    return postService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PostService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PostService>(value),
    );
  }
}

String _$postServiceHash() => r'f042c4f8323594a0332cd8cae9d0e7e1fdc61ad9';
