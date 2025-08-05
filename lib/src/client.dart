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

  /// Close the HTTP client.
  void close() {
    _httpClient.close();
  }

  /// Get blob metadata (size, last-modified).
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

  /// Get blob data as bytes.
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

  /// Stream blob to file, returns true if successful.
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

  /// Store blob data from bytes.
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

  /// Stream file to blob storage.
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

  /// Delete blob, returns true if found.
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

  /// Get service statistics and metrics.
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

  /// Check if blob exists.
  Future<bool> exists(String blobId) async {
    final metadata = await head(blobId);
    return metadata != null;
  }

  /// Get blob size in bytes.
  Future<int?> getSize(String blobId) async {
    final metadata = await head(blobId);
    return metadata?.size;
  }

  /// Get blob last modified time.
  Future<DateTime?> getLastModified(String blobId) async {
    final metadata = await head(blobId);
    return metadata?.lastModified;
  }

  /// Move blobs from memory to disk, returns count flushed.
  Future<int> flush({int? limit, Duration? age}) async {
    final uri = Uri.parse('$baseUrl/flush');
    final queryParams = <String, String>{};

    if (limit != null) {
      String limitStr;
      if (limit >= 1000000000) {
        limitStr = '${limit ~/ 1000000000}b';
      } else if (limit >= 1000000) {
        limitStr = '${limit ~/ 1000000}m';
      } else if (limit >= 1000) {
        limitStr = '${limit ~/ 1000}k';
      } else {
        limitStr = limit.toString();
      }
      queryParams['limit'] = limitStr;
    }

    if (age != null) {
      String ageStr;
      if (age.inDays > 0) {
        ageStr = '${age.inDays}d';
      } else if (age.inHours > 0) {
        ageStr = '${age.inHours}h';
      } else if (age.inMinutes > 0) {
        ageStr = '${age.inMinutes}m';
      } else {
        ageStr = '${age.inSeconds}s';
      }
      queryParams['age'] = ageStr;
    }

    final flushUri = uri.replace(queryParameters: queryParams);
    final response = await _httpClient.post(flushUri);

    if (response.statusCode == 409) {
      throw BlobinatorException('Cannot flush when disk storage is disabled');
    }

    if (response.statusCode == 400) {
      throw BlobinatorException('Bad request: ${response.body}');
    }

    if (response.statusCode != 200) {
      throw BlobinatorException(
        'Flush request failed with status ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['flushed'] as int;
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
