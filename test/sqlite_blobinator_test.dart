import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/src/config.dart';
import 'package:blobinator/src/sqlite_blobinator.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteBlobinator - In-Memory', () {
    late SqliteBlobinator blobinator;

    setUp(() {
      blobinator = SqliteBlobinator.inMemory();
    });

    tearDown(() async {
      await blobinator.close();
    });

    _runBasicTests(() => blobinator);
  });

  group('SqliteBlobinator - File-Based', () {
    late SqliteBlobinator blobinator;
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlite_test_');
      dbPath = '${tempDir.path}/test.db';
      blobinator = SqliteBlobinator.inFile(dbPath);
    });

    tearDown(() async {
      await blobinator.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    _runBasicTests(() => blobinator);

    test('should persist data across database reopens', () async {
      final key = [1, 2, 3];
      final data = [4, 5, 6, 7];

      // Store data
      final success = await blobinator.updateBlob(key, data);
      expect(success, isTrue);

      // Close and reopen database
      await blobinator.close();
      blobinator = SqliteBlobinator.inFile(dbPath);

      // Data should still be there
      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(data)));
    });
  });

  group('SqliteBlobinator - Configuration', () {
    late SqliteBlobinator blobinator;

    tearDown(() async {
      await blobinator.close();
    });

    test('should use custom configuration for limits', () async {
      final config = BlobinatorConfig(keyMaxLength: 10, valueMaxLength: 20);
      blobinator = SqliteBlobinator.inMemory(config: config);

      // Test key length limit
      final longKey = List.filled(11, 65);
      expect(
        () async => await blobinator.getBlob(longKey),
        throwsA(isA<ArgumentError>()),
      );

      // Test value length limit
      final validKey = [1, 2, 3];
      final longValue = List.filled(21, 66);
      expect(
        () async => await blobinator.updateBlob(validKey, longValue),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should use custom table name', () async {
      blobinator = SqliteBlobinator.inMemory(tableName: 'custom_blobs');

      final key = [1, 2, 3];
      final data = [4, 5, 6];

      // Should work with custom table name
      final success = await blobinator.updateBlob(key, data);
      expect(success, isTrue);

      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(data)));
    });
  });
}

void _runBasicTests(SqliteBlobinator Function() getBlobinator) {
  group('Basic operations', () {
    test('should return null for non-existent blob', () async {
      final blobinator = getBlobinator();
      final result = await blobinator.getBlob([1, 2, 3]);
      expect(result, isNull);
    });

    test('should return null metadata for non-existent blob', () async {
      final blobinator = getBlobinator();
      final result = await blobinator.getBlobMetadata([1, 2, 3]);
      expect(result, isNull);
    });

    test('should create and retrieve blob', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      final updated = await blobinator.updateBlob(key, bytes);
      expect(updated, isTrue);

      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
      expect(blob.version.length, equals(8));
    });

    test('should retrieve blob metadata', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata, isNotNull);
      expect(metadata!.size, equals(bytes.length));
      expect(metadata.version.length, equals(8));
    });

    test('should delete blob', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final deleted = await blobinator.deleteBlob(key);
      expect(deleted, isTrue);

      final result = await blobinator.getBlob(key);
      expect(result, isNull);
    });

    test('should cast input bytes to Uint8List', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });
  });

  group('Version-based operations', () {
    test('should update blob without version check', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      final updated = await blobinator.updateBlob(key, bytes);
      expect(updated, isTrue);
    });

    test('should update blob with correct version', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      final newBytes = [8, 9, 10];
      final updated = await blobinator.updateBlob(
        key,
        newBytes,
        version: blob!.version,
      );
      expect(updated, isTrue);

      final updatedBlob = await blobinator.getBlob(key);
      expect(updatedBlob!.bytes, equals(Uint8List.fromList(newBytes)));
      expect(updatedBlob.version, isNot(equals(blob.version)));
    });

    test('should fail to update blob with incorrect version', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);

      final wrongVersion = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final newBytes = [8, 9, 10];
      final updated = await blobinator.updateBlob(
        key,
        newBytes,
        version: wrongVersion,
      );
      expect(updated, isFalse);

      // Original data should be unchanged
      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should delete blob without version check', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final deleted = await blobinator.deleteBlob(key);
      expect(deleted, isTrue);
    });

    test('should delete blob with correct version', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      final deleted = await blobinator.deleteBlob(key, version: blob!.version);
      expect(deleted, isTrue);

      final result = await blobinator.getBlob(key);
      expect(result, isNull);
    });

    test('should fail to delete blob with incorrect version', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);

      final wrongVersion = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final deleted = await blobinator.deleteBlob(key, version: wrongVersion);
      expect(deleted, isFalse);

      // Blob should still exist
      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
    });

    test('should return true when deleting non-existent blob', () async {
      final blobinator = getBlobinator();
      final key = [99, 99, 99];
      final result = await blobinator.deleteBlob(key);
      expect(result, isTrue);
    });
  });

  group('Version generation', () {
    test('should generate different versions for different updates', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob1 = await blobinator.getBlob(key);

      await blobinator.updateBlob(key, bytes);
      final blob2 = await blobinator.getBlob(key);

      expect(blob1!.version, isNot(equals(blob2!.version)));
    });

    test('should generate new version on update', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final originalBlob = await blobinator.getBlob(key);

      final newBytes = [8, 9, 10];
      await blobinator.updateBlob(
        key,
        newBytes,
        version: originalBlob!.version,
      );
      final updatedBlob = await blobinator.getBlob(key);

      expect(updatedBlob!.version, isNot(equals(originalBlob.version)));
    });

    test('should generate 8-byte versions', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      expect(blob!.version.length, equals(8));
    });
  });

  group('Key and value validation', () {
    test('should throw ArgumentError for empty key', () async {
      final blobinator = getBlobinator();
      final emptyKey = <int>[];
      expect(
        () async => await blobinator.getBlob(emptyKey),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'should throw ArgumentError for key larger than configured limit',
      () async {
        final config = BlobinatorConfig(keyMaxLength: 5);
        final customBlobinator = SqliteBlobinator.inMemory(config: config);

        try {
          final largeKey = List.filled(6, 65);
          expect(
            () async => await customBlobinator.getBlob(largeKey),
            throwsA(isA<ArgumentError>()),
          );
        } finally {
          await customBlobinator.close();
        }
      },
    );

    test('should accept valid key sizes', () async {
      final blobinator = getBlobinator();
      final validKey = List.filled(100, 65);
      final bytes = [1, 2, 3];

      final success = await blobinator.updateBlob(validKey, bytes);
      expect(success, isTrue);
    });

    test(
      'should throw ArgumentError for value larger than configured limit',
      () async {
        final config = BlobinatorConfig(valueMaxLength: 10);
        final customBlobinator = SqliteBlobinator.inMemory(config: config);

        try {
          final key = [1, 2, 3];
          final largeValue = List.filled(11, 42);
          expect(
            () async => await customBlobinator.updateBlob(key, largeValue),
            throwsA(isA<ArgumentError>()),
          );
        } finally {
          await customBlobinator.close();
        }
      },
    );

    test('should accept valid value sizes', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final validValue = List.filled(1000, 42);

      final success = await blobinator.updateBlob(key, validValue);
      expect(success, isTrue);
    });
  });

  group('Edge cases', () {
    test('should handle empty bytes', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final emptyBytes = <int>[];

      final success = await blobinator.updateBlob(key, emptyBytes);
      expect(success, isTrue);

      final blob = await blobinator.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, isEmpty);

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata, isNotNull);
      expect(metadata!.size, equals(0));
    });

    test('should handle binary key data', () async {
      final blobinator = getBlobinator();
      final binaryKey = [0, 255, 128, 1, 2, 3];
      final bytes = [4, 5, 6, 7];

      final success = await blobinator.updateBlob(binaryKey, bytes);
      expect(success, isTrue);

      final blob = await blobinator.getBlob(binaryKey);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should maintain separate storage for different keys', () async {
      final blobinator = getBlobinator();
      final key1 = [1, 2, 3];
      final key2 = [4, 5, 6];
      final bytes1 = [10, 20, 30];
      final bytes2 = [40, 50, 60];

      await blobinator.updateBlob(key1, bytes1);
      await blobinator.updateBlob(key2, bytes2);

      final blob1 = await blobinator.getBlob(key1);
      final blob2 = await blobinator.getBlob(key2);

      expect(blob1!.bytes, equals(Uint8List.fromList(bytes1)));
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
      expect(blob1.version, isNot(equals(blob2.version)));
    });

    test('should handle updates to same key', () async {
      final blobinator = getBlobinator();
      final key = [1, 2, 3];
      final bytes1 = [10, 20, 30];
      final bytes2 = [40, 50, 60];

      await blobinator.updateBlob(key, bytes1);
      await blobinator.updateBlob(key, bytes2);

      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes2)));
    });
  });
}
