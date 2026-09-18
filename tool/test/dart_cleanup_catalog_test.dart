import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/generate_cleanup_catalog.dart';

void main() {
  group('dart_cleanup_catalog data integrity', () {
    late Map<String, dynamic> catalogData;
    late Map<String, dynamic> repositories;
    late List<dynamic> categories;

    setUpAll(() {
      final catalogPath =
          Directory.current.path.split(Platform.pathSeparator).last == 'tool'
          ? 'data/dart_cleanup_catalog.json'
          : 'tool/data/dart_cleanup_catalog.json';
      final file = File(catalogPath);
      expect(file.existsSync(), isTrue, reason: 'Catalog JSON must exist');
      catalogData = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      repositories = catalogData['repositories'] as Map<String, dynamic>;
      categories = catalogData['categories'] as List<dynamic>;
    });

    test('repositories have valid paths, cloneUrls, and pinned commits', () {
      expect(repositories, isNotEmpty);
      final shaRegex = RegExp(r'^[0-9a-f]{40}$');
      for (final entry in repositories.entries) {
        _verifyRepositoryEntry(
          entry.key,
          entry.value as Map<String, dynamic>,
          shaRegex,
        );
      }
    });

    test('categories are not empty and have distinct names', () {
      expect(categories, isNotEmpty);
      final names = <String>{};
      for (final cat in categories) {
        final name = (cat as Map<String, dynamic>)['name'] as String;
        expect(name, isNotEmpty);
        expect(names.add(name), isTrue, reason: 'Duplicate category: $name');
      }
    });

    test('skills in each category are sorted alphabetically', () {
      _verifyCategoriesSorted(categories);
    });

    test('skills have no duplicates across entire catalog', () {
      _verifyNoDuplicateSkills(categories);
    });

    test('skills define valid repositories', () {
      _verifySkillRepositories(categories, repositories);
    });
  });

  test(
    'validate skills/dart-cleanup/SKILL.md is up-to-date with catalog JSON',
    () async {
      final scriptPath =
          Directory.current.path.split(Platform.pathSeparator).last == 'tool'
          ? 'bin/generate_cleanup_catalog.dart'
          : 'tool/bin/generate_cleanup_catalog.dart';
      final result = await Process.run(Platform.resolvedExecutable, [
        scriptPath,
        '--validate',
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            'dart-cleanup/SKILL.md is out of date. Run dart tool/bin/generate_cleanup_catalog.dart --write to update it.\n'
            'stdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
    },
  );

  group('EnvIssue and EnvIssueType', () {
    test('issue types declare correct fatal statuses', () {
      expect(EnvIssueType.missingRepo.isFatal, isFalse);
      expect(EnvIssueType.notGitRepo.isFatal, isTrue);
      expect(EnvIssueType.mismatchedRemote.isFatal, isTrue);
      expect(EnvIssueType.uncatalogedSkill.isFatal, isTrue);
      expect(EnvIssueType.missingSkill.isFatal, isTrue);
    });

    test('EnvIssue formats readable output with tag and fix', () {
      const issue = EnvIssue(
        EnvIssueType.uncatalogedSkill,
        'Found foo in bar',
        fix: 'Add foo to catalog',
      );
      expect(issue.isFatal, isTrue);
      final rendered = issue.toString();
      expect(rendered, contains('⚠️ [UNCATALOGED SKILL] Found foo in bar'));
      expect(rendered, contains('Fix: Add foo to catalog'));
    });
  });
}

void _verifyRepositoryEntry(
  String key,
  Map<String, dynamic> config,
  RegExp shaRegex,
) {
  final rawPath = config['path'] as String?;
  expect(rawPath, isNotNull, reason: 'Repo $key must have path');
  expect(rawPath, startsWith('~/github/'));

  final cloneUrl = config['cloneUrl'] as String?;
  expect(cloneUrl, isNotNull);
  expect(cloneUrl, startsWith('https://github.com/'));
  expect(cloneUrl, endsWith('.git'));

  final commitSha = config['commitSha'] as String?;
  if (commitSha != null) {
    expect(
      shaRegex.hasMatch(commitSha),
      isTrue,
      reason: 'Commit SHA for $key must be 40-char hex string: $commitSha',
    );
  }

  final commitDate = config['commitDate'] as String?;
  if (commitDate != null) {
    expect(
      DateTime.tryParse(commitDate),
      isNotNull,
      reason: 'Commit date for $key must be valid ISO-8601: $commitDate',
    );
  }
}

void _verifyCategoriesSorted(List<dynamic> categories) {
  for (final cat in categories) {
    final catMap = cat as Map<String, dynamic>;
    final catName = catMap['name'] as String;
    final skills = catMap['skills'] as List<dynamic>;
    final skillNames = skills
        .map((s) => (s as Map<String, dynamic>)['name'] as String)
        .toList();
    final sortedNames = List<String>.from(skillNames)..sort();
    expect(
      skillNames,
      equals(sortedNames),
      reason: 'Skills in category "$catName" must be sorted alphabetically',
    );
  }
}

void _verifyNoDuplicateSkills(List<dynamic> categories) {
  final seen = <String>{};
  for (final cat in categories) {
    final catMap = cat as Map<String, dynamic>;
    final skills = catMap['skills'] as List<dynamic>;
    for (final s in skills) {
      final name = (s as Map<String, dynamic>)['name'] as String;
      expect(
        seen.add(name),
        isTrue,
        reason: 'Duplicate skill "$name" found in catalog',
      );
    }
  }
}

void _verifySkillRepositories(
  List<dynamic> categories,
  Map<String, dynamic> repositories,
) {
  for (final cat in categories) {
    final catMap = cat as Map<String, dynamic>;
    final skills = catMap['skills'] as List<dynamic>;
    for (final s in skills) {
      final skill = s as Map<String, dynamic>;
      final repo = skill['repo'] as String;
      expect(
        repositories.containsKey(repo),
        isTrue,
        reason: 'Unknown repo "$repo" for skill "${skill['name']}"',
      );
    }
  }
}
