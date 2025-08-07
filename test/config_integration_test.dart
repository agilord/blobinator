import 'dart:io';

import 'package:blobinator/src/http_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('Configuration Integration Tests', () {
    late Process serverProcess;
    late HttpBlobinator client;

    setUp(() async {
      // Start the CLI server with custom limits: 100 byte key, 1KB value
      serverProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'serve',
        '--host',
        '127.0.0.1',
        '--port',
        '8084',
        '--key-max-length',
        '100',
        '--value-max-length',
        '1KB',
      ], workingDirectory: Directory.current.path);

      // Wait for server to be ready by polling the status endpoint
      await _waitForServerReady('http://127.0.0.1:8084');

      // Create HTTP client
      client = HttpBlobinator('http://127.0.0.1:8084');
    });

    tearDown(() async {
      await client.close();
      serverProcess.kill();
      await serverProcess.exitCode;
    });

    test('should enforce custom key length limits', () async {
      // Test key that's exactly at the limit (100 bytes)
      final validKey = List.filled(100, 65); // 100 'A' characters
      final smallData = 'test'.codeUnits;

      // Should succeed
      final success = await client.updateBlob(validKey, smallData);
      expect(success, isTrue);

      // Test key that's over the limit (101 bytes)
      final invalidKey = List.filled(101, 65); // 101 'A' characters

      // Should throw ArgumentError
      expect(() async {
        await client.updateBlob(invalidKey, smallData);
      }, throwsA(isA<ArgumentError>()));
    });

    test('should enforce custom value length limits', () async {
      final key = 'test-value-limit'.codeUnits;

      // Test value that's exactly at the limit (1000 bytes for 1KB)
      final validValue = List.filled(999, 65); // 999 bytes, under 1KB limit

      // Should succeed
      final success = await client.updateBlob(key, validValue);
      expect(success, isTrue);

      // Test value that's over the limit (1001 bytes)
      final invalidValue = List.filled(1001, 65); // Over 1KB limit

      // Should throw ArgumentError
      expect(() async {
        await client.updateBlob(key, invalidValue);
      }, throwsA(isA<ArgumentError>()));
    });
  });
}

/// Waits for the server to be ready by polling the status endpoint.
Future<void> _waitForServerReady(String baseUrl) async {
  const maxAttempts = 30; // 15 seconds max wait time
  const retryDelay = Duration(milliseconds: 500);

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/status'),
            headers: {'Connection': 'close'}, // Avoid connection pooling issues
          )
          .timeout(Duration(seconds: 2)); // Short timeout per request

      if (response.statusCode == 200) {
        // Server is ready
        return;
      }
    } catch (e) {
      // Server not ready yet, continue polling
      if (attempt == maxAttempts) {
        throw Exception(
          'Server failed to start after ${maxAttempts * 500}ms. Last error: $e',
        );
      }
    }

    await Future.delayed(retryDelay);
  }
}
