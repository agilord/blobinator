import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:blobinator/src/commands/serve_command.dart';

class BlobinatorCommandRunner extends CommandRunner<int> {
  BlobinatorCommandRunner()
    : super('blobinator', 'Temporary binary blob storage service') {
    addCommand(ServeCommand());
  }

  @override
  String get invocation => 'blobinator <command> [arguments]';

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final result = await super.run(args);
      return result ?? 0;
    } on UsageException catch (e) {
      print(e.message);
      print('');
      print(usage);
      return 64; // EX_USAGE from sysexits.h
    }
  }
}

Future<void> main(List<String> arguments) async {
  final runner = BlobinatorCommandRunner();
  final exitCode = await runner.run(arguments);
  exit(exitCode);
}
