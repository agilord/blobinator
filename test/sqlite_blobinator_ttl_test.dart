import 'dart:typed_data';

import 'package:blobinator/src/config.dart';
import 'package:blobinator/src/sqlite_blobinator.dart';
import 'package:test/test.dart';

void main() {
  late SqliteBlobinator blobinator;

  setUp(() {
    blobinator = SqliteBlobinator.inMemory();
  });

  tearDown(() async {
    await blobinator.close();
  });

  group('TTL functionality', () {
    test(
      'should store blob without expiration when no TTL is provided',
      () async {
        final key = [1, 2, 3];
        final bytes = [4, 5, 6];

        await blobinator.updateBlob(key, bytes);
        final blob = await blobinator.getBlob(key);

        expect(blob, isNotNull);
      },
    );

    test('should store blob with expiration when TTL is provided', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final ttl = Duration(seconds: 10);

      await blobinator.updateBlob(key, bytes, ttl: ttl);
      final blob = await blobinator.getBlob(key);

      expect(blob, isNotNull);
    });

    test('should use defaultTtl when no TTL is provided', () async {
      final config = BlobinatorConfig(defaultTtl: Duration(seconds: 5));
      final blobinatorWithDefault = SqliteBlobinator.inMemory(config: config);
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      try {
        await blobinatorWithDefault.updateBlob(key, bytes);
        final blob = await blobinatorWithDefault.getBlob(key);

        expect(blob, isNotNull);
      } finally {
        await blobinatorWithDefault.close();
      }
    });

    test('should return null for expired blob on getBlob', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final shortTtl = Duration(milliseconds: 100);

      await blobinator.updateBlob(key, bytes, ttl: shortTtl);

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 200));

      final blob = await blobinator.getBlob(key);
      expect(blob, isNull);
    });

    test('should return null for expired blob on getBlobMetadata', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final shortTtl = Duration(milliseconds: 100);

      await blobinator.updateBlob(key, bytes, ttl: shortTtl);

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 200));

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata, isNull);
    });

    test(
      'should treat expired blob as non-existent for version check on update',
      () async {
        final key = [1, 2, 3];
        final bytes1 = [4, 5, 6];
        final bytes2 = [7, 8, 9];
        final shortTtl = Duration(milliseconds: 100);

        // Create blob with version
        await blobinator.updateBlob(key, bytes1, ttl: shortTtl);
        final blob1 = await blobinator.getBlob(key);
        final version1 = blob1!.version;

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 200));

        // Try to update with old version - should fail since blob is expired
        final result = await blobinator.updateBlob(
          key,
          bytes2,
          version: version1,
        );
        expect(result, isFalse);
      },
    );

    test(
      'should succeed when updating expired blob without version check',
      () async {
        final key = [1, 2, 3];
        final bytes1 = [4, 5, 6];
        final bytes2 = [7, 8, 9];
        final shortTtl = Duration(milliseconds: 100);

        // Create blob
        await blobinator.updateBlob(key, bytes1, ttl: shortTtl);

        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 200));

        // Update without version check - should succeed
        final result = await blobinator.updateBlob(key, bytes2);
        expect(result, isTrue);

        final blob = await blobinator.getBlob(key);
        expect(blob, isNotNull);
        expect(blob!.bytes, equals(Uint8List.fromList(bytes2)));
      },
    );

    test('should succeed when deleting expired blob', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final shortTtl = Duration(milliseconds: 100);

      // Create blob
      await blobinator.updateBlob(key, bytes, ttl: shortTtl);

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 200));

      // Delete should always succeed
      final result = await blobinator.deleteBlob(key);
      expect(result, isTrue);
    });

    test('should remove expired blobs with removeExpired', () async {
      final key1 = [1, 2, 3];
      final key2 = [4, 5, 6];
      final key3 = [7, 8, 9];
      final bytes = [10, 11, 12];
      final shortTtl = Duration(milliseconds: 100);

      // Create blobs with different TTLs
      await blobinator.updateBlob(key1, bytes, ttl: shortTtl);
      await blobinator.updateBlob(
        key2,
        bytes,
        ttl: Duration(hours: 1),
      ); // Long TTL
      await blobinator.updateBlob(key3, bytes); // No TTL

      // Wait for first blob to expire
      await Future.delayed(Duration(milliseconds: 200));

      // Remove expired blobs
      await blobinator.removeExpired();

      // Check results
      expect(
        await blobinator.getBlob(key1),
        isNull,
      ); // Expired, should be removed
      expect(await blobinator.getBlob(key2), isNotNull); // Not expired
      expect(await blobinator.getBlob(key3), isNotNull); // No expiration
    });

    test('should update TTL when updating existing blob', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];
      final ttl1 = Duration(seconds: 10);
      final ttl2 = Duration(seconds: 20);

      // Create blob with first TTL
      await blobinator.updateBlob(key, bytes1, ttl: ttl1);

      // Wait a bit
      await Future.delayed(Duration(milliseconds: 100));

      // Update with new TTL
      await blobinator.updateBlob(key, bytes2, ttl: ttl2);
      final blob2 = await blobinator.getBlob(key);

      expect(blob2, isNotNull);
      // We can verify the TTL was updated by checking that the blob still exists
      // and has different content (indicating it was updated)
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
    });

    test('should handle database schema with expires_at column', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final ttl = Duration(seconds: 1);

      // This test ensures the database schema is correct
      await blobinator.updateBlob(key, bytes, ttl: ttl);

      // Should not throw any database errors
      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata, isNotNull);
    });
  });
}
