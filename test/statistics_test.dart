import 'dart:convert';
import 'dart:io';

import 'package:blobinator/src/http_client.dart';
import 'package:blobinator/src/http_server.dart';
import 'package:blobinator/src/sqlite_blobinator.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('SqliteBlobinator Statistics', () {
    late SqliteBlobinator blobinator;

    setUp(() {
      blobinator = SqliteBlobinator.inMemory();
    });

    tearDown(() async {
      await blobinator.close();
    });

    test('should start with empty statistics', () async {
      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(0));
      expect(stats.totalKeysSize, equals(0));
      expect(stats.totalValuesSize, equals(0));
    });

    test('should track statistics when adding blobs', () async {
      final key1 = [1, 2, 3];
      final value1 = [10, 20, 30, 40];
      final key2 = [4, 5];
      final value2 = [50, 60];

      await blobinator.updateBlob(key1, value1);
      var stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(3));
      expect(stats.totalValuesSize, equals(4));

      await blobinator.updateBlob(key2, value2);
      stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(2));
      expect(stats.totalKeysSize, equals(5)); // 3 + 2
      expect(stats.totalValuesSize, equals(6)); // 4 + 2
    });

    test('should track statistics when updating blobs', () async {
      final key = [1, 2, 3];
      final value1 = [10, 20];
      final value2 = [30, 40, 50, 60];

      // Add initial blob
      await blobinator.updateBlob(key, value1);
      var stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(3));
      expect(stats.totalValuesSize, equals(2));

      // Update blob (larger value)
      final blob = await blobinator.getBlob(key);
      await blobinator.updateBlob(key, value2, version: blob!.version);
      stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1)); // Same count
      expect(stats.totalKeysSize, equals(3)); // Same key size
      expect(stats.totalValuesSize, equals(4)); // Updated value size
    });

    test('should track statistics when deleting blobs', () async {
      final key1 = [1, 2, 3];
      final value1 = [10, 20, 30, 40];
      final key2 = [4, 5];
      final value2 = [50, 60];

      // Add two blobs
      await blobinator.updateBlob(key1, value1);
      await blobinator.updateBlob(key2, value2);

      // Delete one blob
      await blobinator.deleteBlob(key1);
      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(2));
      expect(stats.totalValuesSize, equals(2));
    });

    test('should track statistics when removing expired blobs', () async {
      final key = [1, 2, 3];
      final value = [10, 20, 30];

      // Add blob with very short TTL
      await blobinator.updateBlob(key, value, ttl: Duration(milliseconds: 1));

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 10));

      // Remove expired blobs
      await blobinator.removeExpired();

      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(0));
      expect(stats.totalKeysSize, equals(0));
      expect(stats.totalValuesSize, equals(0));
    });
  });

  group('SqliteBlobinator Statistics', () {
    late SqliteBlobinator blobinator;

    setUp(() {
      blobinator = SqliteBlobinator.inMemory();
    });

    tearDown(() async {
      await blobinator.close();
    });

    test('should start with empty statistics', () async {
      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(0));
      expect(stats.totalKeysSize, equals(0));
      expect(stats.totalValuesSize, equals(0));
    });

    test('should track statistics when adding blobs', () async {
      final key1 = [1, 2, 3];
      final value1 = [10, 20, 30, 40];
      final key2 = [4, 5];
      final value2 = [50, 60];

      await blobinator.updateBlob(key1, value1);
      var stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(3));
      expect(stats.totalValuesSize, equals(4));

      await blobinator.updateBlob(key2, value2);
      stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(2));
      expect(stats.totalKeysSize, equals(5)); // 3 + 2
      expect(stats.totalValuesSize, equals(6)); // 4 + 2
    });

    test('should track statistics when updating blobs', () async {
      final key = [1, 2, 3];
      final value1 = [10, 20];
      final value2 = [30, 40, 50, 60];

      // Add initial blob
      await blobinator.updateBlob(key, value1);
      var stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(3));
      expect(stats.totalValuesSize, equals(2));

      // Update blob (larger value)
      final blob = await blobinator.getBlob(key);
      await blobinator.updateBlob(key, value2, version: blob!.version);
      stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1)); // Same count
      expect(stats.totalKeysSize, equals(3)); // Same key size
      expect(stats.totalValuesSize, equals(4)); // Updated value size
    });

    test('should track statistics when deleting blobs', () async {
      final key1 = [1, 2, 3];
      final value1 = [10, 20, 30, 40];
      final key2 = [4, 5];
      final value2 = [50, 60];

      // Add two blobs
      await blobinator.updateBlob(key1, value1);
      await blobinator.updateBlob(key2, value2);

      // Delete one blob
      await blobinator.deleteBlob(key1);
      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(1));
      expect(stats.totalKeysSize, equals(2));
      expect(stats.totalValuesSize, equals(2));
    });

    test('should track statistics when removing expired blobs', () async {
      final key = [1, 2, 3];
      final value = [10, 20, 30];

      // Add blob with very short TTL
      await blobinator.updateBlob(key, value, ttl: Duration(milliseconds: 1));

      // Wait for expiration
      await Future.delayed(Duration(milliseconds: 10));

      // Remove expired blobs
      await blobinator.removeExpired();

      final stats = await blobinator.getStatistics();
      expect(stats.totalBlobCount, equals(0));
      expect(stats.totalKeysSize, equals(0));
      expect(stats.totalValuesSize, equals(0));
    });
  });

  group('HTTP Server Statistics Endpoint', () {
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
      await server.close();
    });

    test('should return statistics via HTTP endpoint', () async {
      // Add some test data
      final key1 = utf8.encode('test-key-1');
      final value1 = utf8.encode('test-value-1');
      final key2 = utf8.encode('key2');
      final value2 = utf8.encode('value2');

      await client.updateBlob(key1, value1);
      await client.updateBlob(key2, value2);

      // Make HTTP request to /status endpoint
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse('$baseUrl/status'));
        final response = await request.close();

        expect(response.statusCode, equals(200));
        expect(
          response.headers.contentType?.mimeType,
          equals('application/json'),
        );

        final responseBody = await response.transform(utf8.decoder).join();
        final stats = jsonDecode(responseBody) as Map<String, dynamic>;

        expect(stats['totalBlobCount'], equals(2));
        expect(stats['totalKeysSize'], equals(key1.length + key2.length));
        expect(stats['totalValuesSize'], equals(value1.length + value2.length));
      } finally {
        httpClient.close();
      }
    });

    test('should return empty statistics when no blobs exist', () async {
      // Make HTTP request to /status endpoint
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse('$baseUrl/status'));
        final response = await request.close();

        expect(response.statusCode, equals(200));
        expect(
          response.headers.contentType?.mimeType,
          equals('application/json'),
        );

        final responseBody = await response.transform(utf8.decoder).join();
        final stats = jsonDecode(responseBody) as Map<String, dynamic>;

        expect(stats['totalBlobCount'], equals(0));
        expect(stats['totalKeysSize'], equals(0));
        expect(stats['totalValuesSize'], equals(0));
      } finally {
        httpClient.close();
      }
    });
  });
}
