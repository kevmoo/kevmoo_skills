import 'dart:io';
import 'package:dart_skills_lint/dart_skills_lint.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

final String _configFilePath = Directory.current.path.endsWith('tool')
    ? 'dart_skills_lint.yaml'
    : 'tool/dart_skills_lint.yaml';

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
    final skillsDir = Directory(
      Directory.current.path.endsWith('tool') ? '../skills' : 'skills',
    );
    expect(
      skillsDir.existsSync(),
      isTrue,
      reason: 'Skills directory not found at ${skillsDir.path}',
    );

    final skillDirs = skillsDir.listSync().whereType<Directory>();
    for (final dir in skillDirs) {
      final scriptsDir = Directory('${dir.path}/scripts');
      if (scriptsDir.existsSync() &&
          File('${scriptsDir.path}/pubspec.yaml').existsSync()) {
        print('Running tests in ${scriptsDir.path}');

        final packageConfig = File(
          '${scriptsDir.path}/.dart_tool/package_config.json',
        );
        if (!packageConfig.existsSync()) {
          final pubGetResult = Process.runSync(Platform.resolvedExecutable, [
            'pub',
            'get',
          ], workingDirectory: scriptsDir.path);
          expect(
            pubGetResult.exitCode,
            0,
            reason:
                'dart pub get failed in ${scriptsDir.path}:\n${pubGetResult.stderr}',
          );
        }

        final process = await TestProcess.start(Platform.resolvedExecutable, [
          'test',
        ], workingDirectory: scriptsDir.path);
        await process.shouldExit(0);
      }
    }
  });

  test('Verify formatting and analysis of all skills Dart code', () {
    final skillsDir = Directory(
      Directory.current.path.endsWith('tool') ? '../skills' : 'skills',
    );
    expect(
      skillsDir.existsSync(),
      isTrue,
      reason: 'Skills directory not found at ${skillsDir.path}',
    );

    final formatResult = Process.runSync(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      skillsDir.path,
    ]);
    expect(
      formatResult.exitCode,
      0,
      reason:
          'Skills Dart formatting check failed:\n${formatResult.stderr}\n${formatResult.stdout}',
    );

    // Ensure pub get has been run for all nested packages to prevent analysis failures
    final pubspecs = skillsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('pubspec.yaml'));
    for (final pubspec in pubspecs) {
      final result = Process.runSync(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: pubspec.parent.path);
      expect(
        result.exitCode,
        0,
        reason: 'pub get failed in ${pubspec.parent.path}:\n${result.stderr}',
      );
    }

    final analyzeResult = Process.runSync(Platform.resolvedExecutable, [
      'analyze',
      '--fatal-infos',
      skillsDir.path,
    ]);
    expect(
      analyzeResult.exitCode,
      0,
      reason:
          'Skills Dart analysis check failed:\n${analyzeResult.stderr}\n${analyzeResult.stdout}',
    );
  });
}
