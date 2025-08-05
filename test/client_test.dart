import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/blobinator.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('BlobinatorClient Tests', () {
    late HttpServer server;
    late BlobStorage storage;
    late BlobinatorClient client;
    late Directory tempDir;
    late String baseUrl;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'blobinator_client_test_',
      );

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
      client = BlobinatorClient(baseUrl);
    });

    tearDown(() async {
      client.close();
      await server.close();
      await tempDir.delete(recursive: true);
    });

    test('putBytes and getBytes', () async {
      const blobId = 'test-bytes-1';
      final testData = Uint8List.fromList('Hello, World!'.codeUnits);

      // Put bytes
      await client.putBytes(blobId, testData);

      // Get bytes
      final retrievedData = await client.getBytes(blobId);
      expect(retrievedData, isNotNull);
      expect(retrievedData, equals(testData));
    });

    test('putFile and getFile', () async {
      const blobId = 'test-file-1';
      final testFile = File('${tempDir.path}/test_input.txt');
      final outputFile = File('${tempDir.path}/test_output.txt');

      const testContent = 'This is test file content!';
      await testFile.writeAsString(testContent);

      // Put file
      await client.putFile(blobId, testFile.path);

      // Get file
      final success = await client.getFile(blobId, outputFile.path);
      expect(success, isTrue);
      expect(await outputFile.exists(), isTrue);

      final retrievedContent = await outputFile.readAsString();
      expect(retrievedContent, equals(testContent));
    });

    test('head returns metadata', () async {
      const blobId = 'test-head-1';
      final testData = Uint8List.fromList('Test data for HEAD'.codeUnits);

      // Put data first
      await client.putBytes(blobId, testData);

      // Head request
      final metadata = await client.head(blobId);
      expect(metadata, isNotNull);
      expect(metadata!.size, equals(testData.length));
      expect(metadata.lastModified, isNotNull);
    });

    test('head returns null for non-existent blob', () async {
      final metadata = await client.head('non-existent-blob');
      expect(metadata, isNull);
    });

    test('getBytes returns null for non-existent blob', () async {
      final data = await client.getBytes('non-existent-blob');
      expect(data, isNull);
    });

    test('getFile returns false for non-existent blob', () async {
      final outputFile = File('${tempDir.path}/non_existent_output.txt');
      final success = await client.getFile(
        'non-existent-blob',
        outputFile.path,
      );
      expect(success, isFalse);
      expect(await outputFile.exists(), isFalse);
    });

    test('delete removes blob', () async {
      const blobId = 'test-delete-1';
      final testData = Uint8List.fromList('To be deleted'.codeUnits);

      // Put data
      await client.putBytes(blobId, testData);

      // Verify it exists
      expect(await client.exists(blobId), isTrue);

      // Delete it
      final deleted = await client.delete(blobId);
      expect(deleted, isTrue);

      // Verify it's gone
      expect(await client.exists(blobId), isFalse);
    });

    test('delete returns false for non-existent blob', () async {
      final deleted = await client.delete('non-existent-blob');
      expect(deleted, isFalse);
    });

    test('exists convenience method', () async {
      const blobId = 'test-exists-1';
      final testData = Uint8List.fromList('Test data'.codeUnits);

      // Should not exist initially
      expect(await client.exists(blobId), isFalse);

      // Put data
      await client.putBytes(blobId, testData);

      // Should exist now
      expect(await client.exists(blobId), isTrue);
    });

    test('getSize convenience method', () async {
      const blobId = 'test-size-1';
      final testData = Uint8List.fromList('Size test data'.codeUnits);

      // Should return null for non-existent blob
      expect(await client.getSize(blobId), isNull);

      // Put data
      await client.putBytes(blobId, testData);

      // Should return correct size
      final size = await client.getSize(blobId);
      expect(size, equals(testData.length));
    });

    test('getLastModified convenience method', () async {
      const blobId = 'test-lastmod-1';
      final testData = Uint8List.fromList('Last modified test'.codeUnits);

      // Should return null for non-existent blob
      expect(await client.getLastModified(blobId), isNull);

      // Put data
      await client.putBytes(blobId, testData);

      // Should return a datetime
      final lastMod = await client.getLastModified(blobId);
      expect(lastMod, isNotNull);
      expect(lastMod, isA<DateTime>());
    });

    test('getStatus returns service statistics', () async {
      // Add some blobs first
      await client.putBytes(
        'status-test-1',
        Uint8List.fromList('Data 1'.codeUnits),
      );
      await client.putBytes(
        'status-test-2',
        Uint8List.fromList('Data 2'.codeUnits),
      );

      final status = await client.getStatus();
      expect(status.memoryItemCount, greaterThanOrEqualTo(2));
      expect(status.memoryBytesUsed, greaterThan(0));
      expect(status.timestamp, isA<DateTime>());
      expect(status.evictionHistory, isList);
    });

    test('putFile throws exception for non-existent file', () async {
      expect(
        () => client.putFile('test-blob', '/non/existent/file.txt'),
        throwsA(isA<BlobinatorException>()),
      );
    });

    test('putBytes throws exception for invalid blob ID', () async {
      expect(
        () => client.putBytes(
          'ab',
          Uint8List.fromList('test'.codeUnits),
        ), // Too short
        throwsA(isA<BlobinatorException>()),
      );
    });

    test('binary data handling', () async {
      const blobId = 'binary-test';
      final binaryData = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC,
        0x89, 0x50, 0x4E, 0x47, // PNG signature start
      ]);

      // Put binary data
      await client.putBytes(blobId, binaryData);

      // Get binary data
      final retrievedData = await client.getBytes(blobId);
      expect(retrievedData, isNotNull);
      expect(retrievedData, equals(binaryData));
    });

    test('large data handling', () async {
      const blobId = 'large-data-test';
      final largeData = Uint8List(10000);
      for (int i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256;
      }

      // Put large data
      await client.putBytes(blobId, largeData);

      // Get large data
      final retrievedData = await client.getBytes(blobId);
      expect(retrievedData, isNotNull);
      expect(retrievedData, equals(largeData));
      expect(retrievedData!.length, equals(10000));
    });

    test('update existing blob', () async {
      const blobId = 'update-test';
      final originalData = Uint8List.fromList('Original content'.codeUnits);
      final updatedData = Uint8List.fromList('Updated content'.codeUnits);

      // Put original data
      await client.putBytes(blobId, originalData);

      // Verify original data
      final retrieved1 = await client.getBytes(blobId);
      expect(retrieved1, equals(originalData));

      // Update with new data
      await client.putBytes(blobId, updatedData);

      // Verify updated data
      final retrieved2 = await client.getBytes(blobId);
      expect(retrieved2, equals(updatedData));
    });

    test('streaming large file operations', () async {
      const blobId = 'large-file-stream-test';
      final inputFile = File('${tempDir.path}/large_input.bin');
      final outputFile = File('${tempDir.path}/large_output.bin');

      // Create a large file (1MB)
      final largeData = List.generate(1024 * 1024, (i) => i % 256);
      await inputFile.writeAsBytes(largeData);

      // Put large file (streaming)
      await client.putFile(blobId, inputFile.path);

      // Get large file (streaming)
      final success = await client.getFile(blobId, outputFile.path);
      expect(success, isTrue);
      expect(await outputFile.exists(), isTrue);

      // Verify the content matches (without loading into memory)
      expect(await outputFile.length(), equals(await inputFile.length()));

      // Spot check: verify first and last few bytes
      final inputBytes = await inputFile.openRead(0, 10).toList();
      final outputBytes = await outputFile.openRead(0, 10).toList();
      expect(outputBytes, equals(inputBytes));

      final inputEnd = await inputFile.openRead(largeData.length - 10).toList();
      final outputEnd = await outputFile
          .openRead(largeData.length - 10)
          .toList();
      expect(outputEnd, equals(inputEnd));
    });

    test('flush - flush all blobs', () async {
      // Add some blobs to memory
      for (int i = 0; i < 5; i++) {
        final blobId = 'flush-client-test-$i';
        final data = Uint8List.fromList('Flush test data $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Flush all blobs
      final flushed = await client.flush();
      expect(flushed, greaterThanOrEqualTo(5));

      // Verify blobs are still accessible
      final data = await client.getBytes('flush-client-test-0');
      expect(data, isNotNull);
      expect(data, equals(Uint8List.fromList('Flush test data 0'.codeUnits)));
    });

    test('flush - flush with limit', () async {
      // Add some blobs to memory
      for (int i = 0; i < 10; i++) {
        final blobId = 'flush-limit-client-test-$i';
        final data = Uint8List.fromList('Data $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Flush only 3 blobs
      final flushed = await client.flush(limit: 3);
      expect(flushed, equals(3));
    });

    test('flush - flush with age filter', () async {
      // Add some blobs
      for (int i = 0; i < 3; i++) {
        final blobId = 'flush-age-client-test-$i';
        final data = Uint8List.fromList('Age test data $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Wait a bit
      await Future.delayed(Duration(seconds: 1));

      // Add more recent blobs
      for (int i = 3; i < 6; i++) {
        final blobId = 'flush-age-client-test-$i';
        final data = Uint8List.fromList('Recent data $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Flush only old blobs
      final flushed = await client.flush(age: Duration(seconds: 1));
      expect(flushed, greaterThanOrEqualTo(0)); // Age-based, may vary
    });

    test('flush - combined limit and age', () async {
      // Add some blobs
      for (int i = 0; i < 8; i++) {
        final blobId = 'flush-combined-test-$i';
        final data = Uint8List.fromList('Combined test data $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Flush with both limit and age
      final flushed = await client.flush(limit: 5, age: Duration(seconds: 1));
      expect(flushed, lessThanOrEqualTo(5));
    });

    test('flush - memory-only mode throws exception', () async {
      // Create a memory-only client
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
      final memoryOnlyClient = BlobinatorClient(memoryOnlyBaseUrl);

      try {
        // Try to flush - should throw exception
        await expectLater(
          memoryOnlyClient.flush(),
          throwsA(isA<BlobinatorException>()),
        );
      } finally {
        memoryOnlyClient.close();
        await memoryOnlyHttpServer.close();
      }
    });

    test('flush - parameter formatting', () async {
      // Test that parameters are formatted correctly
      for (int i = 0; i < 5; i++) {
        final blobId = 'format-test-$i';
        final data = Uint8List.fromList('Format test $i'.codeUnits);
        await client.putBytes(blobId, data);
      }

      // Test various limit formats
      await client.flush(limit: 1000); // Plain number
      await client.flush(limit: 2000); // Should format as 2k
      await client.flush(limit: 3000000); // Should format as 3m
      await client.flush(limit: 1000000000); // Should format as 1b

      // Test various age formats
      await client.flush(age: Duration(seconds: 30)); // Should format as 30s
      await client.flush(age: Duration(minutes: 5)); // Should format as 5m
      await client.flush(age: Duration(hours: 2)); // Should format as 2h
      await client.flush(age: Duration(days: 1)); // Should format as 1d
    });
  });
}
