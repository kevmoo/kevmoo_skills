#!/usr/bin/env dart

import 'dart:io';

import 'package:sidequest/sidequest.dart';

Future<void> main(List<String> rawArgs) async {
  final runner = SidequestCliRunner();
  final exitCode = await runner.run(rawArgs);
  exit(exitCode);
}
