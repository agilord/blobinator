// ignore_for_file: unused_local_variable

import 'package:blobinator/blobinator.dart';

void main() async {
  final client = BlobinatorClient('http://localhost:8080');

  // Store and retrieve bytes
  await client.putBytes('my-blob', [1, 2, 3, 4]);
  final data = await client.getBytes('my-blob'); // Uint8List?

  // Store and retrieve files (streaming)
  await client.putFile('large-blob', './input.dat');
  await client.getFile('large-blob', './output.dat'); // bool (success)

  // Check existence and metadata
  final exists = await client.exists('my-blob'); // bool
  final size = await client.getSize('my-blob'); // int?
  final lastMod = await client.getLastModified('my-blob'); // DateTime?

  // Get detailed metadata
  final metadata = await client.head('my-blob'); // BlobMetadata?

  // Delete blobs
  await client.delete('my-blob'); // bool (found and deleted)

  // Service status
  final status = await client.getStatus(); // ServiceStatus

  // Flush memory blobs to disk
  final flushed = await client.flush(); // int (number of blobs flushed)
  final flushedLimited = await client.flush(
    limit: 1000,
  ); // Flush max 1000 blobs
  final flushedOld = await client.flush(
    age: Duration(hours: 1),
  ); // Flush blobs older than 1 hour
  final flushedCombined = await client.flush(
    limit: 500,
    age: Duration(minutes: 30),
  ); // Combined

  // Clean up
  client.close();
}
