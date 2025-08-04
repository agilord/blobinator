// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BlobinatorConfig _$BlobinatorConfigFromJson(Map<String, dynamic> json) =>
    BlobinatorConfig(
      maxMemoryItems: (json['maxMemoryItems'] as num?)?.toInt() ?? 1000000,
      maxDiskItems: (json['maxDiskItems'] as num?)?.toInt() ?? 100000000,
      maxMemoryBytes:
          (json['maxMemoryBytes'] as num?)?.toInt() ?? 1024 * 1024 * 1024,
      maxDiskBytes:
          (json['maxDiskBytes'] as num?)?.toInt() ?? 512 * 1024 * 1024 * 1024,
      memoryTtl: json['memoryTtl'] == null
          ? const Duration(days: 3)
          : Duration(microseconds: (json['memoryTtl'] as num).toInt()),
      diskTtl: json['diskTtl'] == null
          ? const Duration(days: 90)
          : Duration(microseconds: (json['diskTtl'] as num).toInt()),
      port: (json['port'] as num?)?.toInt() ?? 8080,
      diskStoragePath: json['diskStoragePath'] as String?,
    );

Map<String, dynamic> _$BlobinatorConfigToJson(BlobinatorConfig instance) =>
    <String, dynamic>{
      'maxMemoryItems': instance.maxMemoryItems,
      'maxDiskItems': instance.maxDiskItems,
      'maxMemoryBytes': instance.maxMemoryBytes,
      'maxDiskBytes': instance.maxDiskBytes,
      'memoryTtl': instance.memoryTtl.inMicroseconds,
      'diskTtl': instance.diskTtl.inMicroseconds,
      'port': instance.port,
      'diskStoragePath': instance.diskStoragePath,
    };
