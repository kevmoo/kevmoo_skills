import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../skills/github-pr-triage/bin/triage.dart';
import '../../skills/github-pr-triage/lib/github_cli.dart';
import '../../skills/pr-loop/bin/pr_status.dart';

void main() {
  _registerJobLogsTests();
  _registerTriageReportTests();
  _registerPrStatusTests();
}

void _registerJobLogsTests() {
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
      const check = (
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

    test('combines check annotations and failed job logs from API', () async {
      const check = (
        name: 'CI / test',
        state: 'FAILURE',
        bucket: 'fail',
        link:
            'https://github.com/test-owner/test-repo/actions/runs/111/job/222',
        workflow: 'CI',
      );

      final result = await fetchFailedCheckLog(
        context,
        check,
        runCommand: _mockAnnotationsAndJobLogsRunner,
      );
      expect(
        result,
        contains('Annotation [failure] lib/foo.dart:42 (Analyze): Bad type'),
      );
      expect(result, contains('--- Job: unit_test (ID: 222) ---'));
      expect(result, contains('Expected: 1\nActual: 2'));
    });

    test('falls back to gh run view --log-failed when job logs empty', () async {
      const check = (
        name: 'CI / test',
        state: 'FAILURE',
        bucket: 'fail',
        link:
            'https://github.com/test-owner/test-repo/actions/runs/111/job/222',
        workflow: 'CI',
      );

      final result = await fetchFailedCheckLog(
        context,
        check,
        runCommand: _mockFallbackRunViewRunner,
      );
      expect(result, contains('Check Annotations:'));
      expect(result, contains('Fallback CLI failure log output'));
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
          'https://github.com/owner/repo/actions/runs/123456789/job/987654321',
        ),
        equals('123456789'),
      );
      expect(parseRunIdFromLink('https://example.com/build/123456789'), isNull);
    });

    test('parseCheckRunIdFromLink extracts check run IDs and job IDs', () {
      expect(
        parseCheckRunIdFromLink('https://github.com/foo/bar/check-runs/12345'),
        equals('12345'),
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
    });
  });
}

Future<String> _mockAnnotationsAndJobLogsRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final joined = arguments.join(' ');
  if (joined.contains('check-runs/222/annotations')) {
    return jsonEncode([
      {
        'path': 'lib/foo.dart',
        'start_line': 42,
        'message': 'Bad type',
        'annotation_level': 'failure',
        'title': 'Analyze',
      },
    ]);
  }
  if (joined.contains('actions/runs/111/jobs')) {
    return jsonEncode({
      'jobs': [
        {'id': 222, 'name': 'unit_test', 'conclusion': 'failure'},
        {'id': 223, 'name': 'lint', 'conclusion': 'success'},
      ],
    });
  }
  if (joined.contains('actions/jobs/222/logs')) {
    return 'Expected: 1\nActual: 2';
  }
  throw StateError('Unexpected command: $joined');
}

Future<String> _mockFallbackRunViewRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final joined = arguments.join(' ');
  if (joined.contains('check-runs/222/annotations')) {
    return jsonEncode([
      {
        'path': 'bin/main.dart',
        'start_line': 10,
        'message': 'Compile error',
        'annotation_level': 'failure',
        'title': 'Build',
      },
    ]);
  }
  if (joined.contains('actions/runs/111/jobs')) {
    return jsonEncode({'jobs': <Object>[]});
  }
  if (joined.contains('run view 111 --log-failed')) {
    return 'Fallback CLI failure log output';
  }
  throw StateError('Unexpected command: $joined');
}

void _registerTriageReportTests() {
  group('triage.dart report builder tests', () {
    test(
      'buildTriageReport renders threads, reviews, comments, and checks',
      () {
        final data = (
          prData: <String, dynamic>{
            'number': 42,
            'title': 'Fix parser bug',
            'url': 'https://github.com/o/r/pull/42',
            'headRefName': 'fix-parser',
            'headRefOid': 'abc1234',
            'reviewDecision': 'CHANGES_REQUESTED',
            'mergeable': 'MERGEABLE',
          },
          syncStatus: (
            localBranch: 'fix-parser',
            remoteBranch: 'fix-parser',
            localHeadSha: 'def5678',
            remoteHeadSha: 'abc1234',
            isSynced: false,
            syncState: 'behind_remote',
            warning: 'Local branch is behind remote.',
          ),
          unresolvedThreads: <PrReviewThread>[
            (
              id: 'PRRT_1',
              isResolved: false,
              comments: [
                (
                  databaseId: '9001',
                  path: 'lib/parser.dart',
                  line: 18,
                  body: 'Please handle null\nhere.',
                  author: 'alice',
                  createdAt: '2026-09-18T10:00:00Z',
                  url: 'https://github.com/o/r/pull/42#discussion_r9001',
                ),
              ],
            ),
          ],
          reviewComments: <PrReview>[
            (
              id: 'PRR_1',
              databaseId: '8001',
              state: 'CHANGES_REQUESTED',
              body: 'Needs a unit test.',
              author: 'bob',
              submittedAt: '2026-09-18T10:05:00Z',
              url: 'https://github.com/o/r/pull/42#pullrequestreview-8001',
            ),
          ],
          generalComments: <PrComment>[
            (
              databaseId: '7001',
              path: '',
              line: null,
              body: '/gemini review',
              author: 'kevmoo',
              createdAt: '2026-09-18T10:06:00Z',
              url: 'https://github.com/o/r/pull/42#issuecomment-7001',
            ),
          ],
          failedChecks: <PrCheckRun>[
            (
              name: 'test (ubuntu-latest)',
              state: 'FAILURE',
              bucket: 'fail',
              link: 'https://github.com/o/r/actions/runs/1/job/2',
              workflow: 'CI',
            ),
          ],
          pendingChecks: <PrCheckRun>[
            (
              name: 'test (macos-latest)',
              state: 'IN_PROGRESS',
              bucket: 'pending',
              link: 'https://github.com/o/r/actions/runs/1/job/3',
              workflow: 'CI',
            ),
          ],
          checkLogs: <String, String>{
            'test (ubuntu-latest)': '1 test failed in parser_test.dart',
          },
        );

        final report = buildTriageReport(data);
        expect(report, contains('# PR Triage Report: #42 - Fix parser bug'));
        expect(
          report,
          contains('> [!WARNING]\n> Local branch is behind remote.'),
        );
        expect(report, contains('Thread `PRRT_1`, Comment `9001`'));
        expect(report, contains('> Please handle null\n> here.'));
        expect(report, contains('Review `PRR_1`, Database ID `8001`'));
        expect(report, contains('Conversation Comment #1 (Comment `7001`)'));
        expect(report, contains('### ❌ test (ubuntu-latest)'));
        expect(report, contains('1 test failed in parser_test.dart'));
        expect(report, contains('⏳ **test (macos-latest)**'));
      },
    );

    test('truncateLog keeps <=100 lines and truncates >100 lines', () {
      final shortLog = List.generate(20, (i) => 'line $i').join('\n');
      expect(truncateLog(shortLog), equals(shortLog));

      final longLog = List.generate(125, (i) => 'line $i').join('\n');
      final truncated = truncateLog(longLog);
      expect(truncated, contains('... [TRUNCATED 25 LINES] ...'));
      expect(truncated, contains('line 0'));
      expect(truncated, contains('line 124'));
    });

    test(
      'buildTriageReport and parseMergeTreeConflictOutput surface merge conflicts prominently',
      () {
        const mergeTreeSample = '''
c5c7aa93942fd3d8dd7b4300136f7589f5a66b98
lib/src/gh_view/report_renderer.dart
lib/src/git_extensions.dart

Auto-merging lib/src/gh_view/report_renderer.dart
CONFLICT (content): Merge conflict in lib/src/gh_view/report_renderer.dart
Auto-merging lib/src/git_extensions.dart
CONFLICT (content): Merge conflict in lib/src/git_extensions.dart
''';
        final parsed = parseMergeTreeConflictOutput(mergeTreeSample);
        expect(
          parsed.files,
          equals([
            'lib/src/gh_view/report_renderer.dart',
            'lib/src/git_extensions.dart',
          ]),
        );
        expect(parsed.messages, hasLength(2));

        final data = (
          prData: <String, dynamic>{
            'number': 326,
            'title': 'chore(release): prepare firestore v0.5.5',
            'url': 'https://github.com/firebase/firebase-admin-dart/pull/326',
            'headRefName': 'widen-deps',
            'baseRefName': 'main',
            'headRefOid': '358eee6',
            'reviewDecision': 'APPROVED',
            'mergeable': 'CONFLICTING',
            'mergeStateStatus': 'DIRTY',
          },
          syncStatus: (
            localBranch: 'widen-deps',
            remoteBranch: 'widen-deps',
            localHeadSha: '358eee6',
            remoteHeadSha: '358eee6',
            isSynced: true,
            syncState: 'in_sync',
            warning: null,
          ),
          unresolvedThreads: <PrReviewThread>[],
          reviewComments: <PrReview>[],
          generalComments: <PrComment>[],
          failedChecks: <PrCheckRun>[],
          pendingChecks: <PrCheckRun>[],
          checkLogs: <String, String>{},
        );

        final report = buildTriageReport(
          data,
          conflictAnalysis: (
            isConflicting: true,
            mergeable: 'CONFLICTING',
            mergeStateStatus: 'DIRTY',
            baseRefName: 'main',
            headRefName: 'widen-deps',
            conflictingFiles: parsed.files,
            conflictMessages: parsed.messages,
            upstreamCommits: [
              '2bcf7bd refactor: reduce cognitive complexity (#106)',
            ],
          ),
        );

        expect(report, contains('**Mergeable**: `CONFLICTING` ⚠️ (BLOCKER)'));
        expect(report, contains('**MERGE CONFLICT BLOCKER**'));
        expect(report, contains('## ⚠️ Merge Conflicts (2 conflicting files)'));
        expect(report, contains('- `lib/src/git_extensions.dart`'));
        expect(
          report,
          contains('- `2bcf7bd refactor: reduce cognitive complexity (#106)`'),
        );
        expect(report, contains('BLOCKED BY MERGE CONFLICTS'));
      },
    );
  });
}

void _registerPrStatusTests() {
  group('pr_status.dart evaluation tests', () {
    const syncedStatus = (
      localBranch: 'feat',
      remoteBranch: 'feat',
      localHeadSha: 'abc',
      remoteHeadSha: 'abc',
      isSynced: true,
      syncState: 'in_sync',
      warning: null,
    );

    test('evaluateTermination checks all gate conditions in order', () {
      expect(
        evaluateTermination(
          syncStatus: (
            localBranch: 'feat',
            remoteBranch: 'feat',
            localHeadSha: 'abc',
            remoteHeadSha: 'def',
            isSynced: false,
            syncState: 'behind_remote',
            warning: 'Behind remote',
          ),
          graphqlError: null,
          inProgressChecks: const [],
          failedChecks: const [],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: false,
        ),
        equals((false, 'Behind remote')),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: 'GraphQL timeout',
          inProgressChecks: const [],
          failedChecks: const [],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: false,
        ),
        equals((
          false,
          'Failed to verify PR threads/reactions: GraphQL timeout',
        )),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: null,
          inProgressChecks: const ['build'],
          failedChecks: const [],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: false,
        ),
        equals((false, 'CI workflow(s) still in progress: build')),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: null,
          inProgressChecks: const [],
          failedChecks: const ['lint'],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: false,
        ),
        equals((false, 'CI workflow(s) failed: lint')),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: null,
          inProgressChecks: const [],
          failedChecks: const [],
          unresolvedThreadsCount: 2,
          hasActiveEyesReaction: false,
        ),
        equals((false, 'There are 2 unresolved review thread(s)')),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: null,
          inProgressChecks: const [],
          failedChecks: const [],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: true,
        ),
        equals((
          false,
          'Review bot has an active EYES (👀) reaction processing feedback',
        )),
      );

      expect(
        evaluateTermination(
          syncStatus: syncedStatus,
          graphqlError: null,
          inProgressChecks: const [],
          failedChecks: const [],
          unresolvedThreadsCount: 0,
          hasActiveEyesReaction: false,
        ),
        equals((true, null)),
      );
    });

    test(
      'evaluateChecks and evaluateGraphData classify bot review timestamps',
      () async {
        final context = PrContext(
          workingDir: '/tmp',
          prNumber: '111',
          owner: 'kevmoo',
          repo: 'kevmoo_skills',
        );

        final checksResult = await evaluateChecks(
          context,
          runCommand: (_, __, {workingDirectory}) async => jsonEncode([
            {
              'name': 'lint',
              'state': 'SUCCESS',
              'bucket': 'pass',
              'link': '',
              'workflow': '',
            },
            {
              'name': 'unit',
              'state': 'IN_PROGRESS',
              'bucket': 'pending',
              'link': '',
              'workflow': '',
            },
            {
              'name': 'e2e',
              'state': 'FAILURE',
              'bucket': 'fail',
              'link': '',
              'workflow': '',
            },
          ]),
        );
        expect(checksResult.$1, equals(['unit']));
        expect(checksResult.$2, equals(['e2e']));

        final evalAfterBotReview = await evaluateGraphData(
          context,
          runCommand: (_, __, {workingDirectory}) async => jsonEncode({
            'data': {
              'repository': {
                'pullRequest': {
                  'comments': {
                    'nodes': [
                      {
                        'id': 'C1',
                        'databaseId': 1,
                        'body': '/gemini review',
                        'createdAt': '2026-09-18T12:00:00Z',
                        'url': '',
                        'author': {'login': 'kevmoo'},
                      },
                    ],
                  },
                  'reviews': {
                    'nodes': [
                      {
                        'id': 'R1',
                        'databaseId': 2,
                        'state': 'COMMENTED',
                        'body': 'LGTM',
                        'submittedAt': '2026-09-18T12:05:00Z',
                        'url': '',
                        'author': {'login': 'gemini-code-assist[bot]'},
                      },
                    ],
                  },
                  'reviewThreads': {
                    'nodes': [
                      {
                        'id': 'T1',
                        'isResolved': true,
                        'comments': {'nodes': <Object>[]},
                      },
                    ],
                  },
                },
              },
            },
          }),
        );
        expect(evalAfterBotReview.hasActiveEyesReaction, isFalse);
        expect(evalAfterBotReview.unresolvedThreadsCount, equals(0));
      },
    );
  });
}
