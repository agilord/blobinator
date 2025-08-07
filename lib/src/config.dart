class BlobinatorConfig {
  final int? keyMaxLength;
  final int? valueMaxLength;
  final Duration? defaultTtl;

  BlobinatorConfig({this.keyMaxLength, this.valueMaxLength, this.defaultTtl});
}
