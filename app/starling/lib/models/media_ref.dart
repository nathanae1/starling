class MediaRef {
  const MediaRef({
    required this.hash,
    required this.mimeType,
    required this.size,
  });

  final String hash;
  final String mimeType;
  final int size;

  Map<String, dynamic> toMap() => {
    'hash': hash,
    'mime_type': mimeType,
    'size': size,
  };

  static MediaRef fromMap(Map<dynamic, dynamic> map) => MediaRef(
    hash: map['hash'] as String,
    mimeType: map['mime_type'] as String,
    size: map['size'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaRef &&
          hash == other.hash &&
          mimeType == other.mimeType &&
          size == other.size;

  @override
  int get hashCode => Object.hash(hash, mimeType, size);

  @override
  String toString() =>
      'MediaRef(hash: $hash, mimeType: $mimeType, size: $size)';

  MediaRef copyWith({String? hash, String? mimeType, int? size}) => MediaRef(
    hash: hash ?? this.hash,
    mimeType: mimeType ?? this.mimeType,
    size: size ?? this.size,
  );
}
