import 'dart:io';

import 'package:test/test.dart';
import '../../skills/github-pr-triage/lib/github_cli.dart';

void main() {
  group('fetchFailedCheckLog unit tests', () {
    late Directory tempDir;
    late PrContext context;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('job_logs_test_');
      context = PrContext(
        workingDir: tempDir.path,
        prNumber: '999',
        owner: 'test-owner',
        repo: 'test-repo',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns non-GHA notice when link is not GitHub Actions', () async {
      final check = (
        name: 'Custom Check',
        state: 'FAILURE',
        bucket: 'fail',
        link: 'https://example.com/build/123',
        workflow: 'Custom',
      );

      final result = await fetchFailedCheckLog(context, check);
      expect(result, contains('Non-GitHub Actions run'));
      expect(result, contains('https://example.com/build/123'));
    });

    test('checkRunIdMatch matches both /check-runs/ and /runs/', () {
      final regex = RegExp(r'/(?:check-runs|runs)/(\d+)');
      final match1 = regex.firstMatch(
        'https://github.com/foo/bar/check-runs/12345',
      );
      final match2 = regex.firstMatch('https://github.com/foo/bar/runs/67890');

      expect(match1?.group(1), equals('12345'));
      expect(match2?.group(1), equals('67890'));
    });
  });
}
