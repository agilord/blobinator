import 'dart:convert';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'api.dart';
import 'cli_utils.dart';

class BlobinatorHttpServer {
  final Blobinator _blobinator;

  BlobinatorHttpServer(this._blobinator);

  Handler get handler {
    final router = Router();

    router.get('/status', _handleStatus);
    router.head('/blobs/<key|.*>', _handleHead);
    router.get('/blobs/<key|.*>', _handleGet);
    router.put('/blobs/<key|.*>', _handlePut);
    router.delete('/blobs/<key|.*>', _handleDelete);

    return router.call;
  }

  List<int> _decodeKey(String encodedKey) {
    // URL decode first
    final urlDecoded = Uri.decodeComponent(encodedKey);

    if (urlDecoded.startsWith('base64:')) {
      // Remove 'base64:' prefix and decode as base64
      final base64Part = urlDecoded.substring(7);
      return base64.decode(base64Part);
    } else {
      // Decode as UTF-8
      return utf8.encode(urlDecoded);
    }
  }

  List<int>? _decodeVersion(String? versionParam) {
    if (versionParam == null) return null;
    return base64.decode(versionParam);
  }

  String _encodeVersionHeader(Uint8List version) {
    return base64.encode(version);
  }

  Duration? _parseTtlParam(String? ttlParam) {
    if (ttlParam == null) return null;
    try {
      return parseDuration(ttlParam);
    } on FormatException {
      rethrow; // Let caller handle the 400 response
    }
  }

  Future<Response> _handleStatus(Request request) async {
    try {
      final statistics = await _blobinator.getStatistics();
      return Response.ok(
        jsonEncode(statistics.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: 'Failed to get statistics');
    }
  }

  Future<Response> _handleHead(Request request) async {
    try {
      final key = _decodeKey(request.params['key']!);

      final metadata = await _blobinator.getBlobMetadata(key);
      if (metadata == null) {
        return Response.notFound('Blob not found');
      }

      return Response.ok(
        null,
        headers: {
          'content-length': metadata.size.toString(),
          'x-blob-version': _encodeVersionHeader(metadata.version),
        },
      );
    } on ArgumentError catch (e) {
      return Response(400, body: e.message);
    } on FormatException catch (e) {
      return Response(400, body: e.message);
    }
  }

  Future<Response> _handleGet(Request request) async {
    try {
      final key = _decodeKey(request.params['key']!);

      final blob = await _blobinator.getBlob(key);
      if (blob == null) {
        return Response.notFound('Blob not found');
      }

      final contentType =
          lookupMimeType('', headerBytes: blob.bytes) ??
          'application/octet-stream';

      return Response.ok(
        blob.bytes,
        headers: {
          'content-type': contentType,
          'content-length': blob.bytes.length.toString(),
          'x-blob-version': _encodeVersionHeader(blob.version),
        },
      );
    } on ArgumentError catch (e) {
      return Response(400, body: e.message);
    } on FormatException catch (e) {
      return Response(400, body: e.message);
    }
  }

  Future<Response> _handlePut(Request request) async {
    try {
      final key = _decodeKey(request.params['key']!);

      final bodyBytes = await request.read().toList();
      final bytes = bodyBytes.expand((chunk) => chunk).toList();

      final version = _decodeVersion(
        request.requestedUri.queryParameters['version'],
      );
      final ttl = _parseTtlParam(request.requestedUri.queryParameters['ttl']);

      final success = await _blobinator.updateBlob(
        key,
        bytes,
        version: version,
        ttl: ttl,
      );
      if (!success) {
        return Response(409, body: 'Version conflict');
      }

      return Response.ok('Blob updated');
    } on ArgumentError catch (e) {
      return Response(400, body: e.message);
    } on FormatException catch (e) {
      return Response(400, body: e.message);
    }
  }

  Future<Response> _handleDelete(Request request) async {
    try {
      final key = _decodeKey(request.params['key']!);

      final version = _decodeVersion(
        request.requestedUri.queryParameters['version'],
      );

      final success = await _blobinator.deleteBlob(key, version: version);
      if (!success) {
        return Response(409, body: 'Version conflict');
      }

      return Response.ok('Blob deleted');
    } on ArgumentError catch (e) {
      return Response(400, body: e.message);
    } on FormatException catch (e) {
      return Response(400, body: e.message);
    }
  }
}
