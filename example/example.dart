import 'dart:convert';
import 'dart:typed_data';

import 'package:blobinator/src/http_client.dart';

/// Example demonstrating HTTP client usage with a Blobinator server.
///
/// This example shows:
/// - Using HttpBlobinator client to perform CRUD operations
/// - Working with different key formats (UTF-8 and base64)
/// - Version-based operations for optimistic concurrency control
/// - TTL (time-to-live) functionality
/// - Error handling and statistics
Future<void> main() async {
  // Connect to a Blobinator server (start one with: dart run blobinator serve)
  final baseUrl = 'http://localhost:8080';
  final client = HttpBlobinator(baseUrl);

  try {
    print('Blobinator HTTP Client Example');
    print('Connecting to: $baseUrl\n');

    // Basic CRUD operations
    print('1. Basic Operations');
    final key = utf8.encode('demo-key');
    final data = utf8.encode('Hello from HTTP client!');

    await client.updateBlob(key, data);
    print('   - Stored blob');

    final blob = await client.getBlob(key);
    print('   - Retrieved: "${utf8.decode(blob!.bytes)}"');

    final metadata = await client.getBlobMetadata(key);
    print(
      '   - Metadata: ${metadata!.size} bytes, version ${_formatVersion(metadata.version)}',
    );

    await client.deleteBlob(key);
    print('   - Deleted blob\n');

    // Version control
    print('2. Version Control');
    final versionKey = utf8.encode('version-test');
    await client.updateBlob(versionKey, utf8.encode('Initial content'));

    final initialBlob = await client.getBlob(versionKey);
    final currentVersion = initialBlob!.version;
    print('   - Initial version: ${_formatVersion(currentVersion)}');

    // Update with correct version
    final updateSuccess = await client.updateBlob(
      versionKey,
      utf8.encode('Updated content'),
      version: currentVersion,
    );
    print('   - Version-based update: ${updateSuccess ? "Success" : "Failed"}');

    // Try update with old version (should fail)
    final wrongUpdate = await client.updateBlob(
      versionKey,
      utf8.encode('Should fail'),
      version: currentVersion, // outdated
    );
    print(
      '   - Outdated version update: ${wrongUpdate ? "Unexpected success" : "Failed as expected"}',
    );

    await client.deleteBlob(versionKey);
    print('');

    // TTL functionality
    print('3. TTL (Time-to-Live)');
    final ttlKey = utf8.encode('ttl-test');
    await client.updateBlob(
      ttlKey,
      utf8.encode('Expires soon!'),
      ttl: Duration(seconds: 2),
    );
    print('   - Stored blob with 2s TTL');

    var ttlBlob = await client.getBlob(ttlKey);
    print(
      '   - Retrieved immediately: ${ttlBlob != null ? "Found" : "Not found"}',
    );

    await Future.delayed(Duration(seconds: 3));
    ttlBlob = await client.getBlob(ttlKey);
    print(
      '   - Retrieved after expiration: ${ttlBlob != null ? "Still there" : "Expired as expected"}\n',
    );

    // Different key formats
    print('4. Key Formats');

    // UTF-8 path-like key
    final pathKey = utf8.encode('files/document.pdf');
    await client.updateBlob(pathKey, utf8.encode('PDF content'));
    print('   - UTF-8 path key: files/document.pdf');

    // Binary key
    final binaryKey = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0x00]);
    await client.updateBlob(binaryKey, utf8.encode('Binary key content'));
    print('   - Binary key: [${binaryKey.join(', ')}]');

    // Special base64 prefix
    final specialKey = utf8.encode('base64:forced-encoding');
    await client.updateBlob(specialKey, utf8.encode('Special content'));
    print('   - Base64-prefixed key forces base64 encoding');

    await client.deleteBlob(pathKey);
    await client.deleteBlob(binaryKey);
    await client.deleteBlob(specialKey);
    print('');

    // Statistics and error handling
    print('5. Statistics & Error Handling');

    // Store test data
    for (int i = 0; i < 3; i++) {
      await client.updateBlob(utf8.encode('test-$i'), utf8.encode('Data $i'));
    }

    final stats = await client.getStatistics();
    print(
      '   - Server stats: ${stats.totalBlobCount} blobs, ${stats.totalValuesSize} bytes',
    );

    // Test error cases
    final nonExistent = await client.getBlob(utf8.encode('does-not-exist'));
    print(
      '   - Non-existent blob: ${nonExistent == null ? "null as expected" : "unexpected result"}',
    );

    // Empty blob
    final emptyKey = utf8.encode('empty');
    await client.updateBlob(emptyKey, []);
    final emptyBlob = await client.getBlob(emptyKey);
    print('   - Empty blob: ${emptyBlob!.bytes.length} bytes');

    // Clean up
    for (int i = 0; i < 3; i++) {
      await client.deleteBlob(utf8.encode('test-$i'));
    }
    await client.deleteBlob(emptyKey);

    print('\n- Example completed successfully!');
  } catch (e) {
    print('Error: $e');
    print('\nMake sure a Blobinator server is running:');
    print('  dart run blobinator serve --port 8080');
  } finally {
    await client.close();
  }
}

String _formatVersion(Uint8List version) {
  return version
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .take(4)
      .join('');
}
