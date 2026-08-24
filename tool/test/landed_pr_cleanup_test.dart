import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:github_landed_pr_cleanup/github_landed_pr_cleanup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LandedPr model', () {
    test('parses search and view json data correctly', () {
      final searchJson = {
        'repository': {'nameWithOwner': 'dart-lang/samples'},
        'number': 250,
        'title': 'chore(ci): remove unpinned coveralls',
        'url': 'https://github.com/dart-lang/samples/pull/250',
        'closedAt': '2026-08-24T11:21:09Z',
      };
      final viewJson = {
        'headRefName': 'remove-coveralls',
        'baseRefName': 'main',
        'mergeCommit': {'oid': '9aa1e69275c818cb96168be97c587e9eb4fb08ee'},
        'body': 'Fixes #59SAR and related to #V6BMB',
      };

      final pr = LandedPr.fromJson(searchJson, viewData: viewJson);
      check(pr.repository).equals('dart-lang/samples');
      check(pr.owner).equals('dart-lang');
      check(pr.repoName).equals('samples');
      check(pr.number).equals(250);
      check(pr.headRefName).equals('remove-coveralls');
      check(pr.baseRefName).equals('main');
      check(
        pr.mergeCommitSha,
      ).equals('9aa1e69275c818cb96168be97c587e9eb4fb08ee');
      check(pr.body).contains('#59SAR');
    });
  });

  group('LocalRepoState matching', () {
    test('finds matching worktree by branch and folder name', () {
      final repoState = LocalRepoState(
        repoPath: '/home/user/github/samples',
        exists: true,
        currentBranch: 'main',
        worktrees: [
          WorktreeInfo(
            path: '/home/user/github/samples',
            head: 'abc',
            branch: 'main',
          ),
          WorktreeInfo(
            path: '/home/user/github/_samples-remove-coveralls',
            head: 'def',
            branch: 'remove-coveralls',
          ),
        ],
        localBranches: ['main', 'remove-coveralls'],
      );

      final match = repoState.findMatchingWorktree(
        'remove-coveralls',
        'samples',
      );
      check(match).isNotNull();
      check(match!.path).equals('/home/user/github/_samples-remove-coveralls');
      check(repoState.hasLocalBranch('remove-coveralls')).isTrue();
      check(repoState.isDirectlyOnFeatureBranch('remove-coveralls')).isFalse();
    });
  });

  group('Report formatting', () {
    test('formats markdown and json reports accurately', () {
      final pr = LandedPr(
        repository: 'firebase/flutterfire',
        number: 18604,
        title: 'refactor platform interface',
        url: 'https://github.com/firebase/flutterfire/pull/18604',
        closedAt: DateTime.parse('2026-08-24T12:04:53Z'),
        headRefName: 'cleanup-meta-annotations',
        baseRefName: 'main',
        mergeCommitSha: 'fef6d42090ea275f07117c085bd04710d9df51bc',
      );

      final repoState = LocalRepoState(
        repoPath: '/home/user/github/flutterfire',
        exists: true,
        currentBranch: 'main',
        worktrees: [],
        localBranches: ['main'],
      );

      final result = CleanupResult(
        pr: pr,
        repoState: repoState,
        jetskiMatches: [
          JetskiMatch(
            conversationId: '7436b600-bf35-406b-9573-900e54a3bae9',
            matchedTerm: 'PR #18604',
            candidateHandles: ['#59SAR'],
          ),
        ],
        actions: [
          CleanupAction(
            description: 'Deleted branch `cleanup-meta-annotations`',
            success: true,
          ),
        ],
      );

      final md = formatMarkdownReport([result], applied: true);
      check(md).contains('firebase/flutterfire');
      check(md).contains('18604');
      check(md).contains('#59SAR');
      check(md).contains('Deleted branch');

      final jsonReport = formatJsonReport([result], applied: true);
      check(jsonReport['applied']).equals(true);
      check(jsonReport['count']).equals(1);
    });
  });

  group('Jetski discovery', () {
    test(
      'extracts conversation and candidate handles from mock transcripts',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'jetski_brain_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final sessionDir = Directory(
          p.join(tempDir.path, 'test-conv-1234', '.system_generated', 'logs'),
        )..createSync(recursive: true);
        final transcriptFile = File(
          p.join(sessionDir.path, 'transcript.jsonl'),
        );

        transcriptFile.writeAsStringSync(
          jsonEncode({
            'type': 'USER_INPUT',
            'content':
                'We need to fix https://github.com/dart-lang/samples/pull/250 and close #V6BMB',
          }),
        );

        final pr = LandedPr(
          repository: 'dart-lang/samples',
          number: 250,
          title: 'remove coveralls',
          url: 'https://github.com/dart-lang/samples/pull/250',
          closedAt: DateTime.now(),
          headRefName: 'remove-coveralls',
          baseRefName: 'main',
        );

        final matches = await findJetskiMatches(pr, brainDir: tempDir.path);
        check(matches.length).equals(1);
        check(matches.first.conversationId).equals('test-conv-1234');
        check(matches.first.candidateHandles).contains('#V6BMB');
      },
    );
  });
}
