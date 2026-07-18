#!/usr/bin/env dart

import 'dart:io';

import 'package:sidequest/sidequest.dart';

Future<void> main(List<String> rawArgs) async {
  String? dir;
  final cleanArgs = <String>[];

  for (var i = 0; i < rawArgs.length; i++) {
    final arg = rawArgs[i];
    if (arg.startsWith('--dir=')) {
      dir = arg.substring('--dir='.length);
    } else if (arg == '--dir' && i + 1 < rawArgs.length) {
      dir = rawArgs[++i];
    } else {
      cleanArgs.add(arg);
    }
  }

  final store = SessionStore(directory: dir);
  final runner = SidequestCliRunner(store: store);
  final exitCode = await runner.run(cleanArgs);
  exit(exitCode);
}
