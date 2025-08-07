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

  group('Key validation', () {
    test('should throw ArgumentError for empty key', () {
      expect(() => blobinator.getBlob([]), throwsA(isA<ArgumentError>()));
    });

    test('should throw ArgumentError for key larger than configured limit', () {
      final config = BlobinatorConfig(keyMaxLength: 16 * 1024);
      final limitedBlobinator = SqliteBlobinator.inMemory(config: config);
      addTearDown(() async => await limitedBlobinator.close());
      final largeKey = List.filled(16 * 1024 + 1, 42);
      expect(
        () => limitedBlobinator.getBlob(largeKey),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should accept valid key sizes', () async {
      final minKey = [1];
      final largeKey = List.filled(
        100 * 1024,
        42,
      ); // 100KB - no limit by default

      expect(await blobinator.getBlob(minKey), isNull);
      expect(await blobinator.getBlob(largeKey), isNull);
    });
  });

  group('Value validation', () {
    test('should throw ArgumentError for value exceeding configured limit', () {
      final config = BlobinatorConfig(valueMaxLength: 1024);
      final limitedBlobinator = SqliteBlobinator.inMemory(config: config);
      addTearDown(() async => await limitedBlobinator.close());
      final key = [1, 2, 3];
      final largeValue = List.filled(1025, 42);

      expect(
        () => limitedBlobinator.updateBlob(key, largeValue),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should accept valid value sizes', () async {
      final key = [1, 2, 3];
      final largeValue = List.filled(
        10 * 1024 * 1024,
        42,
      ); // 10MB - no limit by default

      expect(await blobinator.updateBlob(key, largeValue), isTrue);
    });
  });

  group('Basic operations', () {
    test('should return null for non-existent blob', () async {
      final result = await blobinator.getBlob([1, 2, 3]);
      expect(result, isNull);
    });

    test('should return null metadata for non-existent blob', () async {
      final result = await blobinator.getBlobMetadata([1, 2, 3]);
      expect(result, isNull);
    });

    test('should create and retrieve blob', () async {
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
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata, isNotNull);
      expect(metadata!.size, equals(bytes.length));
      expect(metadata.version.length, equals(8));
    });

    test('should cast input bytes to Uint8List', () async {
      final key = <int>[1, 2, 3];
      final bytes = <int>[4, 5, 6, 7];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      expect(blob!.bytes, isA<Uint8List>());
      expect(blob.version, isA<Uint8List>());
    });
  });

  group('Version-based operations', () {
    test('should update blob without version check', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];

      await blobinator.updateBlob(key, bytes1);
      final result = await blobinator.updateBlob(key, bytes2);

      expect(result, isTrue);
      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes2)));
    });

    test('should update blob with correct version', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];

      await blobinator.updateBlob(key, bytes1);
      final blob1 = await blobinator.getBlob(key);

      final result = await blobinator.updateBlob(
        key,
        bytes2,
        version: blob1!.version,
      );
      expect(result, isTrue);

      final blob2 = await blobinator.getBlob(key);
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
      expect(blob2.version, isNot(equals(blob1.version)));
    });

    test('should fail to update blob with incorrect version', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];
      final wrongVersion = [1, 2, 3, 4, 5, 6, 7, 8];

      await blobinator.updateBlob(key, bytes1);
      final result = await blobinator.updateBlob(
        key,
        bytes2,
        version: wrongVersion,
      );

      expect(result, isFalse);
      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes1)));
    });

    test('should delete blob without version check', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await blobinator.updateBlob(key, bytes);
      final result = await blobinator.deleteBlob(key);

      expect(result, isTrue);
      expect(await blobinator.getBlob(key), isNull);
    });

    test('should delete blob with correct version', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      final result = await blobinator.deleteBlob(key, version: blob!.version);
      expect(result, isTrue);
      expect(await blobinator.getBlob(key), isNull);
    });

    test('should fail to delete blob with incorrect version', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final wrongVersion = [1, 2, 3, 4, 5, 6, 7, 8];

      await blobinator.updateBlob(key, bytes);
      final result = await blobinator.deleteBlob(key, version: wrongVersion);

      expect(result, isFalse);
      expect(await blobinator.getBlob(key), isNotNull);
    });

    test('should return true when deleting non-existent blob', () async {
      final key = [1, 2, 3];
      final result = await blobinator.deleteBlob(key);
      expect(result, isTrue);
    });
  });

  group('Version generation', () {
    test('should generate different versions for different updates', () async {
      final key1 = [1, 2, 3];
      final key2 = [4, 5, 6];
      final bytes = [7, 8, 9];

      await blobinator.updateBlob(key1, bytes);
      await blobinator.updateBlob(key2, bytes);

      final blob1 = await blobinator.getBlob(key1);
      final blob2 = await blobinator.getBlob(key2);

      expect(blob1!.version, isNot(equals(blob2!.version)));
    });

    test('should generate new version on update', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];

      await blobinator.updateBlob(key, bytes1);
      final blob1 = await blobinator.getBlob(key);

      await blobinator.updateBlob(key, bytes2);
      final blob2 = await blobinator.getBlob(key);

      expect(blob1!.version, isNot(equals(blob2!.version)));
    });

    test('should generate 8-byte versions', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      expect(blob!.version.length, equals(8));
    });
  });

  group('Edge cases', () {
    test('should handle empty bytes', () async {
      final key = [1, 2, 3];
      final bytes = <int>[];

      final result = await blobinator.updateBlob(key, bytes);
      expect(result, isTrue);

      final blob = await blobinator.getBlob(key);
      expect(blob!.bytes.length, equals(0));

      final metadata = await blobinator.getBlobMetadata(key);
      expect(metadata!.size, equals(0));
    });

    test('should handle binary key data', () async {
      final key = [0, 255, 128, 1];
      final bytes = [4, 5, 6];

      await blobinator.updateBlob(key, bytes);
      final blob = await blobinator.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should maintain separate storage for different keys', () async {
      final key1 = [1];
      final key2 = [2];
      final bytes1 = [10];
      final bytes2 = [20];

      await blobinator.updateBlob(key1, bytes1);
      await blobinator.updateBlob(key2, bytes2);

      final blob1 = await blobinator.getBlob(key1);
      final blob2 = await blobinator.getBlob(key2);

      expect(blob1!.bytes, equals(Uint8List.fromList(bytes1)));
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
    });
  });
}
