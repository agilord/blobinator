import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

import 'cli_utils.dart';
import 'http_client.dart';

class ClientCommand extends Command<void> {
  @override
  String get name => 'client';

  @override
  String get description => 'HTTP client for blob operations';

  ClientCommand() {
    argParser.addOption('url', help: 'Base URL of the blobinator server');

    addSubcommand(_GetMetadataCommand());
    addSubcommand(_GetCommand());
    addSubcommand(_UpdateCommand());
    addSubcommand(_DeleteCommand());
    addSubcommand(_StatusCommand());
  }

  @override
  Future<void> run() async {
    // This should not be called directly, subcommands handle execution
    throw UsageException('Please specify a subcommand', usage);
  }

  String _getBaseUrl() {
    final urlArg = argResults?['url'] as String?;
    final envUrl = Platform.environment['BLOBINATOR_URL'];

    // --url takes precedence over environment
    final baseUrl = urlArg ?? envUrl;

    if (baseUrl == null) {
      throw UsageException(
        'Base URL must be provided via --url or BLOBINATOR_URL environment variable',
        usage,
      );
    }

    return baseUrl;
  }
}

class _GetMetadataCommand extends Command<void> {
  @override
  String get name => 'get-metadata';

  @override
  String get description => 'Get blob metadata';

  _GetMetadataCommand() {
    argParser.addOption(
      'key',
      help: 'Blob key (supports utf8 or base64: prefix)',
      mandatory: true,
    );
  }

  @override
  Future<void> run() async {
    try {
      final clientCommand = parent as ClientCommand;
      final baseUrl = clientCommand._getBaseUrl();
      final client = HttpBlobinator(baseUrl);

      final keyParam = argResults!['key'] as String;
      final key = parseKeyParameter(keyParam);

      final metadata = await client.getBlobMetadata(key);
      await client.close();

      if (metadata == null) {
        stderr.writeln(jsonEncode({'error': 'Blob not found'}));
        exit(1);
      }

      final output = {
        'size': metadata.size,
        'version': base64.encode(metadata.version),
      };

      print(jsonEncode(output));
    } on FormatException catch (e) {
      stderr.writeln(jsonEncode({'error': 'Invalid key format: ${e.message}'}));
      exit(1);
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }
  }
}

class _GetCommand extends Command<void> {
  @override
  String get name => 'get';

  @override
  String get description => 'Get blob data';

  _GetCommand() {
    argParser.addOption(
      'key',
      help: 'Blob key (supports utf8 or base64: prefix)',
      mandatory: true,
    );
    argParser.addOption(
      'output',
      help: 'Output file (- for stdout)',
      defaultsTo: '-',
    );
  }

  @override
  Future<void> run() async {
    try {
      final clientCommand = parent as ClientCommand;
      final baseUrl = clientCommand._getBaseUrl();
      final client = HttpBlobinator(baseUrl);

      final keyParam = argResults!['key'] as String;
      final outputPath = argResults!['output'] as String;
      final key = parseKeyParameter(keyParam);

      final blob = await client.getBlob(key);
      await client.close();

      if (blob == null) {
        stderr.writeln(jsonEncode({'error': 'Blob not found'}));
        exit(1);
      }

      if (outputPath == '-') {
        // Write to stdout
        stdout.add(blob.bytes);
      } else {
        // Write to file
        final file = File(outputPath);
        await file.writeAsBytes(blob.bytes);
      }
    } on FormatException catch (e) {
      stderr.writeln(jsonEncode({'error': 'Invalid key format: ${e.message}'}));
      exit(1);
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }
  }
}

class _UpdateCommand extends Command<void> {
  @override
  String get name => 'update';

  @override
  String get description => 'Update blob data';

  _UpdateCommand() {
    argParser.addOption(
      'key',
      help: 'Blob key (supports utf8 or base64: prefix)',
      mandatory: true,
    );
    argParser.addOption(
      'input',
      help: 'Input file (- for stdin)',
      defaultsTo: '-',
    );
    argParser.addOption(
      'version',
      help: 'Expected blob version (base64 encoded)',
    );
    argParser.addOption(
      'ttl',
      help: 'Time-to-live duration (supports s, m, h, d suffixes)',
    );
  }

  @override
  Future<void> run() async {
    try {
      final clientCommand = parent as ClientCommand;
      final baseUrl = clientCommand._getBaseUrl();
      final client = HttpBlobinator(baseUrl);

      final keyParam = argResults!['key'] as String;
      final inputPath = argResults!['input'] as String;
      final versionParam = argResults!['version'] as String?;
      final ttlParam = argResults!['ttl'] as String?;

      final key = parseKeyParameter(keyParam);

      // Read input data
      final Uint8List data;
      if (inputPath == '-') {
        // Read from stdin
        final bytes = <int>[];
        await for (final chunk in stdin) {
          bytes.addAll(chunk);
        }
        data = Uint8List.fromList(bytes);
      } else {
        // Read from file
        final file = File(inputPath);
        data = await file.readAsBytes();
      }

      // Parse optional parameters
      List<int>? version;
      if (versionParam != null) {
        version = base64.decode(versionParam);
      }

      Duration? ttl;
      if (ttlParam != null) {
        ttl = parseDuration(ttlParam);
      }

      final success = await client.updateBlob(
        key,
        data,
        version: version,
        ttl: ttl,
      );
      await client.close();

      if (!success) {
        stderr.writeln(
          jsonEncode({'error': 'Update failed (version conflict)'}),
        );
        exit(1);
      }

      print(jsonEncode({'success': true}));
    } on FormatException catch (e) {
      stderr.writeln(jsonEncode({'error': 'Invalid format: ${e.message}'}));
      exit(1);
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }
  }
}

class _DeleteCommand extends Command<void> {
  @override
  String get name => 'delete';

  @override
  String get description => 'Delete blob';

  _DeleteCommand() {
    argParser.addOption(
      'key',
      help: 'Blob key (supports utf8 or base64: prefix)',
      mandatory: true,
    );
    argParser.addOption(
      'version',
      help: 'Expected blob version (base64 encoded)',
    );
  }

  @override
  Future<void> run() async {
    try {
      final clientCommand = parent as ClientCommand;
      final baseUrl = clientCommand._getBaseUrl();
      final client = HttpBlobinator(baseUrl);

      final keyParam = argResults!['key'] as String;
      final versionParam = argResults!['version'] as String?;

      final key = parseKeyParameter(keyParam);

      List<int>? version;
      if (versionParam != null) {
        version = base64.decode(versionParam);
      }

      final success = await client.deleteBlob(key, version: version);
      await client.close();

      if (!success) {
        stderr.writeln(
          jsonEncode({
            'error': 'Delete failed (version conflict or not found)',
          }),
        );
        exit(1);
      }

      print(jsonEncode({'success': true}));
    } on FormatException catch (e) {
      stderr.writeln(jsonEncode({'error': 'Invalid format: ${e.message}'}));
      exit(1);
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }
  }
}

class _StatusCommand extends Command<void> {
  @override
  String get name => 'status';

  @override
  String get description => 'Get server status and statistics';

  @override
  Future<void> run() async {
    try {
      final clientCommand = parent as ClientCommand;
      final baseUrl = clientCommand._getBaseUrl();
      final client = HttpBlobinator(baseUrl);

      final statistics = await client.getStatistics();
      await client.close();

      final output = {
        'totalBlobCount': statistics.totalBlobCount,
        'totalKeysSize': statistics.totalKeysSize,
        'totalValuesSize': statistics.totalValuesSize,
      };

      print(jsonEncode(output));
    } catch (e) {
      stderr.writeln(jsonEncode({'error': e.toString()}));
      exit(1);
    }
  }
}
