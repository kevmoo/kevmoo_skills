import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('validate README.md is up-to-date with the latest skills', () {
    final scriptPath = Directory.current.path.endsWith('tool')
        ? 'bin/readme.dart'
        : 'tool/bin/readme.dart';
    final result = Process.runSync(Platform.resolvedExecutable, [
      scriptPath,
      '--validate',
    ]);
    expect(
      result.exitCode,
      0,
      reason:
          'README.md is out of date.\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
    );
  });
}
