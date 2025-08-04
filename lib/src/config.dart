import 'package:json_annotation/json_annotation.dart';

part 'config.g.dart';

@JsonSerializable()
class BlobinatorConfig {
  final int maxMemoryItems;
  final int maxDiskItems;
  final int maxMemoryBytes;
  final int maxDiskBytes;
  final Duration memoryTtl;
  final Duration diskTtl;
  final int port;
  final String? diskStoragePath;

  const BlobinatorConfig({
    this.maxMemoryItems = 1000000,
    this.maxDiskItems = 100000000,
    this.maxMemoryBytes = 1024 * 1024 * 1024, // 1 GiB
    this.maxDiskBytes = 512 * 1024 * 1024 * 1024, // 512 GiB
    this.memoryTtl = const Duration(days: 3),
    this.diskTtl = const Duration(days: 90),
    this.port = 8080,
    this.diskStoragePath,
  });

  factory BlobinatorConfig.fromJson(Map<String, dynamic> json) =>
      _$BlobinatorConfigFromJson(json);

  Map<String, dynamic> toJson() => _$BlobinatorConfigToJson(this);
}
