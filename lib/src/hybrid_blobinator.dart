import 'dart:async';
import 'dart:typed_data';

import 'api.dart';
import 'config.dart';
import 'sqlite_blobinator.dart';

class HybridBlobinatorConfig extends BlobinatorConfig {
  final Duration migrationAge;
  final Duration cleanupInterval;
  final String? diskPath;

  HybridBlobinatorConfig({
    super.keyMaxLength,
    super.valueMaxLength,
    super.defaultTtl,
    this.migrationAge = const Duration(minutes: 5),
    this.cleanupInterval = const Duration(minutes: 1),
    this.diskPath,
  });
}

/// Hybrid blob storage that uses in-memory SQLite for fast access and
/// file-based SQLite for persistent storage. The entries are stored in
/// memory first, and migrated to the disk storage later.
class HybridBlobinator implements Blobinator {
  final SqliteBlobinator _memory;
  final SqliteBlobinator _disk;
  final HybridBlobinatorConfig _config;
  Timer? _cleanupTimer;

  HybridBlobinator({HybridBlobinatorConfig? config})
    : this._(config ?? HybridBlobinatorConfig());

  HybridBlobinator._(HybridBlobinatorConfig config)
    : _config = config,
      _memory = SqliteBlobinator.inMemory(config: config),
      _disk = config.diskPath != null
          ? SqliteBlobinator.inFile(config.diskPath!, config: config)
          : SqliteBlobinator.inMemory(config: config) {
    // Start cleanup tasks automatically
    _cleanupTimer = Timer.periodic(
      _config.cleanupInterval,
      (_) => _performCleanup(),
    );
  }

  @override
  Future<Blob?> getBlob(List<int> key) async {
    // Check memory first
    final memoryBlob = await _memory.getBlob(key);
    if (memoryBlob != null) {
      return memoryBlob;
    }

    // Check disk if not in memory
    return await _disk.getBlob(key);
  }

  @override
  Future<BlobMetadata?> getBlobMetadata(List<int> key) async {
    // Check memory first
    final memoryMetadata = await _memory.getBlobMetadata(key);
    if (memoryMetadata != null) {
      return memoryMetadata;
    }

    // Check disk if not in memory
    return await _disk.getBlobMetadata(key);
  }

  @override
  Future<bool> updateBlob(
    List<int> key,
    List<int> bytes, {
    List<int>? version,
    Duration? ttl,
  }) async {
    // Always write to memory first
    final memoryResult = await _memory.updateBlob(
      key,
      bytes,
      version: version,
      ttl: ttl,
    );

    if (!memoryResult) {
      // Version check failed in memory, check disk
      final diskBlob = await _disk.getBlob(key);
      if (diskBlob != null && !_versionsMatch(version, diskBlob.version)) {
        return false;
      }

      // Try again in memory (blob might have been migrated)
      return await _memory.updateBlob(key, bytes, version: version, ttl: ttl);
    }

    return true;
  }

  @override
  Future<bool> deleteBlob(List<int> key, {List<int>? version}) async {
    // Delete from both memory and disk
    final memoryResult = await _memory.deleteBlob(key, version: version);
    final diskResult = await _disk.deleteBlob(
      key,
      version: memoryResult ? null : version,
    );

    // Return success if either succeeded (blob exists in at least one)
    return memoryResult || diskResult;
  }

  @override
  Future<BlobStatistics> getStatistics() async {
    final memoryStats = await _memory.getStatistics();
    final diskStats = await _disk.getStatistics();

    return BlobStatistics(
      totalBlobCount: memoryStats.totalBlobCount + diskStats.totalBlobCount,
      totalKeysSize: memoryStats.totalKeysSize + diskStats.totalKeysSize,
      totalValuesSize: memoryStats.totalValuesSize + diskStats.totalValuesSize,
    );
  }

  /// Performs cleanup: migrates old blobs from memory to disk and removes them from memory.
  Future<void> _performCleanup() async {
    try {
      // First, clean up expired blobs from both stores
      await _memory.removeExpired();
      await _disk.removeExpired();

      // Get only blobs from memory that are old enough to migrate
      final now = DateTime.now();
      final migrationThreshold = now.subtract(_config.migrationAge);
      final memoryBlobs = await _memory.getBlobsOlderThan(migrationThreshold);

      if (memoryBlobs.isEmpty) return;

      // Process each blob for migration
      for (final entry in memoryBlobs.entries) {
        final keyBytes = entry.key;
        final createdAt = entry.value;
        await _migrateBlob(keyBytes, createdAt);
      }
    } catch (e) {
      print('Cleanup failed: $e');
    }
  }

  /// Migrates a single blob from memory to disk and removes it from memory.
  Future<void> _migrateBlob(Uint8List keyBytes, DateTime createdAt) async {
    try {
      // Get the blob from memory
      final memoryBlob = await _memory.getBlob(keyBytes);
      if (memoryBlob == null) {
        // Blob was removed since we scanned, skip it
        return;
      }

      // Check creation time again in case blob was updated
      final currentCreatedAt = await _memory.getBlobCreatedAt(keyBytes);
      if (currentCreatedAt == null || currentCreatedAt.isAfter(createdAt)) {
        // Blob was updated since we scanned, skip migration this time
        return;
      }

      // Store blob in disk with preserved metadata
      // Note: We don't have direct access to expiresAt, so we'll use null for now
      // This is a limitation of the current API that could be improved
      await _disk.storeBlobWithMetadata(
        keyBytes,
        memoryBlob.bytes,
        memoryBlob.version,
        createdAt,
        null, // expiresAt - we'd need another method to get this
      );

      // Remove from memory after successful migration
      await _memory.deleteBlob(keyBytes);
    } catch (e) {
      // Log error and continue with next blob
      print('Failed to migrate blob: $e');
    }
  }

  bool _versionsMatch(List<int>? expectedVersion, List<int> actualVersion) {
    if (expectedVersion == null) return true;
    if (expectedVersion.length != actualVersion.length) return false;
    for (int i = 0; i < expectedVersion.length; i++) {
      if (expectedVersion[i] != actualVersion[i]) return false;
    }
    return true;
  }

  /// Stops the hybrid blobinator and closes all resources.
  @override
  Future<void> close() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    await _memory.close();
    await _disk.close();
  }
}
