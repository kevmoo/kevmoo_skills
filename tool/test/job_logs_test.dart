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

    test(
      'checkRunIdMatch matches /check-runs/, /runs/, and job-level URLs but excludes plain /actions/runs/',
      () {
        RegExpMatch? parseCheckRunId(String link) =>
            RegExp(r'/check-runs/(\d+)').firstMatch(link) ??
            RegExp(r'/actions/runs/\d+/jobs?/(\d+)').firstMatch(link) ??
            (link.contains('/actions/runs/')
                ? null
                : RegExp(r'/runs/(\d+)').firstMatch(link));

        final match1 = parseCheckRunId(
          'https://github.com/foo/bar/check-runs/12345',
        );
        final match2 = parseCheckRunId('https://github.com/foo/bar/runs/67890');
        final match3 = parseCheckRunId(
          'https://github.com/foo/bar/actions/runs/67890',
        );
        final match4 = parseCheckRunId(
          'https://github.com/foo/bar/actions/runs/12345/job/67890',
        );
        final match5 = parseCheckRunId(
          'https://github.com/foo/bar/actions/runs/12345/jobs/67890',
        );

        expect(match1?.group(1), equals('12345'));
        expect(match2?.group(1), equals('67890'));
        expect(match3, isNull);
        expect(match4?.group(1), equals('67890'));
        expect(match5?.group(1), equals('67890'));
      },
    );
  });
}
