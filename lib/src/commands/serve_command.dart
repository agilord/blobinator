import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shelf/shelf_io.dart' as io;

import '../config.dart';
import '../scheduler.dart';
import '../server.dart';
import '../storage.dart';

class ServeCommand extends Command<int> {
  @override
  String get name => 'serve';

  @override
  String get description => 'Start the blobinator HTTP server';

  ServeCommand() {
    argParser
      ..addOption(
        'port',
        abbr: 'p',
        help: 'HTTP server port',
        defaultsTo: '8080',
      )
      ..addOption(
        'mem-items',
        help:
            'Maximum items in memory (e.g., 1000000, 1m, 1000k or plain number)',
        defaultsTo: '1000000',
      )
      ..addOption(
        'disk-items',
        help:
            'Maximum items on disk (e.g., 100000000, 100m, 100000k or plain number)',
        defaultsTo: '100000000',
      )
      ..addOption(
        'mem-size',
        help:
            'Maximum memory usage (e.g., 1024MiB, 1GiB, 1024MB, 1GB or plain number for MiB)',
        defaultsTo: '1024',
      )
      ..addOption(
        'disk-size',
        help:
            'Maximum disk usage (e.g., 524288MiB, 512GiB, 524288MB, 512GB or plain number for MiB)',
        defaultsTo: '524288',
      )
      ..addOption(
        'mem-ttl',
        help:
            'Memory TTL (e.g., 3d, 72h, 4320m, 259200s or plain number for days)',
        defaultsTo: '3',
      )
      ..addOption(
        'disk-ttl',
        help:
            'Disk TTL (e.g., 90d, 2160h, 129600m, 7776000s or plain number for days)',
        defaultsTo: '90',
      )
      ..addOption(
        'disk-storage-path',
        help: 'Path for disk storage (optional)',
      );
  }

  @override
  Future<int> run() async {
    final config = BlobinatorConfig(
      port: int.parse(argResults!['port'] as String),
      maxMemoryItems: _parseCount(argResults!['mem-items'] as String),
      maxDiskItems: _parseCount(argResults!['disk-items'] as String),
      maxMemoryBytes: _parseSize(argResults!['mem-size'] as String),
      maxDiskBytes: _parseSize(argResults!['disk-size'] as String),
      memoryTtl: _parseTtl(argResults!['mem-ttl'] as String),
      diskTtl: _parseTtl(argResults!['disk-ttl'] as String),
      diskStoragePath: argResults!['disk-storage-path'] as String?,
    );

    final storage = BlobStorage(config);
    final server = BlobinatorServer(config, storage);
    final scheduler = EvictionScheduler(storage);

    scheduler.start();

    final handler = server.handler;
    final httpServer = await io.serve(
      handler,
      InternetAddress.anyIPv4,
      config.port,
    );

    print(
      'Blobinator server started on http://${httpServer.address.host}:${httpServer.port}',
    );

    if (config.diskStoragePath != null) {
      print('Disk storage: ${config.diskStoragePath}');
    } else {
      print('Memory-only mode (no disk storage)');
    }

    print('Configuration:');
    print(
      '  Memory: ${config.maxMemoryItems} items, ${_formatBytes(config.maxMemoryBytes)}, TTL ${config.memoryTtl.inDays} days',
    );
    if (config.diskStoragePath != null) {
      print(
        '  Disk: ${config.maxDiskItems} items, ${_formatBytes(config.maxDiskBytes)}, TTL ${config.diskTtl.inDays} days',
      );
    }

    ProcessSignal.sigint.watch().listen((_) async {
      print('\nShutting down...');
      scheduler.stop();
      await httpServer.close();
      exit(0);
    });

    return 0;
  }

  int _parseCount(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('Count value cannot be empty');
    }

    // Check for unit suffix (case insensitive)
    final lowerValue = trimmed.toLowerCase();

    if (lowerValue.endsWith('b')) {
      final numPart = trimmed.substring(0, trimmed.length - 1);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid count number: $numPart');
      }

      return number * 1000000000; // billions
    } else if (lowerValue.endsWith('m')) {
      final numPart = trimmed.substring(0, trimmed.length - 1);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid count number: $numPart');
      }

      return number * 1000000; // millions
    } else if (lowerValue.endsWith('k')) {
      final numPart = trimmed.substring(0, trimmed.length - 1);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid count number: $numPart');
      }

      return number * 1000; // thousands
    } else {
      // Plain number, use as-is
      final number = int.tryParse(trimmed);
      if (number == null || number < 0) {
        throw ArgumentError('Invalid count value: $trimmed');
      }
      return number;
    }
  }

  int _parseSize(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('Size value cannot be empty');
    }

    // Check for unit suffix (case insensitive)
    final lowerValue = trimmed.toLowerCase();

    if (lowerValue.endsWith('gib') || lowerValue.endsWith('gb')) {
      final suffix = lowerValue.endsWith('gib') ? 'gib' : 'gb';
      final numPart = trimmed.substring(0, trimmed.length - suffix.length);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid size number: $numPart');
      }

      if (suffix == 'gib') {
        return number * 1024 * 1024 * 1024; // GiB to bytes
      } else {
        return number * 1000 * 1000 * 1000; // GB to bytes
      }
    } else if (lowerValue.endsWith('mib') || lowerValue.endsWith('mb')) {
      final suffix = lowerValue.endsWith('mib') ? 'mib' : 'mb';
      final numPart = trimmed.substring(0, trimmed.length - suffix.length);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid size number: $numPart');
      }

      if (suffix == 'mib') {
        return number * 1024 * 1024; // MiB to bytes
      } else {
        return number * 1000 * 1000; // MB to bytes
      }
    } else if (lowerValue.endsWith('kib') || lowerValue.endsWith('kb')) {
      final suffix = lowerValue.endsWith('kib') ? 'kib' : 'kb';
      final numPart = trimmed.substring(0, trimmed.length - suffix.length);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid size number: $numPart');
      }

      if (suffix == 'kib') {
        return number * 1024; // KiB to bytes
      } else {
        return number * 1000; // KB to bytes
      }
    } else {
      // Plain number, treat as MiB
      final number = int.tryParse(trimmed);
      if (number == null || number < 0) {
        throw ArgumentError('Invalid size value: $trimmed');
      }
      return number * 1024 * 1024; // MiB to bytes
    }
  }

  Duration _parseTtl(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('TTL value cannot be empty');
    }

    // Check if it ends with a unit suffix
    final lastChar = trimmed[trimmed.length - 1].toLowerCase();

    if (RegExp(r'[dhms]').hasMatch(lastChar)) {
      final numPart = trimmed.substring(0, trimmed.length - 1);
      final number = int.tryParse(numPart);

      if (number == null || number < 0) {
        throw ArgumentError('Invalid TTL number: $numPart');
      }

      switch (lastChar) {
        case 'd':
          return Duration(days: number);
        case 'h':
          return Duration(hours: number);
        case 'm':
          return Duration(minutes: number);
        case 's':
          return Duration(seconds: number);
        default:
          throw ArgumentError('Invalid TTL unit: $lastChar');
      }
    } else {
      // Plain number, treat as days
      final number = int.tryParse(trimmed);
      if (number == null || number < 0) {
        throw ArgumentError('Invalid TTL value: $trimmed');
      }
      return Duration(days: number);
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(size == size.truncate() ? 0 : 1)} ${units[unitIndex]}';
  }
}
