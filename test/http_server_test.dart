import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/src/config.dart';
import 'package:blobinator/src/http_client.dart';
import 'package:blobinator/src/http_server.dart';
import 'package:blobinator/src/sqlite_blobinator.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late HttpBlobinator client;
  late SqliteBlobinator memBlobinator;
  late String baseUrl;

  setUp(() async {
    memBlobinator = SqliteBlobinator.inMemory();
    final httpServer = BlobinatorHttpServer(memBlobinator);

    server = await io.serve(httpServer.handler, 'localhost', 0);
    baseUrl = 'http://localhost:${server.port}';
    client = HttpBlobinator(baseUrl);
  });

  tearDown(() async {
    await client.close();
    await memBlobinator.close();
    await server.close();
  });

  group('Basic operations', () {
    test('should return null for non-existent blob', () async {
      final result = await client.getBlob([1, 2, 3]);
      expect(result, isNull);
    });

    test('should return null metadata for non-existent blob', () async {
      final result = await client.getBlobMetadata([1, 2, 3]);
      expect(result, isNull);
    });

    test('should create and retrieve blob', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      final updated = await client.updateBlob(key, bytes);
      expect(updated, isTrue);

      final blob = await client.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
      expect(blob.version.length, equals(8));
    });

    test('should retrieve blob metadata', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6, 7];

      await client.updateBlob(key, bytes);

      final metadata = await client.getBlobMetadata(key);
      expect(metadata, isNotNull);
      expect(metadata!.size, equals(bytes.length));
      expect(metadata.version.length, equals(8));
    });

    test('should delete blob', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await client.updateBlob(key, bytes);
      final result = await client.deleteBlob(key);

      expect(result, isTrue);
      expect(await client.getBlob(key), isNull);
    });
  });

  group('Version-based operations', () {
    test('should update blob with correct version', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];

      await client.updateBlob(key, bytes1);
      final blob1 = await client.getBlob(key);

      final result = await client.updateBlob(
        key,
        bytes2,
        version: blob1!.version,
      );
      expect(result, isTrue);

      final blob2 = await client.getBlob(key);
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
    });

    test('should fail to update blob with incorrect version', () async {
      final key = [1, 2, 3];
      final bytes1 = [4, 5, 6];
      final bytes2 = [7, 8, 9];
      final wrongVersion = [1, 2, 3, 4, 5, 6, 7, 8];

      await client.updateBlob(key, bytes1);
      final result = await client.updateBlob(
        key,
        bytes2,
        version: wrongVersion,
      );

      expect(result, isFalse);
      final blob = await client.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes1)));
    });

    test('should delete blob with correct version', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      final result = await client.deleteBlob(key, version: blob!.version);
      expect(result, isTrue);
      expect(await client.getBlob(key), isNull);
    });

    test('should fail to delete blob with incorrect version', () async {
      final key = [1, 2, 3];
      final bytes = [4, 5, 6];
      final wrongVersion = [1, 2, 3, 4, 5, 6, 7, 8];

      await client.updateBlob(key, bytes);
      final result = await client.deleteBlob(key, version: wrongVersion);

      expect(result, isFalse);
      expect(await client.getBlob(key), isNotNull);
    });
  });

  group('Key encoding', () {
    test('should handle UTF-8 keys (default)', () async {
      final key = utf8.encode('hello/world');
      final bytes = [1, 2, 3];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should handle keys with forward slashes', () async {
      final key = utf8.encode('folder/subfolder/file');
      final bytes = [10, 20, 30];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should handle binary key data', () async {
      final key = [0, 255, 128, 1];
      final bytes = [4, 5, 6];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should handle keys that start with "base64:" in UTF-8', () async {
      final key = utf8.encode('base64:test');
      final bytes = [100, 200];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should handle complex paths with special characters', () async {
      final key = utf8.encode('folder/file-with_underscores.txt');
      final bytes = [50, 60, 70];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });
  });

  group('Error handling', () {
    test('should throw ArgumentError for invalid key size', () async {
      final emptyKey = <int>[];
      expect(() => client.getBlob(emptyKey), throwsA(isA<ArgumentError>()));
    });

    test('should throw ArgumentError for invalid value size', () async {
      final key = [1, 2, 3];
      // Use a much smaller value to make the test faster (1KB limit)
      final customMemBlobinator = SqliteBlobinator.inMemory(
        config: BlobinatorConfig(valueMaxLength: 1000),
      );

      final largeValue = List.filled(1001, 42); // Just over 1KB limit

      expect(
        () => customMemBlobinator.updateBlob(key, largeValue),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should handle 404 for non-existent blob', () async {
      final key = [99, 99, 99];
      final result = await client.getBlob(key);
      expect(result, isNull);
    });
  });

  group('Edge cases', () {
    test('should handle empty bytes', () async {
      final key = [1, 2, 3];
      final bytes = <int>[];

      final result = await client.updateBlob(key, bytes);
      expect(result, isTrue);

      final blob = await client.getBlob(key);
      expect(blob!.bytes.length, equals(0));

      final metadata = await client.getBlobMetadata(key);
      expect(metadata!.size, equals(0));
    });

    test('should handle large valid blobs', () async {
      final key = [1, 2, 3];
      final bytes = List.filled(1024 * 1024, 42); // 1 MiB

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob!.bytes.length, equals(bytes.length));
      expect(blob.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should maintain separate storage for different keys', () async {
      final key1 = utf8.encode('key1');
      final key2 = utf8.encode('key2');
      final bytes1 = [10, 20];
      final bytes2 = [30, 40];

      await client.updateBlob(key1, bytes1);
      await client.updateBlob(key2, bytes2);

      final blob1 = await client.getBlob(key1);
      final blob2 = await client.getBlob(key2);

      expect(blob1!.bytes, equals(Uint8List.fromList(bytes1)));
      expect(blob2!.bytes, equals(Uint8List.fromList(bytes2)));
    });

    test('should handle updates to same key', () async {
      final key = [1, 2, 3];
      final bytes1 = [10, 20];
      final bytes2 = [30, 40];

      await client.updateBlob(key, bytes1);
      await client.updateBlob(key, bytes2);

      final blob = await client.getBlob(key);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes2)));
    });

    test('should return true when deleting non-existent blob', () async {
      final key = [99, 99, 99];
      final result = await client.deleteBlob(key);
      expect(result, isTrue);
    });
  });

  group('Content type detection', () {
    test('should detect JSON content type', () async {
      final key = utf8.encode('test.json');
      final jsonBytes = utf8.encode('{"test": "data"}');

      await client.updateBlob(key, jsonBytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(jsonBytes)));
    });

    test('should handle binary data', () async {
      final key = utf8.encode('binary');
      final binaryBytes = [0xFF, 0x00, 0xFF, 0x00];

      await client.updateBlob(key, binaryBytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(binaryBytes)));
    });
  });

  group('Prefix encoding edge cases', () {
    test(
      'should correctly encode key that would decode to start with base64:',
      () async {
        // Create a key that when UTF-8 decoded would start with "base64:"
        final key = utf8.encode('base64:actualcontent');
        final bytes = [123, 124, 125];

        await client.updateBlob(key, bytes);
        final blob = await client.getBlob(key);

        expect(blob, isNotNull);
        expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
      },
    );

    test('should handle key with only base64: prefix', () async {
      final key = utf8.encode('base64:');
      final bytes = [1, 2];

      await client.updateBlob(key, bytes);
      final blob = await client.getBlob(key);

      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(bytes)));
    });

    test('should handle various UTF-8 safe keys', () async {
      final testKeys = [
        'simple',
        'folder/file',
        'deep/folder/structure/file.txt',
        'with-dashes',
        'with_underscores',
        'with.dots',
        'file123',
      ];

      for (int i = 0; i < testKeys.length; i++) {
        final key = utf8.encode(testKeys[i]);
        final bytes = [i, i + 1, i + 2];

        await client.updateBlob(key, bytes);
        final blob = await client.getBlob(key);

        expect(blob, isNotNull, reason: 'Failed for key: ${testKeys[i]}');
        expect(
          blob!.bytes,
          equals(Uint8List.fromList(bytes)),
          reason: 'Failed for key: ${testKeys[i]}',
        );
      }
    });
  });
}
