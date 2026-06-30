import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  final triageScript = p.join(
    Directory.current.path.endsWith('tool') ? '..' : '.',
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
}
