import 'dart:typed_data';

import 'package:blobinator/src/config.dart';
import 'package:blobinator/src/sqlite_blobinator.dart';

/// A blob storage system interface for storing and retrieving binary data with versioning and TTL support.
///
/// The Blobinator provides a key-value store for binary data where:
/// - Keys are arbitrary byte sequences
/// - Values are binary data of any size (subject to configured limits)
/// - Each blob has an associated version for optimistic concurrency control
/// - Blobs can have an optional time-to-live (TTL) for automatic expiration
abstract class Blobinator {
  /// Returns a blobinator with a local in-memory Sqlite database.
  static Future<Blobinator> inMemory({BlobinatorConfig? config}) async {
    return SqliteBlobinator.inMemory(config: config);
  }

  /// Returns a blobinator with a local Sqlite database.
  static Future<Blobinator> inFile(
    String path, {
    BlobinatorConfig? config,
  }) async {
    return SqliteBlobinator.inFile(path, config: config);
  }

  /// Retrieves the blob stored under [key].
  ///
  /// Returns null if no blob exists for the given key, or if the blob has expired.
  /// Expired blobs are automatically removed when accessed.
  Future<Blob?> getBlob(List<int> key);

  /// Retrieves metadata for the blob stored under [key].
  ///
  /// Returns null if no blob exists for the given key, or if the blob has expired.
  /// Expired blobs are automatically removed when accessed.
  ///
  /// This is more efficient than [getBlob] when you only need size and version
  /// information without the actual blob content.
  Future<BlobMetadata?> getBlobMetadata(List<int> key);

  /// Creates or updates the blob under [key] with [bytes].
  ///
  /// Parameters:
  /// - [key]: The key to store the blob under. Must not be empty.
  /// - [bytes]: The binary data to store.
  /// - [version]: Optional. If provided, the operation will only succeed if the
  ///   current blob's version matches this value. Used for optimistic concurrency control.
  /// - [ttl]: Optional time-to-live duration. If provided, the blob will automatically
  ///   expire after this duration. If not provided, uses the configured defaultTtl.
  ///   If explicitly null, the blob will not expire.
  ///
  /// Returns:
  /// - true if the blob was successfully created/updated
  /// - false if version check failed (blob exists but version doesn't match)
  ///
  /// Throws [ArgumentError] if key is empty or exceeds configured limits,
  /// or if bytes exceed configured size limits.
  Future<bool> updateBlob(
    List<int> key,
    List<int> bytes, {
    List<int>? version,
    Duration? ttl,
  });

  /// Deletes the blob stored under [key].
  ///
  /// Parameters:
  /// - [key]: The key of the blob to delete.
  /// - [version]: Optional. If provided, the operation will only succeed if the
  ///   current blob's version matches this value. Used for optimistic concurrency control.
  ///
  /// Returns:
  /// - true if the blob was deleted or didn't exist
  /// - false if version check failed (blob exists but version doesn't match)
  ///
  /// Throws [ArgumentError] if key is empty or exceeds configured limits.
  Future<bool> deleteBlob(List<int> key, {List<int>? version});

  /// Returns current statistics about stored blobs.
  ///
  /// This includes total blob count, total size of keys, and total size of values.
  /// The statistics reflect the current state and may change as blobs are added,
  /// updated, or removed (including automatic expiration).
  Future<BlobStatistics> getStatistics();

  /// Closes the blobinator and releases all associated resources.
  ///
  /// After calling this method, the blobinator should not be used anymore.
  /// Any subsequent operations may throw exceptions or behave unexpectedly.
  ///
  /// This method should be called when the blobinator is no longer needed
  /// to ensure proper cleanup of resources such as database connections,
  /// timers, and other system resources.
  ///
  /// Returns a Future that completes when all cleanup operations are finished.
  Future<void> close();
}

/// Represents a blob with its binary content and version information.
///
/// A blob contains the actual binary data along with a version identifier
/// that changes each time the blob is updated, enabling optimistic concurrency control.
class Blob {
  /// The binary content of the blob.
  ///
  /// This is always returned as a [Uint8List] regardless of the input type
  /// used when storing the blob.
  final Uint8List bytes;

  /// An opaque version identifier that changes with each update.
  ///
  /// This 8-byte identifier is used for optimistic concurrency control.
  /// When updating or deleting a blob, you can provide this version to ensure
  /// the operation only succeeds if the blob hasn't been modified by another process.
  ///
  /// The version is automatically generated and should be treated as opaque -
  /// do not attempt to interpret its contents.
  final Uint8List version;

  /// Creates a new Blob instance.
  ///
  /// Both [bytes] and [version] are required parameters.
  Blob({required this.bytes, required this.version});
}

/// Metadata information about a blob without its actual content.
///
/// This is useful when you need to know the size and version of a blob
/// without transferring the potentially large binary content.
class BlobMetadata {
  /// The size of the blob in bytes.
  ///
  /// This represents the exact number of bytes in the blob's content.
  final int size;

  /// An opaque version identifier that changes with each update.
  ///
  /// This 8-byte identifier is used for optimistic concurrency control.
  /// When updating or deleting a blob, you can provide this version to ensure
  /// the operation only succeeds if the blob hasn't been modified by another process.
  ///
  /// The version is automatically generated and should be treated as opaque -
  /// do not attempt to interpret its contents.
  final Uint8List version;

  /// Creates a new BlobMetadata instance.
  ///
  /// Both [size] and [version] are required parameters.
  BlobMetadata({required this.size, required this.version});
}

/// Statistics about the blobs currently stored in the system.
///
/// This class provides information about the total number of blobs
/// and the combined size of all keys and values.
class BlobStatistics {
  /// The total number of blobs currently stored.
  final int totalBlobCount;

  /// The total size in bytes of all blob keys.
  final int totalKeysSize;

  /// The total size in bytes of all blob values.
  final int totalValuesSize;

  /// Creates a new BlobStatistics instance.
  BlobStatistics({
    required this.totalBlobCount,
    required this.totalKeysSize,
    required this.totalValuesSize,
  });

  /// Converts the statistics to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'totalBlobCount': totalBlobCount,
    'totalKeysSize': totalKeysSize,
    'totalValuesSize': totalValuesSize,
  };
}
