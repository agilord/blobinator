import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'config.dart';
import 'models.dart';

class BlobStorage {
  final BlobinatorConfig config;
  final Map<String, BlobData> _memoryStorage = {};
  final List<EvictionStats> _evictionHistory = [];

  int _memoryBytesUsed = 0;
  int _diskBytesUsed = 0;
  int _diskItemCount = 0;

  BlobStorage(this.config);

  String _getBlobPath(String blobId) {
    final hash = md5.convert(utf8.encode(blobId)).toString();
    final dir1 = hash.substring(0, 2);
    final dir2 = hash.substring(2, 4);
    return path.join(config.diskStoragePath!, dir1, dir2, blobId);
  }

  Future<void> _ensureDirectory(String filePath) async {
    final dir = Directory(path.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  bool _isValidBlobId(String blobId) {
    if (blobId.length < 4 || blobId.length > 512) return false;
    return RegExp(r'^[a-z0-9._-]+$').hasMatch(blobId);
  }

  Future<BlobData?> get(String blobId) async {
    if (!_isValidBlobId(blobId)) return null;

    if (_memoryStorage.containsKey(blobId)) {
      return _memoryStorage[blobId];
    }

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      final file = File(filePath);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        final stat = await file.stat();
        return BlobData(
          id: blobId,
          data: Uint8List.fromList(data),
          lastModified: stat.modified,
        );
      }
    }

    return null;
  }

  Future<bool> exists(String blobId) async {
    if (!_isValidBlobId(blobId)) return false;

    if (_memoryStorage.containsKey(blobId)) {
      return true;
    }

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      return await File(filePath).exists();
    }

    return false;
  }

  Future<int> getSize(String blobId) async {
    if (!_isValidBlobId(blobId)) return -1;

    if (_memoryStorage.containsKey(blobId)) {
      return _memoryStorage[blobId]!.sizeInBytes;
    }

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    }

    return -1;
  }

  Future<DateTime?> getLastModified(String blobId) async {
    if (!_isValidBlobId(blobId)) return null;

    if (_memoryStorage.containsKey(blobId)) {
      return _memoryStorage[blobId]!.lastModified;
    }

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified;
      }
    }

    return null;
  }

  Future<void> put(String blobId, Uint8List data) async {
    if (!_isValidBlobId(blobId)) {
      throw ArgumentError('Invalid blob ID: $blobId');
    }

    final now = DateTime.now();
    final blobData = BlobData(id: blobId, data: data, lastModified: now);

    if (_memoryStorage.containsKey(blobId)) {
      _memoryBytesUsed -= _memoryStorage[blobId]!.sizeInBytes;
    }

    _memoryStorage[blobId] = blobData;
    _memoryBytesUsed += data.length;

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      final file = File(filePath);

      if (await file.exists()) {
        final oldSize = await file.length();
        _diskBytesUsed -= oldSize;
        _diskItemCount--;
      }

      await _ensureDirectory(filePath);
      await file.writeAsBytes(data);
      await file.setLastModified(now);
      _diskBytesUsed += data.length;
      _diskItemCount++;
    }

    await _checkMemoryLimits();
  }

  Future<bool> delete(String blobId) async {
    if (!_isValidBlobId(blobId)) return false;

    bool deleted = false;

    if (_memoryStorage.containsKey(blobId)) {
      _memoryBytesUsed -= _memoryStorage[blobId]!.sizeInBytes;
      _memoryStorage.remove(blobId);
      deleted = true;
    }

    if (config.diskStoragePath != null) {
      final filePath = _getBlobPath(blobId);
      final file = File(filePath);
      if (await file.exists()) {
        final size = await file.length();
        await file.delete();
        _diskBytesUsed -= size;
        _diskItemCount--;
        deleted = true;
      }
    }

    return deleted;
  }

  Future<void> _checkMemoryLimits() async {
    int evicted = 0;
    int evictedBytes = 0;

    while (_memoryStorage.length > config.maxMemoryItems ||
        _memoryBytesUsed > config.maxMemoryBytes) {
      if (_memoryStorage.isEmpty) break;

      final oldestEntry = _memoryStorage.entries.reduce(
        (a, b) => a.value.lastModified.isBefore(b.value.lastModified) ? a : b,
      );

      if (config.diskStoragePath != null) {
        await _moveToMemoryToDisk(oldestEntry.key, oldestEntry.value);
      }

      _memoryBytesUsed -= oldestEntry.value.sizeInBytes;
      _memoryStorage.remove(oldestEntry.key);
      evicted++;
      evictedBytes += oldestEntry.value.sizeInBytes;
    }

    if (evicted > 0) {
      _recordEviction(evicted, 0, evictedBytes, 0);
    }
  }

  Future<void> _moveToMemoryToDisk(String blobId, BlobData blobData) async {
    final filePath = _getBlobPath(blobId);
    final file = File(filePath);

    if (!await file.exists()) {
      await _ensureDirectory(filePath);
      await file.writeAsBytes(blobData.data);
      await file.setLastModified(blobData.lastModified);
      _diskBytesUsed += blobData.sizeInBytes;
      _diskItemCount++;
    }
  }

  Future<void> checkMemoryTtl() async {
    final cutoff = DateTime.now().subtract(config.memoryTtl);
    final toRemove = <String>[];
    int evictedBytes = 0;

    for (final entry in _memoryStorage.entries) {
      if (entry.value.lastModified.isBefore(cutoff)) {
        toRemove.add(entry.key);
        evictedBytes += entry.value.sizeInBytes;
      }
    }

    for (final id in toRemove) {
      final blobData = _memoryStorage[id]!;
      if (config.diskStoragePath != null) {
        await _moveToMemoryToDisk(id, blobData);
      }
      _memoryBytesUsed -= blobData.sizeInBytes;
      _memoryStorage.remove(id);
    }

    if (toRemove.isNotEmpty) {
      _recordEviction(toRemove.length, 0, evictedBytes, 0);
    }
  }

  Future<void> checkDiskLimits() async {
    if (config.diskStoragePath == null) return;

    await _scanDiskUsage();

    int evicted = 0;
    int evictedBytes = 0;
    final cutoff = DateTime.now().subtract(config.diskTtl);

    final diskFiles = await _getAllDiskFiles();
    diskFiles.sort((a, b) => a.lastModified.compareTo(b.lastModified));

    final deletedDirs = <String>{};

    for (final fileInfo in diskFiles) {
      final shouldEvictSize =
          _diskItemCount > config.maxDiskItems ||
          _diskBytesUsed > config.maxDiskBytes;
      final shouldEvictTtl = fileInfo.lastModified.isBefore(cutoff);

      if (shouldEvictSize || shouldEvictTtl) {
        final file = File(fileInfo.path);
        if (await file.exists()) {
          final size = await file.length();
          final dirPath = path.dirname(fileInfo.path);
          await file.delete();
          _diskBytesUsed -= size;
          _diskItemCount--;
          evicted++;
          evictedBytes += size;

          // Try to cleanup empty directories
          deletedDirs.add(dirPath);
        }
      } else {
        break;
      }
    }

    // Cleanup empty directories
    await _cleanupEmptyDirectories(deletedDirs);

    if (evicted > 0) {
      _recordEviction(0, evicted, 0, evictedBytes);
    }
  }

  Future<List<_DiskFileInfo>> _getAllDiskFiles() async {
    final files = <_DiskFileInfo>[];
    final baseDir = Directory(config.diskStoragePath!);

    if (!await baseDir.exists()) return files;

    await for (final entity in baseDir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        files.add(
          _DiskFileInfo(
            path: entity.path,
            lastModified: stat.modified,
            size: stat.size,
          ),
        );
      }
    }

    return files;
  }

  Future<void> _scanDiskUsage() async {
    _diskBytesUsed = 0;
    _diskItemCount = 0;

    final files = await _getAllDiskFiles();
    for (final file in files) {
      _diskBytesUsed += file.size;
      _diskItemCount++;
    }
  }

  Future<void> _cleanupEmptyDirectories(Set<String> directories) async {
    for (final dirPath in directories) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          // Try to delete the directory (will fail if not empty)
          await dir.delete();

          // If successful, also try to delete the parent directory
          final parentDir = Directory(path.dirname(dirPath));
          final baseDirPath = config.diskStoragePath!;

          // Only try to delete parent if it's not the base storage directory
          if (parentDir.path != baseDirPath && await parentDir.exists()) {
            try {
              await parentDir.delete();
            } catch (_) {
              // Silently ignore - parent directory might not be empty
            }
          }
        }
      } catch (_) {
        // Silently ignore - directory might not be empty or other issues
      }
    }
  }

  void _recordEviction(
    int memoryEvictions,
    int diskEvictions,
    int memoryEvictedBytes,
    int diskEvictedBytes,
  ) {
    final stats = EvictionStats(
      memoryEvictions: memoryEvictions,
      diskEvictions: diskEvictions,
      memoryEvictedBytes: memoryEvictedBytes,
      diskEvictedBytes: diskEvictedBytes,
      timestamp: DateTime.now(),
    );

    _evictionHistory.add(stats);

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _evictionHistory.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }

  ServiceStatus getStatus() {
    return ServiceStatus(
      memoryItemCount: _memoryStorage.length,
      diskItemCount: _diskItemCount,
      memoryBytesUsed: _memoryBytesUsed,
      diskBytesUsed: _diskBytesUsed,
      evictionHistory: List.from(_evictionHistory),
      timestamp: DateTime.now(),
    );
  }
}

class _DiskFileInfo {
  final String path;
  final DateTime lastModified;
  final int size;

  _DiskFileInfo({
    required this.path,
    required this.lastModified,
    required this.size,
  });
}
