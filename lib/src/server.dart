import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'storage.dart';
import 'utils.dart';

class BlobinatorServer {
  final BlobinatorConfig config;
  final BlobStorage storage;
  late final Router _router;

  BlobinatorServer(this.config, this.storage) {
    _router = Router()
      ..head('/blobs/<blobId>', _handleHead)
      ..get('/blobs/<blobId>', _handleGet)
      ..put('/blobs/<blobId>', _handlePut)
      ..delete('/blobs/<blobId>', _handleDelete)
      ..get('/status', _handleStatus)
      ..post('/flush', _handleFlush);
  }

  Handler get handler => _router.call;

  Future<Response> _handleHead(Request request) async {
    final blobId = request.params['blobId']!;

    final exists = await storage.exists(blobId);
    if (!exists) {
      return Response.notFound('');
    }

    final size = await storage.getSize(blobId);
    final lastModified = await storage.getLastModified(blobId);

    final headers = <String, String>{'content-length': (size ?? 0).toString()};

    if (lastModified != null) {
      headers['last-modified'] = HttpDate.format(lastModified);
    }

    return Response.ok('', headers: headers);
  }

  Future<Response> _handleGet(Request request) async {
    final blobId = request.params['blobId']!;

    final blobData = await storage.get(blobId);
    if (blobData == null) {
      return Response.notFound('Blob not found');
    }

    final headers = <String, String>{
      'content-length': blobData.sizeInBytes.toString(),
      'last-modified': HttpDate.format(blobData.lastModified),
    };

    return Response.ok(blobData.data, headers: headers);
  }

  Future<Response> _handlePut(Request request) async {
    final blobId = request.params['blobId']!;

    try {
      final params = request.url.queryParameters;
      bool flush = false;

      if (params.containsKey('flush')) {
        flush = parseFlush(params['flush']!);
      }

      final bodyBytes = await request.read().fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );

      final data = Uint8List.fromList(bodyBytes);
      await storage.put(blobId, data, flush: flush);

      return Response.ok('');
    } catch (e) {
      if (e is ArgumentError) {
        return Response.badRequest(body: e.message);
      }
      return Response.internalServerError(body: 'Failed to store blob');
    }
  }

  Future<Response> _handleDelete(Request request) async {
    final blobId = request.params['blobId']!;

    final deleted = await storage.delete(blobId);
    if (deleted) {
      return Response.ok('');
    } else {
      return Response.notFound('Blob not found');
    }
  }

  Future<Response> _handleStatus(Request request) async {
    final status = storage.getStatus();
    final json = jsonEncode(status.toJson());

    return Response.ok(json, headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleFlush(Request request) async {
    try {
      final params = request.url.queryParameters;
      int? limit;
      Duration? age;

      if (params.containsKey('limit')) {
        limit = parseLimit(params['limit']!);
      }

      if (params.containsKey('age')) {
        age = parseAge(params['age']!);
      }

      final flushed = await storage.flush(limit: limit, age: age);
      final result = {'flushed': flushed};
      final json = jsonEncode(result);

      return Response.ok(json, headers: {'content-type': 'application/json'});
    } catch (e) {
      if (e is ArgumentError) {
        return Response.badRequest(body: e.message);
      }
      if (e is StateError) {
        return Response(409, body: e.message);
      }
      return Response.internalServerError(body: 'Failed to flush blobs');
    }
  }
}
