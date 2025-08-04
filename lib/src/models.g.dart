// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EvictionStats _$EvictionStatsFromJson(Map<String, dynamic> json) =>
    EvictionStats(
      memoryEvictions: (json['memoryEvictions'] as num).toInt(),
      diskEvictions: (json['diskEvictions'] as num).toInt(),
      memoryEvictedBytes: (json['memoryEvictedBytes'] as num).toInt(),
      diskEvictedBytes: (json['diskEvictedBytes'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$EvictionStatsToJson(EvictionStats instance) =>
    <String, dynamic>{
      'memoryEvictions': instance.memoryEvictions,
      'diskEvictions': instance.diskEvictions,
      'memoryEvictedBytes': instance.memoryEvictedBytes,
      'diskEvictedBytes': instance.diskEvictedBytes,
      'timestamp': instance.timestamp.toIso8601String(),
    };

ServiceStatus _$ServiceStatusFromJson(Map<String, dynamic> json) =>
    ServiceStatus(
      memoryItemCount: (json['memoryItemCount'] as num).toInt(),
      diskItemCount: (json['diskItemCount'] as num).toInt(),
      memoryBytesUsed: (json['memoryBytesUsed'] as num).toInt(),
      diskBytesUsed: (json['diskBytesUsed'] as num).toInt(),
      evictionHistory: (json['evictionHistory'] as List<dynamic>)
          .map((e) => EvictionStats.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$ServiceStatusToJson(ServiceStatus instance) =>
    <String, dynamic>{
      'memoryItemCount': instance.memoryItemCount,
      'diskItemCount': instance.diskItemCount,
      'memoryBytesUsed': instance.memoryBytesUsed,
      'diskBytesUsed': instance.diskBytesUsed,
      'evictionHistory': instance.evictionHistory,
      'timestamp': instance.timestamp.toIso8601String(),
    };
