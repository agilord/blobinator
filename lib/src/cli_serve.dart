import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shelf/shelf_io.dart';

import 'cli_utils.dart';
import 'config.dart';
import 'http_server.dart';
import 'hybrid_blobinator.dart';
import 'sqlite_blobinator.dart';

class ServeCommand extends Command<void> {
  @override
  String get name => 'serve';

  @override
  String get description => 'Start the HTTP server with blob storage';

  ServeCommand() {
    argParser
      ..addOption('host', help: 'Host to bind to', defaultsTo: '0.0.0.0')
      ..addOption(
        'port',
        abbr: 'p',
        help: 'Port to bind to',
        defaultsTo: '8080',
      )
      ..addOption(
        'key-max-length',
        help:
            'Maximum key length (supports suffixes: k/kb/kib, m/mb/mib, g/gb/gib)',
      )
      ..addOption(
        'value-max-length',
        help:
            'Maximum value length (supports suffixes: k/kb/kib, m/mb/mib, g/gb/gib)',
      )
      ..addOption(
        'default-ttl',
        help: 'Default time-to-live for blobs (supports suffixes: s, m, h, d)',
      )
      ..addOption(
        'path',
        help:
            'Path to SQLite database file (uses in-memory storage if not provided)',
      )
      ..addFlag(
        'hybrid',
        help: 'Use hybrid storage (memory cache + disk persistence)',
      );
  }

  @override
  Future<void> run() async {
    final host = argResults!['host'] as String;
    final portStr = argResults!['port'] as String;
    final port = int.tryParse(portStr);

    if (port == null || port < 1 || port > 65535) {
      throw UsageException('Invalid port: $portStr', usage);
    }

    // Parse optional configuration values
    int? maxKeyLength;
    int? maxValueLength;
    Duration? defaultTtl;

    final maxKeyLengthStr = argResults!['key-max-length'] as String?;
    if (maxKeyLengthStr != null) {
      try {
        maxKeyLength = parseBytesAmount(maxKeyLengthStr);
      } on FormatException catch (e) {
        throw UsageException('Invalid key-max-length: ${e.message}', usage);
      }
    }

    final maxValueLengthStr = argResults!['value-max-length'] as String?;
    if (maxValueLengthStr != null) {
      try {
        maxValueLength = parseBytesAmount(maxValueLengthStr);
      } on FormatException catch (e) {
        throw UsageException('Invalid value-max-length: ${e.message}', usage);
      }
    }

    final defaultTtlStr = argResults!['default-ttl'] as String?;
    if (defaultTtlStr != null) {
      try {
        defaultTtl = parseDuration(defaultTtlStr);
      } on FormatException catch (e) {
        throw UsageException('Invalid default-ttl: ${e.message}', usage);
      }
    }

    final config = BlobinatorConfig(
      keyMaxLength: maxKeyLength,
      valueMaxLength: maxValueLength,
      defaultTtl: defaultTtl,
    );

    final pathStr = argResults!['path'] as String?;
    final useHybrid = argResults!['hybrid'] as bool;

    final blobinator = useHybrid
        ? HybridBlobinator(
            config: HybridBlobinatorConfig(
              keyMaxLength: maxKeyLength,
              valueMaxLength: maxValueLength,
              defaultTtl: defaultTtl,
              diskPath: pathStr,
            ),
          )
        : (pathStr != null
              ? SqliteBlobinator.inFile(pathStr, config: config)
              : SqliteBlobinator.inMemory(config: config));
    final server = BlobinatorHttpServer(blobinator);

    final httpServer = await serve(server.handler, host, port);

    print('Server running on http://$host:$port');

    await ProcessSignal.sigint.watch().first;

    // Clean up resources
    await blobinator.close();

    await httpServer.close();
  }
}
