import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class BlobinatorClient {
  final String baseUrl;
  final http.Client _httpClient;

  BlobinatorClient(this.baseUrl, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  void close() {
    _httpClient.close();
  }

  /// Check if a blob exists and get its metadata
  Future<BlobMetadata?> head(String blobId) async {
    final response = await _httpClient.head(
      Uri.parse('$baseUrl/blobs/$blobId'),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'HEAD request failed with status ${response.statusCode}',
      );
    }

    final contentLength = response.headers['content-length'];
    final lastModified = response.headers['last-modified'];

    return BlobMetadata(
      size: contentLength != null ? int.parse(contentLength) : 0,
      lastModified: lastModified != null ? HttpDate.parse(lastModified) : null,
    );
  }

  /// Get a blob as bytes
  Future<Uint8List?> getBytes(String blobId) async {
    final response = await _httpClient.get(Uri.parse('$baseUrl/blobs/$blobId'));

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'GET request failed with status ${response.statusCode}',
      );
    }

    return Uint8List.fromList(response.bodyBytes);
  }

  /// Get a blob and save it to a file (streaming)
  Future<bool> getFile(String blobId, String filePath) async {
    final request = http.Request('GET', Uri.parse('$baseUrl/blobs/$blobId'));
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode == 404) {
      return false;
    }

    if (streamedResponse.statusCode != 200) {
      throw BlobinatorException(
        'GET request failed with status ${streamedResponse.statusCode}',
      );
    }

    final file = File(filePath);
    final sink = file.openWrite();

    try {
      await streamedResponse.stream.pipe(sink);
    } finally {
      await sink.close();
    }

    // Set file modification time if available
    final lastModified = streamedResponse.headers['last-modified'];
    if (lastModified != null) {
      try {
        final modTime = HttpDate.parse(lastModified);
        await file.setLastModified(modTime);
      } catch (_) {
        // Ignore if we can't parse or set the modification time
      }
    }

    return true;
  }

  /// Put a blob from bytes
  Future<void> putBytes(String blobId, List<int> data) async {
    final response = await _httpClient.put(
      Uri.parse('$baseUrl/blobs/$blobId'),
      body: data,
    );

    if (response.statusCode == 400) {
      throw BlobinatorException('Invalid blob ID: $blobId');
    }

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'PUT request failed with status ${response.statusCode}',
      );
    }
  }

  /// Put a blob from a file (streaming)
  Future<void> putFile(String blobId, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw BlobinatorException('File not found: $filePath');
    }

    final request = http.StreamedRequest(
      'PUT',
      Uri.parse('$baseUrl/blobs/$blobId'),
    );
    request.contentLength = await file.length();

    // Stream the file content
    file.openRead().listen(
      (chunk) => request.sink.add(chunk),
      onDone: () => request.sink.close(),
      onError: (error) => request.sink.addError(error),
    );

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode == 400) {
      throw BlobinatorException('Invalid blob ID: $blobId');
    }

    if (streamedResponse.statusCode != 200) {
      throw BlobinatorException(
        'PUT request failed with status ${streamedResponse.statusCode}',
      );
    }
  }

  /// Delete a blob
  Future<bool> delete(String blobId) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/blobs/$blobId'),
    );

    if (response.statusCode == 404) {
      return false;
    }

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'DELETE request failed with status ${response.statusCode}',
      );
    }

    return true;
  }

  /// Get service status
  Future<ServiceStatus> getStatus() async {
    final response = await _httpClient.get(Uri.parse('$baseUrl/status'));

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'Status request failed with status ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ServiceStatus.fromJson(json);
  }

  /// Check if a blob exists (convenience method)
  Future<bool> exists(String blobId) async {
    final metadata = await head(blobId);
    return metadata != null;
  }

  /// Get blob size (convenience method)
  Future<int?> getSize(String blobId) async {
    final metadata = await head(blobId);
    return metadata?.size;
  }

  /// Get blob last modified time (convenience method)
  Future<DateTime?> getLastModified(String blobId) async {
    final metadata = await head(blobId);
    return metadata?.lastModified;
  }
}

class BlobMetadata {
  final int size;
  final DateTime? lastModified;

  const BlobMetadata({required this.size, this.lastModified});
}

class BlobinatorException implements Exception {
  final String message;

  const BlobinatorException(this.message);

  @override
  String toString() => 'BlobinatorException: $message';
}
