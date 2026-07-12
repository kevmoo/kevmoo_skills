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

    test('parseRunIdFromLink extracts run ID from GitHub Actions URLs', () {
      expect(
        parseRunIdFromLink(
          'https://github.com/owner/repo/actions/runs/123456789',
        ),
        equals('123456789'),
      );
      expect(
        parseRunIdFromLink(
          'https://github.com/owner/repo/actions/runs/123456789/',
        ),
        equals('123456789'),
      );
      expect(
        parseRunIdFromLink(
          'https://github.com/owner/repo/actions/runs/123456789/job/987654321',
        ),
        equals('123456789'),
      );
      expect(parseRunIdFromLink('https://example.com/build/123456789'), isNull);
    });

    test(
      'parseCheckRunIdFromLink extracts check run IDs and job IDs correctly',
      () {
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/check-runs/12345',
          ),
          equals('12345'),
        );
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/check-runs/12345/',
          ),
          equals('12345'),
        );
        expect(
          parseCheckRunIdFromLink('https://github.com/foo/bar/runs/67890'),
          equals('67890'),
        );
        expect(
          parseCheckRunIdFromLink('https://github.com/foo/bar/runs/67890/'),
          equals('67890'),
        );
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/actions/runs/67890',
          ),
          isNull,
        );
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/actions/runs/12345/job/67890',
          ),
          equals('67890'),
        );
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/actions/runs/12345/job/67890/',
          ),
          equals('67890'),
        );
        expect(
          parseCheckRunIdFromLink(
            'https://github.com/foo/bar/actions/runs/12345/jobs/67890',
          ),
          equals('67890'),
        );
      },
    );
  });
}
