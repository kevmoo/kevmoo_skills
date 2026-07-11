import 'dart:io';
import 'package:test/test.dart';

import '../bin/readme.dart';

void main() {
  test('validate README.md is up-to-date with the latest skills', () async {
    final scriptPath = Directory.current.path.endsWith('tool')
        ? 'bin/readme.dart'
        : 'tool/bin/readme.dart';
    final result = await Process.run(Platform.resolvedExecutable, [
      scriptPath,
      '--validate',
    ]);
    expect(
      result.exitCode,
      0,
      reason:
          'README.md is out of date. Run dart tool/bin/readme.dart --write to update it.\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
    );
  });

  group('getRepoSlugFromUrl', () {
    test('strips trailing slashes and .git suffix from HTTPS URLs', () {
      expect(
        getRepoSlugFromUrl('https://github.com/owner/repo.git/'),
        equals('owner/repo'),
      );
      expect(
        getRepoSlugFromUrl('https://github.com/owner/repo/'),
        equals('owner/repo'),
      );
    });

    test('strips trailing slashes and .git suffix from SSH URLs', () {
      expect(
        getRepoSlugFromUrl('git@github.com:owner/repo.git/'),
        equals('owner/repo'),
      );
      expect(
        getRepoSlugFromUrl('git@github.com:owner/repo'),
        equals('owner/repo'),
      );
    });
  });
}
