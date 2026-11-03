import 'dart:convert';
import 'dart:io';

import 'package:_kevmoo_skills_tool/upskill_checks.dart';
import 'package:logging/logging.dart';
import 'package:skills_lint/skills_lint.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

final String _configFilePath =
    Directory.current.path.split(Platform.pathSeparator).last == 'tool'
    ? 'skills_lint.yaml'
    : 'tool/skills_lint.yaml';

final String _skillsDirPath =
    Directory.current.path.split(Platform.pathSeparator).last == 'tool'
    ? '../skills'
    : 'skills';

final String _skillsShJsonPath =
    Directory.current.path.split(Platform.pathSeparator).last == 'tool'
    ? '../skills.sh.json'
    : 'skills.sh.json';

void main() {
  test('Validate skills.sh.json covers all active skills', () {
    final skillsDir = _requireSkillsDir();
    final actualSkills = skillsDir
        .listSync()
        .whereType<Directory>()
        .where((dir) => File('${dir.path}/SKILL.md').existsSync())
        .map((dir) => dir.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();

    final configFile = File(_skillsShJsonPath);
    expect(
      configFile.existsSync(),
      isTrue,
      reason: 'skills.sh.json not found at ${configFile.path}',
    );

    final decoded =
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      decoded[r'$schema'],
      'https://skills.sh/schemas/skills.sh.schema.json',
    );
    expect(decoded['notGrouped'], 'bottom');

    final groupings = decoded['groupings'] as List<Object?>;
    expect(groupings, isNotEmpty);

    final groupedSkills = <String>{};
    for (final group in groupings.cast<Map<String, Object?>>()) {
      final title = group['title'];
      expect(
        title,
        isA<String>().having(
          (s) =>
              s.trim().isNotEmpty && s.trim().split(RegExp(r'\s+')).length <= 3,
          '1-3 words',
          isTrue,
        ),
      );
      expect(
        group['description'],
        isA<String>().having((s) => s.isNotEmpty, 'non-empty', isTrue),
      );
      final skills = (group['skills'] as List<Object?>).cast<String>();
      expect(skills, isNotEmpty);
      for (final skill in skills) {
        expect(
          groupedSkills.add(skill),
          isTrue,
          reason: 'Duplicate skill "$skill" in skills.sh.json',
        );
      }
    }

    expect(groupedSkills, equals(actualSkills));
  });

  test('Validate skills', () async {
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen((record) {
      print(record.message);
    });

    try {
      final config = await ConfigParser.loadConfig(path: _configFilePath);
      final isValid = await validateSkills(config: config);
      expect(
        isValid,
        isTrue,
        reason: 'Skills validation failed. See above for details.',
      );
    } finally {
      await subscription.cancel();
    }
  });

  test('Run skill/scripts/test', () async {
    final skillsDir = _requireSkillsDir();
    await _runSkillScriptTests(skillsDir);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Verify formatting and analysis of all skills Dart code', () async {
    final skillsDir = _requireSkillsDir();

    final formatProcess = await TestProcess.start(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      skillsDir.path,
    ]);
    await formatProcess.shouldExit(0);

    await _ensureNestedPackagesResolved(skillsDir);

    final analyzeProcess = await TestProcess.start(
      Platform.resolvedExecutable,
      ['analyze', '--fatal-infos', skillsDir.path],
    );
    await analyzeProcess.shouldExit(0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  _registerUpskillRepoTests();
  _registerP1AndP2UnitTests();
  _registerP3AndP4UnitTests();
  _registerP5UnitTests();
}

void _registerUpskillRepoTests() {
  test('Enforce upskill static checks (P1.1, P1.2, P2.1, P3.4, P4.2) on all '
      'skills', () {
    final skillsDir = _requireSkillsDir();
    final findings = <SkillStaticFinding>[];
    final skillDirs = skillsDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final dir in skillDirs) {
      findings.addAll(auditSkillDirectory(dir));
    }
    expect(
      findings,
      isEmpty,
      reason:
          'Upskill static checks failed:\n'
          '${findings.map((f) => '  - $f').join('\n')}',
    );
  });

  test('Enforce P5.1 Zero-Content-Loss corpus diff on modified skills', () {
    final skillsDir = _requireSkillsDir();
    for (final ref in <String?>[null, 'HEAD']) {
      final diffResults = verifyModifiedSkillsAgainstGit(
        skillsDir: skillsDir,
        baseRef: ref,
      );
      for (final entry in diffResults.entries) {
        expect(
          entry.value.passed,
          isTrue,
          reason:
              'P5.1 Zero-Content-Loss check failed for skill '
              '"${entry.key}" against ${ref ?? 'default base ref'}: '
              '${entry.value}',
        );
      }
    }
  });
}

void _registerP1AndP2UnitTests() {
  group('P1.1 / P1.2 view_file Byte & Char Ceiling unit tests', () {
    test('detects oversized SKILL.md and references/*.md files', () {
      final tmp = Directory.systemTemp.createTempSync('upskill_p1_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/SKILL.md').writeAsStringSync('a' * 120);
      final refsDir = Directory('${tmp.path}/references')..createSync();
      File('${refsDir.path}/big.md').writeAsStringSync('b' * 120);

      expect(
        checkSkillSizeBudgets(tmp, maxSkillChars: 200, maxBytes: 200),
        isEmpty,
      );
      final findings = checkSkillSizeBudgets(
        tmp,
        maxSkillChars: 100,
        maxBytes: 100,
      );
      expect(findings.map((f) => f.code), containsAll(['P1.1', 'P1.2']));
    });
  });

  group('P2.1 Self-Contained Quick Start Delegation unit tests', () {
    test('passes when Quick Start table row includes CLI --flags', () {
      const md = '''
| Task | Command |
| :--- | :--- |
| Run query | `duckdb -batch --version` (see references/recipes.md) |
| Read docs | Read `references/recipes.md` first (see references/recipes.md) |
''';
      expect(findIncompleteQuickStartDelegations(md), isEmpty);
    });

    test(
      'fails when table row combines flagless CLI stub with see pointer',
      () {
        const md = '''
| Task | Command |
| :--- | :--- |
| Run query | `duckdb query` — see references/recipes.md |
| Run g3 CLI | `/google/bin/releases/f1/f1-sql` (see foo/SKILL.md) |
| Inside fence | ignored below |
```markdown
| Ignored | `duckdb query` — see references/recipes.md |
```
''';
        expect(findIncompleteQuickStartDelegations(md), hasLength(2));
      },
    );
  });
}

void _registerP3AndP4UnitTests() {
  group('P3.4 Anti-Frontmatter-Blindness unit tests', () {
    test('passes when every reference topic has a >=4-char token in desc', () {
      const desc =
          'Evaluates drafts with a fresh reader persona and SQL recipes.';
      final missing = findMissingReferenceTopics(
        description: desc,
        referenceFileNames: [
          'persona.md',
          'recipes.md',
          'README.md',
          'contributing.md',
        ],
      );
      expect(missing, isEmpty);
    });

    test('fails when reference topic tokens are absent from description', () {
      const desc = 'Evaluates drafts with a fresh reader.';
      final missing = findMissingReferenceTopics(
        description: desc,
        referenceFileNames: ['persona.md', 'miss-diagnosis-examples.md'],
      );
      expect(missing, hasLength(2));
      expect(missing.first, contains('persona.md'));
      expect(missing.last, contains('miss-diagnosis-examples.md'));
    });
  });

  group('P4.2 GFM Table Pipe Hygiene unit tests', () {
    test('passes on escaped pipes, logical OR pipes, and fenced blocks', () {
      const md = r'''
| Check | Command |
| :--- | :--- |
| Escaped | `foo \| bar` |
| Logical OR | `cmd1 || cmd2` |

```bash
| Inside fence | `unescaped | pipe` |
```
''';
      expect(hasUnescapedPipeInsideTableInlineCode(md), isFalse);
      expect(findUnescapedPipesInTableInlineCode(md), isEmpty);
    });

    test('fails on unescaped pipe inside inline code span in table row', () {
      const md = '''
| Check | Command |
| :--- | :--- |
| Broken | `cat file.txt | grep foo` |
''';
      expect(hasUnescapedPipeInsideTableInlineCode(md), isTrue);
      expect(
        findUnescapedPipesInTableInlineCode(md),
        equals(['`cat file.txt | grep foo`']),
      );
    });
  });
}

void _registerP5UnitTests() {
  group('P5.1 Zero-Content-Loss Corpus Token-Set Diff unit tests', () {
    test('passes when all flags and script/reference paths are preserved', () {
      const base = '''
Run `scripts/check.py --strict --format=json` and read `references/guide.md`.
''';
      const candidate = '''
Updated docs: read `references/guide.md` and run
`scripts/check.py --strict --format=json --verbose`.
''';
      final diff = verifySkillCorpusDiff(
        baseCorpus: base,
        candidateCorpus: candidate,
      );
      expect(diff.passed, isTrue);
      expect(diff.missingFlags, isEmpty);
      expect(diff.missingPaths, isEmpty);
    });

    test('fails when a CLI flag or relative path is accidentally dropped', () {
      const base = '''
Run `scripts/check.py --strict --timeout` and read `references/guide.md`.
''';
      const candidate = '''
Run `scripts/check.py --strict`.
''';
      final diff = verifySkillCorpusDiff(
        baseCorpus: base,
        candidateCorpus: candidate,
      );
      expect(diff.passed, isFalse);
      expect(diff.missingFlags, equals({'--timeout'}));
      expect(diff.missingPaths, equals({'references/guide.md'}));
    });

    test('passes when dropped tokens are explicitly suppressed', () {
      const base = '''
Run `scripts/legacy.py --legacy-flag --keep-flag` and `references/old.md`.
''';
      const candidate = '''
<!-- allow-drop: --legacy-flag -->
Run `scripts/legacy.py --keep-flag`.
''';
      final diff = verifySkillCorpusDiff(
        baseCorpus: base,
        candidateCorpus: candidate,
        allowedDrops: {'references/old.md'},
      );
      expect(diff.passed, isTrue);
    });
  });
}

Directory _requireSkillsDir() {
  final skillsDir = Directory(_skillsDirPath);
  expect(
    skillsDir.existsSync(),
    isTrue,
    reason: 'Skills directory not found at ${skillsDir.path}',
  );
  return skillsDir;
}

Future<void> _ensurePubGet(Directory packageDir) async {
  final packageConfig = File(
    '${packageDir.path}/.dart_tool/package_config.json',
  );
  if (!packageConfig.existsSync()) {
    final process = await TestProcess.start(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: packageDir.path);
    await process.shouldExit(0);
  }
}

Future<void> _runSkillScriptTests(Directory skillsDir) async {
  for (final dir in skillsDir.listSync().whereType<Directory>()) {
    final scriptsDir = Directory('${dir.path}/scripts');
    if (scriptsDir.existsSync() &&
        File('${scriptsDir.path}/pubspec.yaml').existsSync()) {
      print('Running tests in ${scriptsDir.path}');
      await _ensurePubGet(scriptsDir);
      final process = await TestProcess.start(Platform.resolvedExecutable, [
        'test',
      ], workingDirectory: scriptsDir.path);
      await process.shouldExit(0);
    }
  }
}

Future<void> _ensureNestedPackagesResolved(Directory skillsDir) async {
  final validDirs = skillsDir.listSync().whereType<Directory>().where(
    (dir) => File('${dir.path}/SKILL.md').existsSync(),
  );
  for (final dir in validDirs) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      await _ensurePubGet(pubspec.parent);
    }
    final scriptsPubspec = File('${dir.path}/scripts/pubspec.yaml');
    if (scriptsPubspec.existsSync()) {
      await _ensurePubGet(scriptsPubspec.parent);
    }
  }
}
