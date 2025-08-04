import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'storage.dart';

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
      ..get('/status', _handleStatus);
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

    final headers = <String, String>{'content-length': size.toString()};

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
      final bodyBytes = await request.read().fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );

      final data = Uint8List.fromList(bodyBytes);
      await storage.put(blobId, data);

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
}
