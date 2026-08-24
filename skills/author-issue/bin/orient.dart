import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../lib/orient.dart';

Future<void> main(List<String> args) async {
  final parser = buildArgParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error parsing arguments: $e');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln(
      'Orient with repository conventions for issues and pull requests.\n',
    );
    stdout.writeln('Usage: dart run orient.dart [options]\n');
    stdout.writeln(parser.usage);
    return;
  }

  final workingDir = results.option('dir');
  final repo = results.option('repo');
  final limitStr = results.option('limit') ?? '20';
  final limit = int.tryParse(limitStr) ?? 20;
  final asJson = results.flag('json');

  final gatherer = OrientationGatherer();
  try {
    final orientation = await gatherer.gather(
      workingDirectory: workingDir,
      repo: repo,
      sampleLimit: limit,
    );

    if (asJson) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(orientation.toJson()),
      );
    } else {
      stdout.writeln(orientation.toMarkdown());
    }
  } catch (e, st) {
    stderr.writeln('Failed to gather orientation: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
