import 'dart:io';

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

void main() {
  test('Validate skills', () async {
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen((record) {
      print(record.message);
    });

    try {
      final Configuration config = await ConfigParser.loadConfig(
        path: _configFilePath,
      );
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
  }, timeout: Timeout(Duration(minutes: 3)));

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
  }, timeout: Timeout(Duration(minutes: 3)));
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
