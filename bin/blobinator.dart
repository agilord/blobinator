#!/usr/bin/env dart

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:blobinator/src/cli_client.dart';
import 'package:blobinator/src/cli_serve.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<void>(
    'blobinator',
    'Tools and HTTP service for temporary binary blob storage.',
  );

  runner.addCommand(ServeCommand());
  runner.addCommand(ClientCommand());

  try {
    await runner.run(arguments);
  } on UsageException catch (e) {
    print(e.message);
    print('');
    print(e.usage);
    exit(64);
  }
}
