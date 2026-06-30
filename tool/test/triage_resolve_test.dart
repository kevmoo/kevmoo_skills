import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  final triageScript = p.join(
    p.basename(Directory.current.path) == 'tool' ? '..' : '.',
    'skills',
    'github-pr-triage',
    'bin',
    'triage.dart',
  );

  test(
    'triage.dart resolve with no args outputs usage and exits with code 1',
    () async {
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        triageScript,
        'resolve',
      ]);

      await expectLater(
        process.stderr,
        emitsThrough(
          contains('Error: Invalid arguments for resolve subcommand.'),
        ),
      );
      await process.shouldExit(1);
    },
  );

  test(
    'triage.dart resolve with 2 args outputs usage and exits with code 1',
    () async {
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        triageScript,
        'resolve',
        'thread_123',
        'comment_456',
      ]);

      await expectLater(
        process.stderr,
        emitsThrough(
          contains('Error: Invalid arguments for resolve subcommand.'),
        ),
      );
      await process.shouldExit(1);
    },
  );

  test(
    'triage.dart resolve with invalid target directory outputs error and exits with code 1',
    () async {
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        triageScript,
        'resolve',
        'thread_123',
        '--dir',
        '/non_existent_path_xyz',
      ]);

      await expectLater(
        process.stderr,
        emitsThrough(
          contains('Target directory "/non_existent_path_xyz" does not exist.'),
        ),
      );
      await process.shouldExit(1);
    },
  );

  test(
    'triage.dart resolve with non-numeric comment_id outputs error and exits with code 1',
    () async {
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        triageScript,
        'resolve',
        'thread_123',
        'not_a_number',
        'some reply',
      ]);

      await expectLater(
        process.stderr,
        emitsThrough(
          contains('Error: <comment_id> must be a numeric database ID.'),
        ),
      );
      await process.shouldExit(1);
    },
  );

  test(
    'triage.dart resolve with empty body_text outputs error and exits with code 1',
    () async {
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        triageScript,
        'resolve',
        'thread_123',
        '456',
        '   ',
      ]);

      await expectLater(
        process.stderr,
        emitsThrough(contains('Error: <body_text> cannot be empty.')),
      );
      await process.shouldExit(1);
    },
  );
}
