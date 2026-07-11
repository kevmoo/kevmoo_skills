import 'dart:io';
import 'package:test/test.dart';
import '../bin/readme.dart' as readme;

void main() {
  group('parseRepoSlugFromUrl unit tests', () {
    test('extracts slug from https URL with .git suffix', () {
      expect(
        readme.parseRepoSlugFromUrl(
          'https://github.com/kevmoo/angular.dart.git',
        ),
        equals('kevmoo/angular.dart'),
      );
    });

    test(
      'extracts slug from SSH URL with .git suffix and dots in repo name',
      () {
        expect(
          readme.parseRepoSlugFromUrl(
            'git@github.com:kevmoo/built_value.dart.git',
          ),
          equals('kevmoo/built_value.dart'),
        );
      },
    );

    test('extracts slug when no .git suffix exists', () {
      expect(
        readme.parseRepoSlugFromUrl('https://github.com/owner/repo'),
        equals('owner/repo'),
      );
    });

    test('extracts slug from URL with trailing slash', () {
      expect(
        readme.parseRepoSlugFromUrl('https://github.com/owner/repo/'),
        equals('owner/repo'),
      );
    });

    test('extracts slug from full pull request subpath URL', () {
      expect(
        readme.parseRepoSlugFromUrl('https://github.com/owner/repo/pull/39'),
        equals('owner/repo'),
      );
    });

    test('extracts slug from ssh:// URL with .git suffix', () {
      expect(
        readme.parseRepoSlugFromUrl('ssh://git@github.com/owner/repo.git'),
        equals('owner/repo'),
      );
    });

    test('extracts slug from HTTPS URL with explicit port number', () {
      expect(
        readme.parseRepoSlugFromUrl('https://github.com:443/owner/repo.git'),
        equals('owner/repo'),
      );
    });

    test('returns null for non-github URLs', () {
      expect(
        readme.parseRepoSlugFromUrl('https://gitlab.com/owner/repo.git'),
        isNull,
      );
    });
  });

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
}
