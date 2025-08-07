import 'dart:convert';
import 'dart:io';

import 'package:blobinator/src/cli_client.dart';
import 'package:blobinator/src/cli_utils.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('CLI Utils Key Parsing', () {
    test('should parse UTF-8 keys correctly', () {
      final key = parseKeyParameter('hello');
      expect(key, equals(utf8.encode('hello')));
    });

    test('should parse base64 keys correctly', () {
      final key = parseKeyParameter('base64:SGVsbG8=');
      expect(key, equals([72, 101, 108, 108, 111])); // "Hello" in bytes
    });

    test('should encode keys for HTTP URLs', () {
      final encoded = encodeKey(utf8.encode('hello'));
      expect(encoded, equals('hello'));

      final encodedWithSlash = encodeKey(utf8.encode('hello/world'));
      expect(encodedWithSlash, equals('hello/world'));

      final encodedBase64 = encodeKey([72, 101, 108, 108, 111]); // "Hello"
      expect(encodedBase64, equals('Hello'));
    });
  });

  group('ClientCommand', () {
    test('should have all expected subcommands', () {
      final command = ClientCommand();
      final subcommands = command.subcommands.keys.toSet();

      expect(
        subcommands,
        containsAll(['get-metadata', 'get', 'update', 'delete', 'status']),
      );
    });

    test('should require URL parameter or environment variable', () {
      final command = ClientCommand();
      expect(command.argParser.options.containsKey('url'), isTrue);
    });
  });

  group('CLI Client Integration Tests', () {
    late Process serverProcess;
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

      // Wait for server to be ready
      await _waitForServerReady('http://127.0.0.1:$port');
    });

    tearDown(() async {
      serverProcess.kill();
      await serverProcess.exitCode;
    });

    test('should get server status', () async {
      final result = await Process.run('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        'http://127.0.0.1:$port',
        'status',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, equals(0));

      final response = jsonDecode(result.stdout as String);
      expect(response, containsPair('totalBlobCount', 0));
      expect(response, containsPair('totalKeysSize', 0));
      expect(response, containsPair('totalValuesSize', 0));
    });

    test('should handle blob operations via environment variable', () async {
      final env = Map<String, String>.from(Platform.environment);
      env['BLOBINATOR_URL'] = 'http://127.0.0.1:$port';

      // Test getting non-existent blob
      final getResult = await Process.run(
        'dart',
        [
          'bin/blobinator.dart',
          'client',
          'get-metadata',
          '--key',
          'nonexistent',
        ],
        workingDirectory: Directory.current.path,
        environment: env,
      );

      expect(getResult.exitCode, equals(1));
      final errorResponse = jsonDecode(getResult.stderr as String);
      expect(errorResponse, containsPair('error', 'Blob not found'));
    });

    test('should perform complete blob lifecycle', () async {
      final baseUrl = 'http://127.0.0.1:$port';
      final testData = 'Hello, CLI World!';

      // Create temporary file
      final tempDir = await Directory.systemTemp.createTemp('cli_test_');
      final inputFile = File('${tempDir.path}/input.txt');
      final outputFile = File('${tempDir.path}/output.txt');

      try {
        await inputFile.writeAsString(testData);

        // Update blob from file
        final updateResult = await Process.run('dart', [
          'bin/blobinator.dart',
          'client',
          '--url',
          baseUrl,
          'update',
          '--key',
          'test-key',
          '--input',
          inputFile.path,
          '--ttl',
          '1h',
        ], workingDirectory: Directory.current.path);

        expect(updateResult.exitCode, equals(0));
        final updateResponse = jsonDecode(updateResult.stdout as String);
        expect(updateResponse, containsPair('success', true));

        // Get blob metadata
        final metadataResult = await Process.run('dart', [
          'bin/blobinator.dart',
          'client',
          '--url',
          baseUrl,
          'get-metadata',
          '--key',
          'test-key',
        ], workingDirectory: Directory.current.path);

        expect(metadataResult.exitCode, equals(0));
        final metadataResponse =
            jsonDecode(metadataResult.stdout as String) as Map<String, dynamic>;
        expect(metadataResponse['size'], equals(testData.length));
        expect(metadataResponse.containsKey('version'), isTrue);

        // Get blob to file
        final getResult = await Process.run('dart', [
          'bin/blobinator.dart',
          'client',
          '--url',
          baseUrl,
          'get',
          '--key',
          'test-key',
          '--output',
          outputFile.path,
        ], workingDirectory: Directory.current.path);

        expect(getResult.exitCode, equals(0));
        final retrievedData = await outputFile.readAsString();
        expect(retrievedData, equals(testData));

        // Delete blob
        final deleteResult = await Process.run('dart', [
          'bin/blobinator.dart',
          'client',
          '--url',
          baseUrl,
          'delete',
          '--key',
          'test-key',
        ], workingDirectory: Directory.current.path);

        expect(deleteResult.exitCode, equals(0));
        final deleteResponse = jsonDecode(deleteResult.stdout as String);
        expect(deleteResponse, containsPair('success', true));

        // Verify deletion
        final verifyResult = await Process.run('dart', [
          'bin/blobinator.dart',
          'client',
          '--url',
          baseUrl,
          'get-metadata',
          '--key',
          'test-key',
        ], workingDirectory: Directory.current.path);

        expect(verifyResult.exitCode, equals(1));
        final errorResponse = jsonDecode(verifyResult.stderr as String);
        expect(errorResponse, containsPair('error', 'Blob not found'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('should handle base64 keys', () async {
      final baseUrl = 'http://127.0.0.1:$port';
      final testKey = 'base64:SGVsbG8='; // "Hello" in base64
      final testData = 'Base64 key test';

      // Update with base64 key
      final updateProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        baseUrl,
        'update',
        '--key',
        testKey,
      ], workingDirectory: Directory.current.path);

      // Write test data to stdin
      updateProcess.stdin.write(testData);
      await updateProcess.stdin.close();
      final updateExitCode = await updateProcess.exitCode;

      expect(updateExitCode, equals(0));

      // Get metadata with same key
      final metadataResult = await Process.run('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        baseUrl,
        'get-metadata',
        '--key',
        testKey,
      ], workingDirectory: Directory.current.path);

      expect(metadataResult.exitCode, equals(0));
      final metadataResponse =
          jsonDecode(metadataResult.stdout as String) as Map<String, dynamic>;
      expect(metadataResponse['size'], equals(testData.length));
    });

    test('should handle version conflicts', () async {
      final baseUrl = 'http://127.0.0.1:$port';
      final testData = 'Version test data';

      // Create initial blob
      final updateProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        baseUrl,
        'update',
        '--key',
        'version-test',
      ], workingDirectory: Directory.current.path);

      updateProcess.stdin.write(testData);
      await updateProcess.stdin.close();
      await updateProcess.exitCode;

      // Get current version
      final metadataResult = await Process.run('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        baseUrl,
        'get-metadata',
        '--key',
        'version-test',
      ], workingDirectory: Directory.current.path);

      final metadataResponse =
          jsonDecode(metadataResult.stdout as String) as Map<String, dynamic>;
      final version = metadataResponse['version'] as String;

      // Try to update with wrong version
      final wrongVersionProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'client',
        '--url', baseUrl,
        'update',
        '--key', 'version-test',
        '--version', 'V3JvbmdWZXJzaW9u', // "WrongVersion" in base64
      ], workingDirectory: Directory.current.path);

      wrongVersionProcess.stdin.write('New data');
      await wrongVersionProcess.stdin.close();
      final wrongVersionExitCode = await wrongVersionProcess.exitCode;

      expect(wrongVersionExitCode, equals(1));

      // Try to update with correct version
      final correctVersionProcess = await Process.start('dart', [
        'bin/blobinator.dart',
        'client',
        '--url',
        baseUrl,
        'update',
        '--key',
        'version-test',
        '--version',
        version,
      ], workingDirectory: Directory.current.path);

      correctVersionProcess.stdin.write('Updated data');
      await correctVersionProcess.stdin.close();
      final correctVersionExitCode = await correctVersionProcess.exitCode;

      expect(correctVersionExitCode, equals(0));
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
