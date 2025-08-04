import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

class BlobData {
  final String id;
  final Uint8List data;
  final DateTime lastModified;

  BlobData({required this.id, required this.data, DateTime? lastModified})
    : lastModified = lastModified ?? DateTime.now();

  BlobData copyWith({String? id, Uint8List? data, DateTime? lastModified}) {
    return BlobData(
      id: id ?? this.id,
      data: data ?? this.data,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  int get sizeInBytes => data.length;
}

@JsonSerializable()
class EvictionStats {
  final int memoryEvictions;
  final int diskEvictions;
  final int memoryEvictedBytes;
  final int diskEvictedBytes;
  final DateTime timestamp;

  const EvictionStats({
    required this.memoryEvictions,
    required this.diskEvictions,
    required this.memoryEvictedBytes,
    required this.diskEvictedBytes,
    required this.timestamp,
  });

  factory EvictionStats.fromJson(Map<String, dynamic> json) =>
      _$EvictionStatsFromJson(json);

  Map<String, dynamic> toJson() => _$EvictionStatsToJson(this);
}

@JsonSerializable()
class ServiceStatus {
  final int memoryItemCount;
  final int diskItemCount;
  final int memoryBytesUsed;
  final int diskBytesUsed;
  final List<EvictionStats> evictionHistory;
  final DateTime timestamp;

  const ServiceStatus({
    required this.memoryItemCount,
    required this.diskItemCount,
    required this.memoryBytesUsed,
    required this.diskBytesUsed,
    required this.evictionHistory,
    required this.timestamp,
  });

  factory ServiceStatus.fromJson(Map<String, dynamic> json) =>
      _$ServiceStatusFromJson(json);

  Map<String, dynamic> toJson() => _$ServiceStatusToJson(this);
}
