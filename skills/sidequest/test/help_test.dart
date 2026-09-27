import 'dart:async';
import 'package:test/test.dart';
import '../lib/src/cli/command_runner.dart';
import 'package:args/command_runner.dart';

void main() {
  group('Help commands', () {
    late SidequestCliRunner runner;

    setUp(() {
      runner = SidequestCliRunner();
    });

    test('sidequest --help prints usage', () async {
      await expectLater(
        () => runner.run(['--help']),
        prints(contains('Deterministic session map manager')),
      );
    });

    test('sidequest help prints usage', () async {
      await expectLater(
        () => runner.run(['help']),
        prints(contains('Deterministic session map manager')),
      );
    });

    test('sidequest help <cmd> prints command usage', () async {
      await expectLater(
        () => runner.run(['help', 'quest']),
        prints(contains('Manage main quests')),
      );
    });

    test('sidequest <cmd> --help prints command usage', () async {
      await expectLater(
        () => runner.run(['quest', '--help']),
        prints(contains('Manage main quests')),
      );
    });

    test('sidequest help <cmd> <sub> prints subcommand usage', () async {
      await expectLater(
        () => runner.run(['help', 'quest', 'add']),
        prints(contains('Add a new main quest')),
      );
    });

    test('sidequest <cmd> <sub> --help prints subcommand usage', () async {
      await expectLater(
        () => runner.run(['quest', 'add', '--help']),
        prints(contains('Add a new main quest')),
      );
    });

    test('sidequest help batch prints operation types', () async {
      await expectLater(
        () => runner.run(['help', 'batch']),
        allOf(
          prints(contains('Supported operation types in JSON array:')),
          prints(contains('sidequest_add')),
          prints(contains('subquest_add')),
          prints(contains('quest_add')),
        ),
      );
    });
  });
}
