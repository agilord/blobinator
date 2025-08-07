import 'dart:io';
import 'dart:typed_data';

import 'package:blobinator/src/cli_serve.dart';
import 'package:blobinator/src/cli_utils.dart';
import 'package:blobinator/src/http_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('ServeCommand', () {
    test('should parse default-ttl argument', () {
      final command = ServeCommand();

      // Verify the default-ttl option is available
      expect(command.argParser.options.containsKey('default-ttl'), isTrue);

      // Verify help text
      final option = command.argParser.options['default-ttl'];
      expect(option?.help, contains('Default time-to-live for blobs'));
      expect(option?.help, contains('supports suffixes: s, m, h, d'));
    });

    test('should have all expected options', () {
      final command = ServeCommand();
      final options = command.argParser.options;

      expect(options.containsKey('host'), isTrue);
      expect(options.containsKey('port'), isTrue);
      expect(options.containsKey('key-max-length'), isTrue);
      expect(options.containsKey('value-max-length'), isTrue);
      expect(options.containsKey('default-ttl'), isTrue);
      expect(options.containsKey('path'), isTrue);
      expect(options.containsKey('hybrid'), isTrue);
    });

    test('should parse path argument', () {
      final command = ServeCommand();

      // Verify the path option is available
      expect(command.argParser.options.containsKey('path'), isTrue);

      // Verify help text
      final option = command.argParser.options['path'];
      expect(option?.help, contains('Path to SQLite database file'));
      expect(option?.help, contains('uses in-memory storage if not provided'));
    });
  });

  group('parseDuration', () {
    test('should parse various duration formats', () {
      expect(parseDuration('30'), equals(Duration(seconds: 30)));
      expect(parseDuration('30s'), equals(Duration(seconds: 30)));
      expect(parseDuration('5m'), equals(Duration(minutes: 5)));
      expect(parseDuration('2h'), equals(Duration(hours: 2)));
      expect(parseDuration('1d'), equals(Duration(days: 1)));
    });

    test('should throw FormatException for invalid duration', () {
      expect(() => parseDuration(''), throwsA(isA<FormatException>()));
      expect(() => parseDuration('invalid'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('10x'), throwsA(isA<FormatException>()));
    });
  });

  group('CLI Integration Tests', () {
    late Process serverProcess;
    late HttpBlobinator client;
    late int port;

    setUp(() async {
      // Find a free port
      port = await _findFreePort();

      // Start the CLI server process
      serverProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'serve',
        '--host',
        '127.0.0.1',
        '--port',
        port.toString(),
      ], workingDirectory: Directory.current.path);

      // Wait for server to be ready by polling the status endpoint
      await _waitForServerReady('http://127.0.0.1:$port');

      // Create HTTP client
      client = HttpBlobinator('http://127.0.0.1:$port');
    });

    tearDown(() async {
      await client.close();
      serverProcess.kill();
      await serverProcess.exitCode;
    });

    test(
      'should start server and handle blob operations via HTTP client',
      () async {
        final key = 'test-key'.codeUnits;
        final data = 'Hello, World!'.codeUnits;

        // Test that blob doesn't exist initially
        final initialBlob = await client.getBlob(key);
        expect(initialBlob, isNull);

        // Create blob
        final success = await client.updateBlob(key, data);
        expect(success, isTrue);

        // Get blob
        final blob = await client.getBlob(key);
        expect(blob, isNotNull);
        expect(blob!.bytes, equals(Uint8List.fromList(data)));

        // Get blob metadata
        final metadata = await client.getBlobMetadata(key);
        expect(metadata, isNotNull);
        expect(metadata!.size, equals(data.length));

        // Update blob with version
        final newData = 'Updated data'.codeUnits;
        final updateSuccess = await client.updateBlob(
          key,
          newData,
          version: blob.version,
        );
        expect(updateSuccess, isTrue);

        // Get updated blob
        final updatedBlob = await client.getBlob(key);
        expect(updatedBlob, isNotNull);
        expect(updatedBlob!.bytes, equals(Uint8List.fromList(newData)));

        // Delete blob
        final deleteSuccess = await client.deleteBlob(
          key,
          version: updatedBlob.version,
        );
        expect(deleteSuccess, isTrue);

        // Verify blob is deleted
        final deletedBlob = await client.getBlob(key);
        expect(deletedBlob, isNull);
      },
    );

    test('should handle version conflicts', () async {
      final key = 'conflict-test'.codeUnits;
      final data = 'Initial data'.codeUnits;

      // Create blob
      await client.updateBlob(key, data);
      final blob = await client.getBlob(key);
      expect(blob, isNotNull);

      // Try to update with wrong version
      final wrongVersion = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final success = await client.updateBlob(
        key,
        'New data'.codeUnits,
        version: wrongVersion,
      );
      expect(success, isFalse);

      // Try to delete with wrong version
      final deleteSuccess = await client.deleteBlob(key, version: wrongVersion);
      expect(deleteSuccess, isFalse);

      // Cleanup
      await client.deleteBlob(key, version: blob!.version);
    });
  });
}

/// Finds a free port by creating a server socket and immediately closing it.
Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind('localhost', 0);
  final port = socket.port;
  await socket.close();
  return port;
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
