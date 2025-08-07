import 'dart:io';
import 'dart:typed_data';

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
  late Directory tempDir;

  setUp(() async {
    memBlobinator = SqliteBlobinator.inMemory();
    final httpServer = BlobinatorHttpServer(memBlobinator);

    server = await io.serve(httpServer.handler, 'localhost', 0);
    baseUrl = 'http://localhost:${server.port}';
    client = HttpBlobinator(baseUrl);

    // Create temporary directory for file tests
    tempDir = await Directory.systemTemp.createTemp('streaming_test_');
  });

  tearDown(() async {
    await client.close();
    await memBlobinator.close();
    await server.close();

    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Streaming PUT operations', () {
    test('should upload blob from stream', () async {
      final key = 'stream-test'.codeUnits;
      final testData = 'Hello, streaming world!'.codeUnits;

      // Create a stream from the test data
      final dataStream = Stream.fromIterable([testData]);

      final success = await client.updateBlobStream(key, dataStream);
      expect(success, isTrue);

      // Verify the blob was uploaded correctly
      final blob = await client.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes, equals(Uint8List.fromList(testData)));
    });

    test('should upload large blob from stream in chunks', () async {
      final key = 'large-stream-test'.codeUnits;

      // Create test data in chunks
      final chunk1 = List.filled(1024, 65); // 1KB of 'A'
      final chunk2 = List.filled(1024, 66); // 1KB of 'B'
      final chunk3 = List.filled(1024, 67); // 1KB of 'C'

      final dataStream = Stream.fromIterable([chunk1, chunk2, chunk3]);

      final success = await client.updateBlobStream(key, dataStream);
      expect(success, isTrue);

      // Verify the blob was uploaded correctly
      final blob = await client.getBlob(key);
      expect(blob, isNotNull);
      expect(blob!.bytes.length, equals(3072)); // 3KB total

      // Verify the content
      expect(blob.bytes.sublist(0, 1024), equals(Uint8List.fromList(chunk1)));
      expect(
        blob.bytes.sublist(1024, 2048),
        equals(Uint8List.fromList(chunk2)),
      );
      expect(
        blob.bytes.sublist(2048, 3072),
        equals(Uint8List.fromList(chunk3)),
      );
    });

    test('should handle version conflict in streaming upload', () async {
      final key = 'version-conflict-stream'.codeUnits;
      final testData = 'Initial data'.codeUnits;

      // Upload initial blob
      await client.updateBlob(key, testData);
      final blob = await client.getBlob(key);
      expect(blob, isNotNull);

      // Try to update with wrong version
      final wrongVersion = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final newDataStream = Stream.fromIterable(['New data'.codeUnits]);

      final success = await client.updateBlobStream(
        key,
        newDataStream,
        version: wrongVersion,
      );
      expect(success, isFalse);
    });
  });

  group('Streaming GET operations', () {
    test('should download blob as stream', () async {
      final key = 'download-stream-test'.codeUnits;
      final testData = 'Hello, download streaming!'.codeUnits;

      // Upload test data first
      await client.updateBlob(key, testData);

      // Download as stream
      final stream = await client.getBlobStream(key);
      expect(stream, isNotNull);

      // Collect all chunks from the stream
      final chunks = <List<int>>[];
      await for (final chunk in stream!) {
        chunks.add(chunk);
      }

      // Combine all chunks and verify
      final downloadedData = chunks.expand((chunk) => chunk).toList();
      expect(downloadedData, equals(testData));
    });

    test('should return null for non-existent blob stream', () async {
      final key = 'non-existent-stream'.codeUnits;

      final stream = await client.getBlobStream(key);
      expect(stream, isNull);
    });

    test('should stream large blob in chunks', () async {
      final key = 'large-download-test'.codeUnits;
      final testData = List.filled(10240, 88); // 10KB of 'X'

      // Upload large test data
      await client.updateBlob(key, testData);

      // Download as stream
      final stream = await client.getBlobStream(key);
      expect(stream, isNotNull);

      // Collect all data
      final downloadedData = <int>[];
      await for (final chunk in stream!) {
        downloadedData.addAll(chunk);
      }

      expect(downloadedData.length, equals(10240));
      expect(downloadedData, equals(testData));
    });
  });

  group('File operations', () {
    test('should upload blob from file', () async {
      final key = 'file-upload-test'.codeUnits;
      final testData = 'Hello from file!';

      // Create test file
      final testFile = File('${tempDir.path}/test_upload.txt');
      await testFile.writeAsString(testData);

      final success = await client.updateBlobFromFile(key, testFile.path);
      expect(success, isTrue);

      // Verify upload
      final blob = await client.getBlob(key);
      expect(blob, isNotNull);
      expect(String.fromCharCodes(blob!.bytes), equals(testData));
    });

    test('should throw error for non-existent file', () async {
      final key = 'missing-file-test'.codeUnits;
      final nonExistentPath = '${tempDir.path}/does_not_exist.txt';

      expect(
        () => client.updateBlobFromFile(key, nonExistentPath),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should download blob to file', () async {
      final key = 'file-download-test'.codeUnits;
      final testData = 'Hello to file!';

      // Upload test data first
      await client.updateBlob(key, testData.codeUnits);

      // Download to file
      final downloadFile = File('${tempDir.path}/downloaded.txt');
      final success = await client.saveBlobToFile(key, downloadFile.path);
      expect(success, isTrue);

      // Verify file content
      final fileContent = await downloadFile.readAsString();
      expect(fileContent, equals(testData));
    });

    test(
      'should return false when downloading non-existent blob to file',
      () async {
        final key = 'non-existent-file-test'.codeUnits;
        final downloadFile = File('${tempDir.path}/not_found.txt');

        final success = await client.saveBlobToFile(key, downloadFile.path);
        expect(success, isFalse);
        expect(await downloadFile.exists(), isFalse);
      },
    );

    test(
      'should create parent directories automatically when downloading to file',
      () async {
        final key = 'dir-creation-test'.codeUnits;
        final testData = 'Directory creation test';

        // Upload test data first
        await client.updateBlob(key, testData.codeUnits);

        // Download to nested path that doesn't exist
        final nestedPath = '${tempDir.path}/nested/deep/path/file.txt';
        final success = await client.saveBlobToFile(key, nestedPath);
        expect(success, isTrue);

        // Verify file was created and content is correct
        final downloadFile = File(nestedPath);
        expect(await downloadFile.exists(), isTrue);
        final fileContent = await downloadFile.readAsString();
        expect(fileContent, equals(testData));
      },
    );

    test('should handle large file upload and download', () async {
      final key = 'large-file-test'.codeUnits;

      // Create large test file (5KB)
      final largeData = List.generate(5120, (i) => i % 256);
      final uploadFile = File('${tempDir.path}/large_upload.bin');
      await uploadFile.writeAsBytes(largeData);

      // Upload from file
      final uploadSuccess = await client.updateBlobFromFile(
        key,
        uploadFile.path,
      );
      expect(uploadSuccess, isTrue);

      // Download to file
      final downloadFile = File('${tempDir.path}/large_download.bin');
      final downloadSuccess = await client.saveBlobToFile(
        key,
        downloadFile.path,
      );
      expect(downloadSuccess, isTrue);

      // Verify files are identical
      final originalData = await uploadFile.readAsBytes();
      final downloadedData = await downloadFile.readAsBytes();
      expect(downloadedData, equals(originalData));
    });
  });

  group('Integration with existing methods', () {
    test(
      'should work with version control across streaming and regular methods',
      () async {
        final key = 'version-integration-test'.codeUnits;
        final initialData = 'Initial content';

        // Upload using regular method
        await client.updateBlob(key, initialData.codeUnits);
        final blob = await client.getBlob(key);
        expect(blob, isNotNull);

        // Update using streaming with correct version
        final newData = 'Updated via stream';
        final dataStream = Stream.fromIterable([newData.codeUnits]);
        final success = await client.updateBlobStream(
          key,
          dataStream,
          version: blob!.version,
        );
        expect(success, isTrue);

        // Verify update using regular method
        final updatedBlob = await client.getBlob(key);
        expect(updatedBlob, isNotNull);
        expect(String.fromCharCodes(updatedBlob!.bytes), equals(newData));
      },
    );
  });
}
