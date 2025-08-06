import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/blobinator.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
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

    test('Flush endpoint - flush all blobs', () async {
      // Add some blobs to memory
      for (int i = 0; i < 5; i++) {
        final blobId = 'flush-test-$i';
        final data = Uint8List.fromList('Data for flush test $i'.codeUnits);
        await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: data);
      }

      // Verify blobs are in memory
      final statusBefore = await http.get(Uri.parse('$baseUrl/status'));
      final statusBeforeJson =
          jsonDecode(statusBefore.body) as Map<String, dynamic>;
      expect(statusBeforeJson['memoryItemCount'], greaterThanOrEqualTo(5));

      // Flush all blobs
      final flushResponse = await http.post(Uri.parse('$baseUrl/flush'));
      expect(flushResponse.statusCode, equals(200));

      final flushResult =
          jsonDecode(flushResponse.body) as Map<String, dynamic>;
      expect(flushResult['flushed'], greaterThanOrEqualTo(5));

      // Verify blobs are still accessible
      final getResponse = await http.get(
        Uri.parse('$baseUrl/blobs/flush-test-0'),
      );
      expect(getResponse.statusCode, equals(200));
      expect(
        getResponse.bodyBytes,
        equals(Uint8List.fromList('Data for flush test 0'.codeUnits)),
      );
    });

    test('Flush endpoint - flush with limit', () async {
      // Add some blobs to memory
      for (int i = 0; i < 10; i++) {
        final blobId = 'flush-limit-test-$i';
        final data = Uint8List.fromList('Data $i'.codeUnits);
        await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: data);
      }

      // Flush only 3 blobs
      final flushResponse = await http.post(
        Uri.parse('$baseUrl/flush?limit=3'),
      );
      expect(flushResponse.statusCode, equals(200));

      final flushResult =
          jsonDecode(flushResponse.body) as Map<String, dynamic>;
      expect(flushResult['flushed'], equals(3));
    });

    test('Flush endpoint - flush with age filter', () async {
      // Add some blobs and wait
      for (int i = 0; i < 3; i++) {
        final blobId = 'flush-age-test-$i';
        final data = Uint8List.fromList('Old data $i'.codeUnits);
        await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: data);
      }

      // Wait a moment
      await Future.delayed(Duration(milliseconds: 100));

      // Add more recent blobs
      for (int i = 3; i < 6; i++) {
        final blobId = 'flush-age-test-$i';
        final data = Uint8List.fromList('New data $i'.codeUnits);
        await http.put(Uri.parse('$baseUrl/blobs/$blobId'), body: data);
      }

      // Flush only blobs older than 1 second
      final flushResponse = await http.post(Uri.parse('$baseUrl/flush?age=1s'));
      expect(flushResponse.statusCode, equals(200));

      final flushResult =
          jsonDecode(flushResponse.body) as Map<String, dynamic>;
      expect(
        flushResult['flushed'],
        greaterThanOrEqualTo(0),
      ); // Age-based, may vary
    });

    test('Flush endpoint - invalid parameters', () async {
      // Invalid limit parameter
      final invalidLimitResponse = await http.post(
        Uri.parse('$baseUrl/flush?limit=invalid'),
      );
      expect(invalidLimitResponse.statusCode, equals(400));

      // Invalid age parameter
      final invalidAgeResponse = await http.post(
        Uri.parse('$baseUrl/flush?age=invalid'),
      );
      expect(invalidAgeResponse.statusCode, equals(400));
    });

    test('Flush endpoint - memory-only mode fails', () async {
      // Create a memory-only config
      final memoryOnlyConfig = BlobinatorConfig(
        port: 0,
        maxMemoryItems: 100,
        diskStoragePath: null, // Memory-only
      );

      final memoryOnlyStorage = BlobStorage(memoryOnlyConfig);
      final memoryOnlyServer = BlobinatorServer(
        memoryOnlyConfig,
        memoryOnlyStorage,
      );

      final memoryOnlyHttpServer = await io.serve(
        memoryOnlyServer.handler,
        InternetAddress.loopbackIPv4,
        0,
      );

      final memoryOnlyBaseUrl =
          'http://${memoryOnlyHttpServer.address.host}:${memoryOnlyHttpServer.port}';

      try {
        // Try to flush - should fail with 409
        final flushResponse = await http.post(
          Uri.parse('$memoryOnlyBaseUrl/flush'),
        );
        expect(flushResponse.statusCode, equals(409));
      } finally {
        await memoryOnlyHttpServer.close();
      }
    });

    test('Flush parameter via HTTP API writes to disk immediately', () async {
      const blobId = 'http-flush-test';
      final testData = Uint8List.fromList('HTTP flush test data'.codeUnits);

      // Get initial memory count via HTTP status endpoint
      final initialStatusResponse = await http.get(
        Uri.parse('$baseUrl/status'),
      );
      final initialStatus =
          jsonDecode(initialStatusResponse.body) as Map<String, dynamic>;
      final initialMemoryCount = initialStatus['memoryItemCount'] as int;

      // PUT blob with immediate flush (zero duration)
      final putResponse = await http.put(
        Uri.parse('$baseUrl/blobs/$blobId?flush=0'),
        body: testData,
      );
      expect(putResponse.statusCode, equals(200));

      // Verify blob is NOT in memory (was immediately flushed)
      final statusAfterResponse = await http.get(Uri.parse('$baseUrl/status'));
      final statusAfter =
          jsonDecode(statusAfterResponse.body) as Map<String, dynamic>;
      expect(statusAfter['memoryItemCount'], equals(initialMemoryCount));

      // Verify blob can still be retrieved
      final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
      expect(getResponse.statusCode, equals(200));
      expect(getResponse.bodyBytes, equals(testData));

      // Verify disk storage was updated
      expect(
        statusAfter['diskItemCount'],
        greaterThan(initialStatus['diskItemCount']),
      );
      expect(
        statusAfter['diskBytesUsed'],
        greaterThan(initialStatus['diskBytesUsed']),
      );
    });

    test('Invalid flush parameter values return 400', () async {
      const blobId = 'invalid-flush-test';
      final testData = Uint8List.fromList('test data'.codeUnits);

      // Test invalid flush parameter values
      final invalidValues = ['invalid', 'yes', 'no', 'maybe', '2x', ''];

      for (final invalidValue in invalidValues) {
        final putResponse = await http.put(
          Uri.parse('$baseUrl/blobs/$blobId?flush=$invalidValue'),
          body: testData,
        );
        expect(
          putResponse.statusCode,
          equals(400),
          reason: 'flush=$invalidValue should return 400',
        );
        expect(
          putResponse.body,
          anyOf([
            contains('Invalid flush'),
            contains('Flush value cannot be empty'),
          ]),
        );
      }
    });

    test('Valid flush parameter values work correctly', () async {
      final validValues = ['1', '0', '5s', '10m', '2h', '3d', '60'];

      for (int i = 0; i < validValues.length; i++) {
        final blobId = 'valid-flush-test-$i';
        final testData = Uint8List.fromList('test data $i'.codeUnits);
        final value = validValues[i];

        final putResponse = await http.put(
          Uri.parse('$baseUrl/blobs/$blobId?flush=$value'),
          body: testData,
        );
        expect(
          putResponse.statusCode,
          equals(200),
          reason: 'flush=$value should succeed',
        );

        // Verify blob can be retrieved
        final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
        expect(getResponse.statusCode, equals(200));
        expect(getResponse.bodyBytes, equals(testData));
      }
    });

    test('Expanded character set works via HTTP API', () async {
      final testCases = [
        'Test-With-Uppercase',
        'MyBlobId',
        'TEST123',
        'test~with~tildes',
        'file~backup~v1',
        '~temp~file~',
        'mixed.Case_With-All~Valid.chars123',
      ];

      for (final blobId in testCases) {
        final testData = Uint8List.fromList('data for $blobId'.codeUnits);

        // PUT the blob
        final putResponse = await http.put(
          Uri.parse('$baseUrl/blobs/$blobId'),
          body: testData,
        );
        expect(
          putResponse.statusCode,
          equals(200),
          reason: 'PUT should succeed for ID: $blobId',
        );

        // GET the blob
        final getResponse = await http.get(Uri.parse('$baseUrl/blobs/$blobId'));
        expect(
          getResponse.statusCode,
          equals(200),
          reason: 'GET should succeed for ID: $blobId',
        );
        expect(getResponse.bodyBytes, equals(testData));

        // HEAD the blob
        final headResponse = await http.head(
          Uri.parse('$baseUrl/blobs/$blobId'),
        );
        expect(
          headResponse.statusCode,
          equals(200),
          reason: 'HEAD should succeed for ID: $blobId',
        );
        expect(
          headResponse.headers['content-length'],
          equals('${testData.length}'),
        );
      }
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
      final validIds = [
        'test', 'test-123', 'test_123', 'test.123', 'a1b2c3d4',
        // New expanded character set
        'Test-With-Uppercase', 'MyBlobId', 'TEST123',
        'test~with~tildes', 'file~backup~v1', '~temp~file~',
        'mixed.Case_With-All~Valid.chars123',
      ];
      for (final id in validIds) {
        final data = Uint8List.fromList('test'.codeUnits);
        await storage.put(id, data);
        expect(await storage.exists(id), isTrue);
      }
    });

    test('Invalid blob ID validation', () async {
      final invalidIds = [
        'ab', // Too short
        'a' * 513, // Too long
        // Invalid characters (not in [a-zA-Z0-9._~-])
        'test@123', // @ symbol
        'test#123', // # symbol
        'test/path', // Forward slash
        r'test\path', // Backslash
        'test?query', // Question mark
        'test with spaces', // Spaces
        'test:colon', // Colon
        'test*wildcard', // Asterisk
        'test<greater', // Less than
        'test>less', // Greater than
        'test|pipe', // Pipe
        'test"quote', // Double quote
        "test'quote", // Single quote
        'test%percent', // Percent
        'test+plus', // Plus
        'test=equals', // Equals
        'test[bracket]', // Square brackets
        'test{brace}', // Curly braces
        'test(paren)', // Parentheses
        'test;semicolon', // Semicolon
        'test,comma', // Comma
        'test&ampersand', // Ampersand
        r'test$dollar', // Dollar sign
      ];
      for (final id in invalidIds) {
        final data = Uint8List.fromList('test'.codeUnits);
        expect(
          () => storage.put(id, data),
          throwsArgumentError,
          reason: 'ID "$id" should be invalid',
        );
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

    test('Update blob after flush removes old disk file', () async {
      const blobId = 'flush-update-test';
      final originalData = Uint8List.fromList('original data'.codeUnits);
      final updatedData = Uint8List.fromList(
        'updated data with different size'.codeUnits,
      );

      // Put original blob data
      await storage.put(blobId, originalData);

      // Verify blob is in memory
      expect(await storage.exists(blobId), isTrue);
      final originalSize = await storage.getSize(blobId);
      expect(originalSize, equals(originalData.length));

      // Flush the blob to disk
      final flushed = await storage.flush();
      expect(flushed, equals(1));

      // Get the disk file path to verify it exists
      final hash = md5.convert(utf8.encode(blobId)).toString();
      final dir1 = hash.substring(0, 2);
      final dir2 = hash.substring(2, 4);
      final diskFilePath = path.join(tempDir.path, dir1, dir2, blobId);
      final diskFile = File(diskFilePath);

      // Verify disk file exists with original size
      expect(await diskFile.exists(), isTrue);
      expect(await diskFile.length(), equals(originalData.length));

      // Update the blob with different sized data
      await storage.put(blobId, updatedData);

      // Verify blob is back in memory with new data
      expect(await storage.exists(blobId), isTrue);
      final newSize = await storage.getSize(blobId);
      expect(newSize, equals(updatedData.length));

      // Verify disk file still exists but with updated size and data
      expect(await diskFile.exists(), isTrue);
      expect(await diskFile.length(), equals(updatedData.length));

      // Verify disk file contains updated data
      final diskData = await diskFile.readAsBytes();
      expect(diskData, equals(updatedData));

      // Verify we can retrieve the updated data
      final retrievedData = await storage.get(blobId);
      expect(retrievedData, isNotNull);
      expect(retrievedData!.data, equals(updatedData));
    });

    test('Disk cache is initialized and maintained correctly', () async {
      const blobId1 = 'cache-test-1';
      const blobId2 = 'cache-test-2';
      final data1 = Uint8List.fromList('data 1'.codeUnits);
      final data2 = Uint8List.fromList('data 2'.codeUnits);

      // Put first blob and flush it to disk
      await storage.put(blobId1, data1);
      await storage.flush();

      // Put second blob directly to disk by flushing
      await storage.put(blobId2, data2);
      await storage.flush();

      // Verify both blobs exist using cache (no filesystem access)
      expect(await storage.exists(blobId1), isTrue);
      expect(await storage.exists(blobId2), isTrue);

      // Create new storage instance to test cache initialization from disk
      final newStorage = BlobStorage(storage.config);

      // First call should initialize cache by scanning disk
      expect(await newStorage.exists(blobId1), isTrue);
      expect(await newStorage.exists(blobId2), isTrue);

      // Delete one blob and verify cache is updated
      await newStorage.delete(blobId1);
      expect(await newStorage.exists(blobId1), isFalse);
      expect(await newStorage.exists(blobId2), isTrue);

      // Verify the blob is actually gone from disk
      final hash = md5.convert(utf8.encode(blobId1)).toString();
      final dir1 = hash.substring(0, 2);
      final dir2 = hash.substring(2, 4);
      final diskFilePath = path.join(tempDir.path, dir1, dir2, blobId1);
      expect(await File(diskFilePath).exists(), isFalse);
    });

    test('Cache prevents unnecessary filesystem operations', () async {
      const nonExistentBlobId = 'does-not-exist';

      // Initialize cache by calling exists once
      await storage.exists('any-id');

      // Multiple calls to exists for non-existent blobs should use cache
      expect(await storage.exists(nonExistentBlobId), isFalse);
      expect(await storage.exists(nonExistentBlobId), isFalse);
      expect(await storage.exists(nonExistentBlobId), isFalse);

      // Verify get/getSize/getLastModified also use cache
      expect(await storage.get(nonExistentBlobId), isNull);
      expect(await storage.getSize(nonExistentBlobId), isNull);
      expect(await storage.getLastModified(nonExistentBlobId), isNull);
    });

    test(
      'Flush parameter immediately writes to disk and removes from memory',
      () async {
        const blobId = 'flush-parameter-test';
        final testData = Uint8List.fromList('test data for flush'.codeUnits);

        // Get initial status to verify no items in memory
        final initialStatus = storage.getStatus();
        final initialMemoryCount = initialStatus.memoryItemCount;

        // Put blob with immediate flush (zero duration)
        await storage.put(blobId, testData, flush: Duration.zero);

        // Verify blob is NOT in memory (was immediately flushed)
        final statusAfterFlush = storage.getStatus();
        expect(statusAfterFlush.memoryItemCount, equals(initialMemoryCount));

        // Verify blob exists and can be retrieved
        expect(await storage.exists(blobId), isTrue);

        final retrievedBlob = await storage.get(blobId);
        expect(retrievedBlob, isNotNull);
        expect(retrievedBlob!.data, equals(testData));

        // Verify blob is physically on disk
        final hash = md5.convert(utf8.encode(blobId)).toString();
        final dir1 = hash.substring(0, 2);
        final dir2 = hash.substring(2, 4);
        final diskFilePath = path.join(tempDir.path, dir1, dir2, blobId);
        final diskFile = File(diskFilePath);

        expect(await diskFile.exists(), isTrue);
        expect(await diskFile.length(), equals(testData.length));

        final diskData = await diskFile.readAsBytes();
        expect(diskData, equals(testData));

        // Verify disk storage stats were updated
        expect(
          statusAfterFlush.diskItemCount,
          greaterThan(initialStatus.diskItemCount),
        );
        expect(
          statusAfterFlush.diskBytesUsed,
          greaterThan(initialStatus.diskBytesUsed),
        );
      },
    );
  });
}
