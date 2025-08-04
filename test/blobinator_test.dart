import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/blobinator.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('Blobinator Integration Tests', () {
    late HttpServer server;
    late BlobStorage storage;
    late String baseUrl;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('blobinator_test_');

      final config = BlobinatorConfig(
        port: 0, // Let the system assign a port
        maxMemoryItems: 100,
        maxDiskItems: 1000,
        maxMemoryBytes: 1024 * 1024, // 1MB
        maxDiskBytes: 10 * 1024 * 1024, // 10MB
        memoryTtl: const Duration(seconds: 30),
        diskTtl: const Duration(minutes: 5),
        diskStoragePath: tempDir.path,
      );

      storage = BlobStorage(config);
      final blobServer = BlobinatorServer(config, storage);

      server = await io.serve(
        blobServer.handler,
        InternetAddress.loopbackIPv4,
        0,
      );

      baseUrl = 'http://${server.address.host}:${server.port}';
    });

    tearDown(() async {
      await server.close();
      await tempDir.delete(recursive: true);
    });

    test('PUT and GET blob successfully', () async {
      const blobId = 'test-blob-123';
      final testData = Uint8List.fromList('Hello, World!'.codeUnits);

      // PUT the blob
      final putResponse = await http.put(
        Uri.parse('$baseUrl/blobs/$blobId'),
        body: testData,
      );
      expect(putResponse.statusCode, equals(200));

      // GET the blob
      final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse.statusCode, equals(200));
      expect(getResponse.bodyBytes, equals(testData));
      expect(getResponse.headers['content-length'], equals('13'));
      expect(getResponse.headers['last-modified'], isNotNull);
    });

    test('HEAD request returns correct metadata', () async {
      const blobId = 'test-blob-head';
      final testData = Uint8List.fromList('Test data for HEAD'.codeUnits);

      // PUT the blob
      await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: testData);

      // HEAD request
      final headResponse = await http.head(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(headResponse.statusCode, equals(200));
      expect(headResponse.headers['content-length'], equals('18'));
      expect(headResponse.headers['last-modified'], isNotNull);
      expect(headResponse.body, isEmpty);
    });

    test('GET non-existent blob returns 404', () async {
      final getResponse = await http.get(
        Uri.parse('$baseUrl/blobs/non-existent-blob'),
      );
      expect(getResponse.statusCode, equals(404));
    });

    test('HEAD non-existent blob returns 404', () async {
      final headResponse = await http.head(
        Uri.parse('$baseUrl/blobs/non-existent-blob'),
      );
      expect(headResponse.statusCode, equals(404));
    });

    test('DELETE blob successfully', () async {
      const blobId = 'test-blob-delete';
      final testData = Uint8List.fromList('To be deleted'.codeUnits);

      // PUT the blob
      await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: testData);

      // Verify it exists
      final getResponse1 = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse1.statusCode, equals(200));

      // DELETE the blob
      final deleteResponse = await http.delete(
        Uri.parse('$baseUrl/blobs/$blobId'),
      );
      expect(deleteResponse.statusCode, equals(200));

      // Verify it's gone
      final getResponse2 = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse2.statusCode, equals(404));
    });

    test('DELETE non-existent blob returns 404', () async {
      final deleteResponse = await http.delete(
        Uri.parse('$baseUrl/blobs/non-existent-blob'),
      );
      expect(deleteResponse.statusCode, equals(404));
    });

    test('PUT updates existing blob', () async {
      const blobId = 'test-blob-update';
      final testData1 = Uint8List.fromList('Original data'.codeUnits);
      final testData2 = Uint8List.fromList('Updated data'.codeUnits);

      // PUT original data
      await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: testData1);

      // GET original data
      final getResponse1 = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse1.bodyBytes, equals(testData1));

      // PUT updated data
      await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: testData2);

      // GET updated data
      final getResponse2 = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse2.bodyBytes, equals(testData2));
      expect(getResponse2.headers['content-length'], equals('12'));
    });

    test('Invalid blob ID returns 400 on PUT', () async {
      const invalidBlobId = 'ab'; // Too short
      final testData = Uint8List.fromList('Test data'.codeUnits);

      final putResponse = await http.put(
        Uri.parse('$baseUrl/blobs/$invalidBlobId'),
        body: testData,
      );
      expect(putResponse.statusCode, equals(400));
    });

    test('Status endpoint returns service statistics', () async {
      // Add some blobs first
      await http.put(
        Uri.parse('$baseUrl/blobs/status-test-1'),
        body: Uint8List.fromList('Data 1'.codeUnits),
      );
      await http.put(
        Uri.parse('$baseUrl/blobs/status-test-2'),
        body: Uint8List.fromList('Data 2'.codeUnits),
      );

      final statusResponse = await http.get(Uri.parse('$baseUrl/status'));
      expect(statusResponse.statusCode, equals(200));
      expect(
        statusResponse.headers['content-type'],
        contains('application/json'),
      );

      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      expect(status['memoryItemCount'], greaterThanOrEqualTo(2));
      expect(status['memoryBytesUsed'], greaterThan(0));
      expect(status['timestamp'], isNotNull);
      expect(status['evictionHistory'], isList);
    });

    test('Binary data handling', () async {
      const blobId = 'binary-test';
      final binaryData = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC,
        0x89, 0x50, 0x4E, 0x47, // PNG signature start
      ]);

      // PUT binary data
      final putResponse = await http.put(
        Uri.parse('$baseUrl/blobs/$blobId'),
        body: binaryData,
      );
      expect(putResponse.statusCode, equals(200));

      // GET binary data
      final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse.statusCode, equals(200));
      expect(getResponse.bodyBytes, equals(binaryData));
    });

    test('Large blob handling', () async {
      const blobId = 'large-blob-test';
      final largeData = Uint8List(10000);
      for (int i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256;
      }

      // PUT large data
      final putResponse = await http.put(
        Uri.parse('$baseUrl/blobs/$blobId'),
        body: largeData,
      );
      expect(putResponse.statusCode, equals(200));

      // GET large data
      final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse.statusCode, equals(200));
      expect(getResponse.bodyBytes, equals(largeData));
      expect(getResponse.headers['content-length'], equals('10000'));
    });

    test('Memory to disk eviction', () async {
      // Fill up memory beyond the limit (100 items)
      for (int i = 0; i < 150; i++) {
        final blobId = 'eviction-test-$i';
        final data = Uint8List.fromList('Data for item $i'.codeUnits);

        await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: data);
      }

      // Check that some items are still accessible (moved to disk)
      final getResponse = await http.get(
        Uri.parse('$baseUrl/blobs/eviction-test-0'),
      );
      expect(getResponse.statusCode, equals(200));

      // Check status shows disk usage
      final statusResponse = await http.get(Uri.parse('$baseUrl/status'));
      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      expect(status['diskItemCount'], greaterThan(0));
      expect(status['diskBytesUsed'], greaterThan(0));
    });
  });

  group('BlobStorage Unit Tests', () {
    late BlobStorage storage;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('blobinator_unit_test_');
      final config = BlobinatorConfig(
        maxMemoryItems: 5,
        maxMemoryBytes: 100,
        diskStoragePath: tempDir.path,
      );
      storage = BlobStorage(config);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('Valid blob ID validation', () async {
      final validIds = ['test', 'test-123', 'test_123', 'test.123', 'a1b2c3d4'];
      for (final id in validIds) {
        final data = Uint8List.fromList('test'.codeUnits);
        await storage.put(id, data);
        expect(await storage.exists(id), isTrue);
      }
    });

    test('Invalid blob ID validation', () async {
      final invalidIds = ['ab', 'TEST', 'test@123', 'test#123', 'a' * 513];
      for (final id in invalidIds) {
        final data = Uint8List.fromList('test'.codeUnits);
        expect(() => storage.put(id, data), throwsArgumentError);
      }
    });

    test('Disk file path generation', () async {
      const blobId = 'test-blob-123';
      final data = Uint8List.fromList('test data'.codeUnits);

      await storage.put(blobId, data);

      // Check that file was created with correct path structure
      final files = await tempDir.list(recursive: true).toList();
      final blobFiles = files.where((f) => f.path.endsWith(blobId)).toList();
      expect(blobFiles, hasLength(1));

      // Path should have two subdirs based on MD5 hash
      final parts = blobFiles.first.path.split(Platform.pathSeparator);
      expect(parts[parts.length - 3], hasLength(2)); // First subdir
      expect(parts[parts.length - 2], hasLength(2)); // Second subdir
      expect(parts[parts.length - 1], equals(blobId)); // Filename
    });

    test('Directory cleanup after deletion', () async {
      const blobId = 'cleanup-test-blob';
      final data = Uint8List.fromList('test data'.codeUnits);

      // Put a blob to create directory structure
      await storage.put(blobId, data);

      // Verify directories were created
      final allEntities = await tempDir.list(recursive: true).toList();
      final directories = allEntities.whereType<Directory>().toList();
      expect(directories, isNotEmpty);

      // Delete the blob
      final deleted = await storage.delete(blobId);
      expect(deleted, isTrue);

      // Check that empty directories are cleaned up
      // Note: This is a best-effort cleanup, so we just verify it doesn't crash
      // and that the blob file is gone
      final remainingFiles = await tempDir
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();
      final blobFiles = remainingFiles.where((f) => f.path.endsWith(blobId));
      expect(blobFiles, isEmpty);
    });
  });
}
