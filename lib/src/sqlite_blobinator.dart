import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'api.dart';
import 'config.dart';

final _random = Random.secure();

/// Tracks statistics for blob storage operations.
class _StatsTracker {
  int _totalBlobCount = 0;
  int _totalKeysSize = 0;
  int _totalValuesSize = 0;

  /// Gets the current blob count.
  int get totalBlobCount => _totalBlobCount;

  /// Gets the total size of all keys in bytes.
  int get totalKeysSize => _totalKeysSize;

  /// Gets the total size of all values in bytes.
  int get totalValuesSize => _totalValuesSize;

  /// Initializes the statistics with the given values.
  void initialize({
    required int totalBlobCount,
    required int totalKeysSize,
    required int totalValuesSize,
  }) {
    _totalBlobCount = totalBlobCount;
    _totalKeysSize = totalKeysSize;
    _totalValuesSize = totalValuesSize;
  }

  /// Updates statistics when a new blob is added.
  void onAdd(int keySize, int valueSize) {
    _totalBlobCount++;
    _totalKeysSize += keySize;
    _totalValuesSize += valueSize;
  }

  /// Updates statistics when a blob is removed.
  void onRemove(int keySize, int valueSize) {
    _totalBlobCount--;
    _totalKeysSize -= keySize;
    _totalValuesSize -= valueSize;
  }

  /// Updates statistics when a blob's value is updated.
  void onUpdate(int keySize, int oldValueSize, int newValueSize) {
    _totalValuesSize += newValueSize - oldValueSize;
  }

  /// Updates statistics by subtracting bulk removal counts.
  /// Used for efficient bulk removal operations like removeExpired.
  void onBulkRemove({
    required int removedCount,
    required int removedKeysSize,
    required int removedValuesSize,
  }) {
    _totalBlobCount -= removedCount;
    _totalKeysSize -= removedKeysSize;
    _totalValuesSize -= removedValuesSize;
  }

  /// Creates a BlobStatistics object with current values.
  BlobStatistics getStatistics() {
    return BlobStatistics(
      totalBlobCount: _totalBlobCount,
      totalKeysSize: _totalKeysSize,
      totalValuesSize: _totalValuesSize,
    );
  }
}

/// Validates that a key meets the configured requirements.
void _validateKey(List<int> key, BlobinatorConfig config) {
  if (key.isEmpty) {
    throw ArgumentError('Key must have at least one byte');
  }
  final keyMaxLength = config.keyMaxLength;
  if (keyMaxLength != null && key.length > keyMaxLength) {
    throw ArgumentError('Key must be at most $keyMaxLength bytes');
  }
}

/// Validates that a value meets the configured size requirements.
void _validateValue(List<int> bytes, BlobinatorConfig config) {
  final valueMaxLength = config.valueMaxLength;
  if (valueMaxLength != null && bytes.length >= valueMaxLength) {
    throw ArgumentError('Value must be smaller than $valueMaxLength bytes');
  }
}

/// Generates a new random 8-byte version identifier.
Uint8List _generateVersion() {
  final version = Uint8List(8);
  for (int i = 0; i < 8; i++) {
    version[i] = _random.nextInt(256);
  }
  return version;
}

/// Checks if the expected version matches the actual version.
/// Returns true if expectedVersion is null (no version check required).
bool _versionsMatch(List<int>? expectedVersion, List<int> actualVersion) {
  if (expectedVersion == null) return true;
  if (expectedVersion.length != actualVersion.length) return false;
  for (int i = 0; i < expectedVersion.length; i++) {
    if (expectedVersion[i] != actualVersion[i]) return false;
  }
  return true;
}

/// Converts a key to a Uint8List for consistent handling.
Uint8List _keyToBytes(List<int> key) {
  return Uint8List.fromList(key);
}

/// Converts bytes to a Uint8List for consistent handling.
Uint8List _bytesToUint8List(List<int> bytes) {
  return Uint8List.fromList(bytes);
}

/// Calculates expiration time based on TTL and current configuration.
/// Returns null if no expiration should be set.
DateTime? _calculateExpiresAt(Duration? ttl, BlobinatorConfig config) {
  final effectiveTtl = ttl ?? config.defaultTtl;
  if (effectiveTtl == null) return null;
  return DateTime.now().add(effectiveTtl);
}

/// Checks if a blob has expired.
bool _isExpired(DateTime? expiresAt) {
  if (expiresAt == null) return false;
  return DateTime.now().isAfter(expiresAt);
}

/// SQLite-based implementation of the Blobinator API.
class SqliteBlobinator implements Blobinator {
  final Database _db;
  final String _tableName;
  final Map<String, PreparedStatement> _statementCache = {};
  final BlobinatorConfig _config;
  final _StatsTracker _statsTracker = _StatsTracker();

  // Maintenance timers
  Timer? _walCheckpointTimer;
  Timer? _incrementalVacuumTimer;
  Timer? _maintenanceTimer;
  bool _started = false;
  bool _closed = false;

  SqliteBlobinator(
    this._db, {
    BlobinatorConfig? config,
    String tableName = 'blobs',
  }) : _config = config ?? BlobinatorConfig(),
       _tableName = tableName {
    _initializeDatabase();
    _initializeStatistics();
  }

  /// Creates an in-memory SQLite database instance.
  factory SqliteBlobinator.inMemory({
    BlobinatorConfig? config,
    String tableName = 'blobs',
  }) {
    final db = sqlite3.openInMemory();
    return SqliteBlobinator(db, config: config, tableName: tableName);
  }

  /// Creates a file-based SQLite database instance.
  /// Creates the database file if it doesn't exist.
  factory SqliteBlobinator.inFile(
    String path, {
    BlobinatorConfig? config,
    String tableName = 'blobs',
  }) {
    final db = sqlite3.open(path);
    return SqliteBlobinator(db, config: config, tableName: tableName);
  }

  void _initializeDatabase() {
    // Apply performance optimizations first
    _optimizeDatabase();

    // Create table with optimizations
    _db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        key BLOB PRIMARY KEY,
        data BLOB NOT NULL,
        version BLOB NOT NULL,
        size INTEGER NOT NULL,
        key_length INTEGER NOT NULL,
        value_length INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER
      ) WITHOUT ROWID
    ''');

    // Create optimized partial index
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_${_tableName}_expires_at 
      ON $_tableName(expires_at) 
      WHERE expires_at IS NOT NULL
    ''');

    // Analyze tables for query optimization
    _db.execute('ANALYZE');
  }

  /// Applies performance optimizations to the database.
  void _optimizeDatabase() {
    // Enable WAL mode for better concurrency and performance
    _db.execute('PRAGMA journal_mode = WAL');

    // Faster synchronization (still safe for most use cases)
    _db.execute('PRAGMA synchronous = NORMAL');

    // Increase page cache size to 64MB
    _db.execute('PRAGMA cache_size = -65536'); // Negative = KB

    // Memory-mapped I/O for better performance (256MB)
    _db.execute('PRAGMA mmap_size = 268435456');

    // Optimize for writes (reduce checkpoint frequency)
    _db.execute('PRAGMA wal_autocheckpoint = 2000');

    // Set WAL size limit (64MB)
    _db.execute('PRAGMA journal_size_limit = 67108864');

    // Faster temporary storage
    _db.execute('PRAGMA temp_store = MEMORY');

    // Optimize locking for single-writer scenarios
    _db.execute('PRAGMA locking_mode = EXCLUSIVE');

    // Enable incremental vacuum
    _db.execute('PRAGMA auto_vacuum = INCREMENTAL');

    // Initial optimization
    _db.execute('PRAGMA optimize');
  }

  /// Gets or creates a cached prepared statement.
  PreparedStatement _getOrPrepareStatement(String key, String sql) {
    _checkNotClosed();
    return _statementCache[key] ??= _db.prepare(sql);
  }

  /// Checks if the database is closed and throws an exception if so.
  void _checkNotClosed() {
    if (_closed) {
      throw StateError('SqliteBlobinator has been closed and cannot be used');
    }
  }

  void _initializeStatistics() {
    // Remove expired items first
    removeExpired();

    // Query the table to initialize statistics
    final stmt = _db.prepare('''
      SELECT COUNT(*), SUM(key_length), SUM(value_length) 
      FROM $_tableName
    ''');

    try {
      final result = stmt.select([]);
      if (result.isNotEmpty) {
        final row = result.first;
        final totalBlobCount = row.values[0] as int? ?? 0;
        final totalKeysSize = row.values[1] as int? ?? 0;
        final totalValuesSize = row.values[2] as int? ?? 0;

        _statsTracker.initialize(
          totalBlobCount: totalBlobCount,
          totalKeysSize: totalKeysSize,
          totalValuesSize: totalValuesSize,
        );
      }
    } finally {
      stmt.dispose();
    }
  }

  @override
  Future<Blob?> getBlob(List<int> key) async {
    _validateKey(key, _config);
    final keyBytes = _keyToBytes(key);

    final stmt = _getOrPrepareStatement(
      'getBlob',
      'SELECT data, version, expires_at FROM $_tableName WHERE key = ?',
    );

    final result = stmt.select([keyBytes]);
    if (result.isEmpty) {
      return null;
    }

    final row = result.first;
    final data = row['data'] as Uint8List;
    final version = row['version'] as Uint8List;
    final expiresAtMs = row['expires_at'] as int?;

    final expiresAt = expiresAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
        : null;

    // Check if blob has expired
    if (_isExpired(expiresAt)) {
      // Remove expired blob and update stats
      final deleteStmt = _getOrPrepareStatement(
        'deleteExpired',
        'DELETE FROM $_tableName WHERE key = ?',
      );
      deleteStmt.execute([keyBytes]);
      _statsTracker.onRemove(key.length, data.length);
      return null;
    }

    return Blob(bytes: data, version: version);
  }

  @override
  Future<BlobMetadata?> getBlobMetadata(List<int> key) async {
    _validateKey(key, _config);
    final keyBytes = _keyToBytes(key);

    final stmt = _getOrPrepareStatement(
      'getBlobMetadata',
      'SELECT size, version, expires_at FROM $_tableName WHERE key = ?',
    );

    final result = stmt.select([keyBytes]);
    if (result.isEmpty) {
      return null;
    }

    final row = result.first;
    final size = row['size'] as int;
    final version = row['version'] as Uint8List;
    final expiresAtMs = row['expires_at'] as int?;

    final expiresAt = expiresAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
        : null;

    // Check if blob has expired
    if (_isExpired(expiresAt)) {
      // Remove expired blob and update stats
      final deleteStmt = _getOrPrepareStatement(
        'deleteExpired',
        'DELETE FROM $_tableName WHERE key = ?',
      );
      deleteStmt.execute([keyBytes]);
      _statsTracker.onRemove(key.length, size);
      return null;
    }

    return BlobMetadata(size: size, version: version);
  }

  @override
  Future<bool> updateBlob(
    List<int> key,
    List<int> bytes, {
    List<int>? version,
    Duration? ttl,
  }) async {
    _validateKey(key, _config);
    _validateValue(bytes, _config);

    final keyBytes = _keyToBytes(key);
    final dataBytes = _bytesToUint8List(bytes);
    final newVersion = _generateVersion();
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = _calculateExpiresAt(ttl, _config);
    final expiresAtMs = expiresAt?.millisecondsSinceEpoch;

    if (version == null) {
      // No version check - use INSERT OR REPLACE
      // First check if we're updating an existing blob for statistics
      final existingStmt = _getOrPrepareStatement(
        'checkExistingValue',
        'SELECT value_length FROM $_tableName WHERE key = ?',
      );

      final existingResult = existingStmt.select([keyBytes]);
      final existingValueLength = existingResult.isNotEmpty
          ? existingResult.first['value_length'] as int
          : null;

      final stmt = _getOrPrepareStatement('insertOrReplace', '''
        INSERT OR REPLACE INTO $_tableName 
        (key, data, version, size, key_length, value_length, created_at, expires_at) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''');

      stmt.execute([
        keyBytes,
        dataBytes,
        newVersion,
        bytes.length,
        key.length,
        bytes.length,
        now,
        expiresAtMs,
      ]);

      // Update statistics
      if (existingValueLength != null) {
        _statsTracker.onUpdate(key.length, existingValueLength, bytes.length);
      } else {
        _statsTracker.onAdd(key.length, bytes.length);
      }

      return true;
    } else {
      // Version check required - use transaction for atomicity
      _db.execute('BEGIN');
      try {
        // First check if blob exists and version matches
        final checkStmt = _getOrPrepareStatement(
          'checkVersionAndExpiry',
          'SELECT version, expires_at, value_length FROM $_tableName WHERE key = ?',
        );

        final result = checkStmt.select([keyBytes]);
        int? existingValueLength;

        if (result.isNotEmpty) {
          final row = result.first;
          final currentVersion = row['version'] as Uint8List;
          final currentExpiresAtMs = row['expires_at'] as int?;
          existingValueLength = row['value_length'] as int;

          final currentExpiresAt = currentExpiresAtMs != null
              ? DateTime.fromMillisecondsSinceEpoch(currentExpiresAtMs)
              : null;

          // Check if blob has expired (treat as removed)
          if (_isExpired(currentExpiresAt)) {
            // Remove expired blob and fail version check
            final deleteStmt = _getOrPrepareStatement(
              'deleteExpired',
              'DELETE FROM $_tableName WHERE key = ?',
            );
            deleteStmt.execute([keyBytes]);
            _statsTracker.onRemove(key.length, existingValueLength);
            _db.execute('ROLLBACK');
            return false;
          }

          if (!_versionsMatch(version, currentVersion)) {
            _db.execute('ROLLBACK');
            return false;
          }
        }

        // Update or insert the blob
        final updateStmt = _getOrPrepareStatement('insertOrReplace', '''
          INSERT OR REPLACE INTO $_tableName 
          (key, data, version, size, key_length, value_length, created_at, expires_at) 
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''');

        updateStmt.execute([
          keyBytes,
          dataBytes,
          newVersion,
          bytes.length,
          key.length,
          bytes.length,
          now,
          expiresAtMs,
        ]);

        // Update statistics
        if (existingValueLength != null) {
          _statsTracker.onUpdate(key.length, existingValueLength, bytes.length);
        } else {
          _statsTracker.onAdd(key.length, bytes.length);
        }

        _db.execute('COMMIT');
        return true;
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  @override
  Future<bool> deleteBlob(List<int> key, {List<int>? version}) async {
    _validateKey(key, _config);
    final keyBytes = _keyToBytes(key);

    if (version == null) {
      // No version check - but we still need to track statistics
      // First get the value size for statistics
      final sizeStmt = _getOrPrepareStatement(
        'getValueLength',
        'SELECT value_length FROM $_tableName WHERE key = ?',
      );

      final result = sizeStmt.select([keyBytes]);
      final valueLength = result.isNotEmpty
          ? result.first['value_length'] as int
          : null;

      final stmt = _getOrPrepareStatement(
        'deleteBlob',
        'DELETE FROM $_tableName WHERE key = ?',
      );
      stmt.execute([keyBytes]);
      if (valueLength != null) {
        _statsTracker.onRemove(key.length, valueLength);
      }
      return true;
    } else {
      // Version check required - need to check expiration first
      _db.execute('BEGIN');
      try {
        // Check if blob exists and get version/expiration
        final checkStmt = _getOrPrepareStatement(
          'checkVersionAndExpiry',
          'SELECT version, expires_at, value_length FROM $_tableName WHERE key = ?',
        );

        final result = checkStmt.select([keyBytes]);
        if (result.isEmpty) {
          _db.execute('ROLLBACK');
          return true; // Already doesn't exist
        }

        final row = result.first;
        final currentVersion = row['version'] as Uint8List;
        final currentExpiresAtMs = row['expires_at'] as int?;
        final valueLengthToRemove = row['value_length'] as int;

        final currentExpiresAt = currentExpiresAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(currentExpiresAtMs)
            : null;

        // Check if blob has expired (treat as already removed)
        if (_isExpired(currentExpiresAt)) {
          // Remove expired blob
          final deleteStmt = _getOrPrepareStatement(
            'deleteBlob',
            'DELETE FROM $_tableName WHERE key = ?',
          );
          deleteStmt.execute([keyBytes]);
          _statsTracker.onRemove(key.length, valueLengthToRemove);
          _db.execute('COMMIT');
          return true;
        }

        // Check version match
        if (!_versionsMatch(version, currentVersion)) {
          _db.execute('ROLLBACK');
          return false;
        }

        // Delete the blob
        final deleteStmt = _getOrPrepareStatement(
          'deleteBlob',
          'DELETE FROM $_tableName WHERE key = ?',
        );
        deleteStmt.execute([keyBytes]);
        _statsTracker.onRemove(key.length, valueLengthToRemove);

        _db.execute('COMMIT');
        return true;
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  Future<void> removeExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // First, collect statistics of items to be removed
    final selectStmt = _getOrPrepareStatement(
      'selectExpiredStats',
      'SELECT key_length, value_length FROM $_tableName WHERE expires_at IS NOT NULL AND expires_at <= ?',
    );

    int removedCount = 0;
    int removedKeysSize = 0;
    int removedValuesSize = 0;

    final result = selectStmt.select([now]);
    for (final row in result) {
      removedCount++;
      removedKeysSize += row['key_length'] as int;
      removedValuesSize += row['value_length'] as int;
    }

    // Delete the expired items
    final deleteStmt = _getOrPrepareStatement(
      'deleteExpired',
      'DELETE FROM $_tableName WHERE expires_at IS NOT NULL AND expires_at <= ?',
    );
    deleteStmt.execute([now]);

    // Update statistics using bulk removal
    _statsTracker.onBulkRemove(
      removedCount: removedCount,
      removedKeysSize: removedKeysSize,
      removedValuesSize: removedValuesSize,
    );
  }

  @override
  Future<BlobStatistics> getStatistics() async {
    return _statsTracker.getStatistics();
  }

  /// Stores a blob with preserved metadata, bypassing normal validations.
  /// Used internally for migrations between storage backends.
  Future<bool> storeBlobWithMetadata(
    List<int> key,
    List<int> bytes,
    List<int> version,
    DateTime createdAt,
    DateTime? expiresAt,
  ) async {
    final keyBytes = _keyToBytes(key);
    final dataBytes = _bytesToUint8List(bytes);
    final versionBytes = _bytesToUint8List(version);
    final createdAtMs = createdAt.millisecondsSinceEpoch;
    final expiresAtMs = expiresAt?.millisecondsSinceEpoch;

    final stmt = _getOrPrepareStatement('storeBlobWithMetadata', '''
      INSERT OR REPLACE INTO $_tableName 
      (key, data, version, size, key_length, value_length, created_at, expires_at) 
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');

    stmt.execute([
      keyBytes,
      dataBytes,
      versionBytes,
      bytes.length,
      key.length,
      bytes.length,
      createdAtMs,
      expiresAtMs,
    ]);

    return true;
  }

  /// Gets the creation time of a blob.
  Future<DateTime?> getBlobCreatedAt(List<int> key) async {
    final keyBytes = _keyToBytes(key);

    final stmt = _getOrPrepareStatement(
      'getBlobCreatedAt',
      'SELECT created_at FROM $_tableName WHERE key = ?',
    );

    final result = stmt.select([keyBytes]);
    if (result.isEmpty) {
      return null;
    }

    final createdAtMs = result.first['created_at'] as int;
    return DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  }

  /// Gets blobs that are older than the specified threshold for migration.
  /// This is more efficient than querying all blobs and then filtering them,
  /// as it only returns blobs that actually need to be migrated.
  Future<Map<Uint8List, DateTime>> getBlobsOlderThan(DateTime threshold) async {
    final thresholdMs = threshold.millisecondsSinceEpoch;

    final stmt = _getOrPrepareStatement(
      'getBlobsOlderThan',
      'SELECT key, created_at FROM $_tableName WHERE created_at < ?',
    );

    final result = stmt.select([thresholdMs]);
    final blobs = <Uint8List, DateTime>{};

    for (final row in result) {
      final key = row['key'] as Uint8List;
      final createdAtMs = row['created_at'] as int;
      blobs[key] = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    }

    return blobs;
  }

  /// Starts background maintenance tasks.
  /// Should be called after construction to enable automatic maintenance.
  void start() {
    if (_started) return;
    _started = true;

    // WAL checkpoint every 5 minutes
    _walCheckpointTimer = Timer.periodic(Duration(minutes: 5), (_) {
      _performWalCheckpoint();
    });

    // Incremental vacuum every hour
    _incrementalVacuumTimer = Timer.periodic(Duration(hours: 1), (_) {
      _performIncrementalVacuum();
    });

    // Full maintenance daily at 2 AM
    _maintenanceTimer = Timer.periodic(Duration(hours: 24), (_) {
      final now = DateTime.now();
      if (now.hour == 2) {
        _performMaintenanceVacuum();
      }
    });
  }

  /// Performs WAL checkpoint to ensure data is written to main database file.
  void _performWalCheckpoint() {
    try {
      _db.execute('PRAGMA wal_checkpoint(RESTART)');
    } catch (e) {
      // Log error but don't crash
      print('WAL checkpoint failed: $e');
    }
  }

  /// Performs incremental vacuum if there's significant fragmentation.
  void _performIncrementalVacuum() {
    try {
      final freelistResult = _db.select('PRAGMA freelist_count');
      if (freelistResult.isNotEmpty) {
        final freePages = freelistResult.first.values[0] as int;

        if (freePages > 100) {
          // Only vacuum if >100 free pages
          _db.execute('PRAGMA incremental_vacuum(50)'); // Vacuum 50 pages
          print('Incremental vacuum: freed $freePages pages');
        }
      }
    } catch (e) {
      print('Incremental vacuum failed: $e');
    }
  }

  /// Performs full maintenance vacuum and optimization.
  /// This is an expensive operation that should run during low-usage periods.
  void _performMaintenanceVacuum() {
    try {
      print('Starting maintenance vacuum...');

      // Get database size before
      final beforeResult = _db.select('PRAGMA page_count');
      final pagesBefore = beforeResult.isNotEmpty
          ? beforeResult.first.values[0] as int
          : 0;

      // Full vacuum (rebuilds entire database)
      _db.execute('VACUUM');

      // Get database size after
      final afterResult = _db.select('PRAGMA page_count');
      final pagesAfter = afterResult.isNotEmpty
          ? afterResult.first.values[0] as int
          : 0;

      print('Vacuum complete: $pagesBefore -> $pagesAfter pages');

      // Re-analyze after vacuum for query optimization
      _db.execute('ANALYZE');
      _db.execute('PRAGMA optimize');
    } catch (e) {
      print('Maintenance vacuum failed: $e');
    }
  }

  /// Returns performance statistics for monitoring.
  Map<String, dynamic> getPerformanceStats() {
    final stats = <String, dynamic>{};

    try {
      // WAL mode info
      final walInfo = _db.select('PRAGMA wal_checkpoint');
      if (walInfo.isNotEmpty) {
        stats['wal_pages'] = walInfo.first.values[1];
      }

      // Cache size
      final cacheInfo = _db.select('PRAGMA cache_size');
      if (cacheInfo.isNotEmpty) {
        stats['cache_size_kb'] = (cacheInfo.first.values[0] as int).abs();
      }

      // Page count and size
      final pageCount = _db.select('PRAGMA page_count');
      final pageSize = _db.select('PRAGMA page_size');
      if (pageCount.isNotEmpty && pageSize.isNotEmpty) {
        final pages = pageCount.first.values[0] as int;
        final size = pageSize.first.values[0] as int;
        stats['database_size_mb'] = (pages * size) / (1024 * 1024);
      }

      // Free pages (fragmentation)
      final freePages = _db.select('PRAGMA freelist_count');
      if (freePages.isNotEmpty && pageCount.isNotEmpty) {
        final free = freePages.first.values[0] as int;
        final total = pageCount.first.values[0] as int;
        stats['fragmentation_percent'] = total > 0
            ? (free / total * 100).toStringAsFixed(2)
            : '0.00';
      }
    } catch (e) {
      stats['error'] = 'Failed to collect stats: $e';
    }

    return stats;
  }

  /// Prints performance statistics to console.
  void printPerformanceStats() {
    final stats = getPerformanceStats();
    print('=== SQLite Performance Stats ===');
    stats.forEach((key, value) {
      print('$key: $value');
    });
  }

  /// Closes the database connection and stops all timers.
  @override
  Future<void> close() async {
    if (_closed) {
      return; // Already closed, avoid double-close
    }
    _closed = true;
    _started = false;

    // Cancel all timers
    _walCheckpointTimer?.cancel();
    _walCheckpointTimer = null;

    _incrementalVacuumTimer?.cancel();
    _incrementalVacuumTimer = null;

    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;

    // Final WAL checkpoint before closing
    try {
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e) {
      // Ignore errors if database is already closed
      // print('Final WAL checkpoint failed: $e');
    }

    // Clean up prepared statements
    for (final stmt in _statementCache.values) {
      try {
        stmt.dispose();
      } catch (e) {
        print('Failed to dispose prepared statement: $e');
      }
    }
    _statementCache.clear();

    // Close database
    try {
      _db.dispose();
    } catch (e) {
      // Ignore errors if database is already closed
    }
  }
}
