import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'cli_utils.dart';

class HttpBlobinator implements Blobinator {
  final String baseUrl;
  final http.Client _client;

  HttpBlobinator(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  String _encodeKey(List<int> key) {
    return encodeKey(key);
  }

  String _encodeVersion(List<int> version) {
    return base64.encode(version);
  }

  String _buildUrl(String path, {Map<String, String>? queryParams}) {
    final uri = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams).toString();
    }
    return uri.toString();
  }

  Uint8List _parseVersionHeader(String? header) {
    if (header == null) {
      throw FormatException('Missing x-blob-version header');
    }
    return Uint8List.fromList(base64.decode(header));
  }

  @override
  Future<Blob?> getBlob(List<int> key) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);
    final url = _buildUrl('/blobs/$encodedKey');

    final response = await _client.get(Uri.parse(url));

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 400) {
      throw ArgumentError(response.body);
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final version = _parseVersionHeader(response.headers['x-blob-version']);
    return Blob(
      bytes: Uint8List.fromList(response.bodyBytes),
      version: version,
    );
  }

  @override
  Future<BlobMetadata?> getBlobMetadata(List<int> key) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);
    final url = _buildUrl('/blobs/$encodedKey');

    final response = await _client.head(Uri.parse(url));

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 400) {
      throw ArgumentError(response.body);
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final sizeStr = response.headers['content-length'];
    if (sizeStr == null) {
      throw FormatException('Missing content-length header');
    }

    final size = int.parse(sizeStr);
    final version = _parseVersionHeader(response.headers['x-blob-version']);

    return BlobMetadata(size: size, version: version);
  }

  @override
  Future<bool> updateBlob(
    List<int> key,
    List<int> bytes, {
    List<int>? version,
    Duration? ttl,
  }) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);

    final queryParams = <String, String>{};
    if (version != null) {
      queryParams['version'] = _encodeVersion(version);
    }
    if (ttl != null) {
      queryParams['ttl'] = '${ttl.inSeconds}s';
    }

    final url = _buildUrl('/blobs/$encodedKey', queryParams: queryParams);

    final response = await _client.put(
      Uri.parse(url),
      body: Uint8List.fromList(bytes),
    );

    if (response.statusCode == 400) {
      throw ArgumentError(response.body);
    }

    if (response.statusCode == 409) {
      return false; // Version conflict
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    return true;
  }

  @override
  Future<bool> deleteBlob(List<int> key, {List<int>? version}) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);

    final queryParams = <String, String>{};
    if (version != null) {
      queryParams['version'] = _encodeVersion(version);
    }

    final url = _buildUrl('/blobs/$encodedKey', queryParams: queryParams);

    final response = await _client.delete(Uri.parse(url));

    if (response.statusCode == 400) {
      throw ArgumentError(response.body);
    }

    if (response.statusCode == 409) {
      return false; // Version conflict
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    return true;
  }

  /// Uploads a blob from a stream of bytes.
  ///
  /// This method allows streaming large files without loading them entirely
  /// into memory. The [dataStream] should yield chunks of bytes.
  ///
  /// Returns true if the blob was successfully updated, false if there was
  /// a version conflict.
  Future<bool> updateBlobStream(
    List<int> key,
    Stream<List<int>> dataStream, {
    List<int>? version,
  }) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);

    final queryParams = <String, String>{};
    if (version != null) {
      queryParams['version'] = _encodeVersion(version);
    }

    final url = _buildUrl('/blobs/$encodedKey', queryParams: queryParams);

    final request = http.StreamedRequest('PUT', Uri.parse(url));

    // Forward the stream to the request
    dataStream.listen(
      (chunk) => request.sink.add(chunk),
      onError: (error) => request.sink.addError(error),
      onDone: () => request.sink.close(),
    );

    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode == 400) {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw ArgumentError(responseBody);
    }

    if (streamedResponse.statusCode == 409) {
      return false; // Version conflict
    }

    if (streamedResponse.statusCode != 200) {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw Exception('HTTP ${streamedResponse.statusCode}: $responseBody');
    }

    return true;
  }

  /// Downloads a blob as a stream of bytes.
  ///
  /// This method allows streaming large files without loading them entirely
  /// into memory. Returns null if the blob doesn't exist.
  ///
  /// The returned stream will yield chunks of bytes. Make sure to handle
  /// any errors that may occur during streaming.
  Future<Stream<List<int>>?> getBlobStream(List<int> key) async {
    final keyBytes = Uint8List.fromList(key);
    final encodedKey = _encodeKey(keyBytes);
    final url = _buildUrl('/blobs/$encodedKey');

    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode == 404) {
      return null;
    }

    if (streamedResponse.statusCode == 400) {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw ArgumentError(responseBody);
    }

    if (streamedResponse.statusCode != 200) {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw Exception('HTTP ${streamedResponse.statusCode}: $responseBody');
    }

    // Return the stream directly
    return streamedResponse.stream;
  }

  /// Uploads a blob directly from a file.
  ///
  /// This method streams the file content without loading it entirely into
  /// memory, making it suitable for large files.
  ///
  /// Returns true if the blob was successfully updated, false if there was
  /// a version conflict.
  Future<bool> updateBlobFromFile(
    List<int> key,
    String filePath, {
    List<int>? version,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('File not found: $filePath');
    }

    final fileStream = file.openRead();
    return updateBlobStream(key, fileStream, version: version);
  }

  /// Downloads a blob and saves it directly to a file.
  ///
  /// This method streams the blob content without loading it entirely into
  /// memory, making it suitable for large files. Returns true if the blob
  /// was found and saved, false if the blob doesn't exist.
  ///
  /// Any missing parent directories will be created automatically.
  Future<bool> saveBlobToFile(List<int> key, String filePath) async {
    final stream = await getBlobStream(key);
    if (stream == null) {
      return false; // Blob doesn't exist
    }

    final file = File(filePath);

    // Always create parent directories if they don't exist
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final sink = file.openWrite();

    try {
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
      return true;
    } finally {
      await sink.close();
    }
  }

  @override
  Future<BlobStatistics> getStatistics() async {
    final url = _buildUrl('/status');
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    return BlobStatistics(
      totalBlobCount: jsonData['totalBlobCount'] as int,
      totalKeysSize: jsonData['totalKeysSize'] as int,
      totalValuesSize: jsonData['totalValuesSize'] as int,
    );
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}
