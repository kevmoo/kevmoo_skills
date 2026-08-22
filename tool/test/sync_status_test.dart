import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'test_utils.dart';
import '../../skills/github-pr-triage/lib/github_cli.dart';

void main() {
  group('fetchPrSyncStatus unit tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sync_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'returns in_sync when local and remote SHAs match in git repo',
      () async {
        // Initialize git repo in tempDir
        final setup = await setupTestGitRepo(tempDir);
        final headSha = setup.headSha;
        final currentBranch = setup.branch;
        final context = setup.context;

        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: currentBranch,
          remoteHeadSha: headSha,
        );

        expect(status.isSynced, isTrue);
        expect(status.syncState, equals('in_sync'));
        expect(status.localHeadSha, equals(headSha));
        expect(status.remoteHeadSha, equals(headSha));
        expect(status.warning, isNull);
      },
    );

    test(
      'returns branch_mismatch when active local branch differs from remote PR branch',
      () async {
        final setup = await setupTestGitRepo(tempDir);
        final headSha = setup.headSha;
        final currentBranch = setup.branch;
        final context = setup.context;

        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: 'different-feature-branch',
          remoteHeadSha: headSha,
        );

        expect(status.isSynced, isFalse);
        expect(status.syncState, equals('branch_mismatch'));
        expect(status.localBranch, equals(currentBranch));
        expect(status.remoteBranch, equals('different-feature-branch'));
        expect(
          status.warning,
          contains(
            'Active local branch is "$currentBranch", but the PR branch is "different-feature-branch"',
          ),
        );
      },
    );

    test(
      'returns ahead_of_remote when local repo has unpushed commits',
      () async {
        final setup = await setupTestGitRepo(tempDir, commits: 2);
        final firstCommitSha = setup.commitShas[0];
        final secondCommitSha = setup.commitShas[1];

        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = setup.context;

        // Local is at secondCommitSha, remote PR is at firstCommitSha
        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: currentBranch,
          remoteHeadSha: firstCommitSha,
        );

        expect(status.isSynced, isFalse);
        expect(status.syncState, equals('ahead_of_remote'));
        expect(status.localHeadSha, equals(secondCommitSha));
        expect(status.remoteHeadSha, equals(firstCommitSha));
        expect(status.warning, contains('is ahead of remote PR commit'));
      },
    );

    test(
      'returns behind_remote when local repo is behind remote PR commit',
      () async {
        final setup = await setupTestGitRepo(tempDir, commits: 2);
        final firstCommitSha = setup.commitShas[0];
        final secondCommitSha = setup.commitShas[1];

        // Reset local repo back to first commit
        await runCommand('git', [
          'reset',
          '--hard',
          firstCommitSha,
        ], workingDirectory: tempDir.path);

        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = setup.context;

        // Local is at firstCommitSha, remote PR is at secondCommitSha
        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: currentBranch,
          remoteHeadSha: secondCommitSha,
        );

        expect(status.isSynced, isFalse);
        expect(status.syncState, equals('behind_remote'));
        expect(status.localHeadSha, equals(firstCommitSha));
        expect(status.remoteHeadSha, equals(secondCommitSha));
        expect(status.warning, contains('is behind remote PR commit'));
      },
    );

    test('returns isSynced false when local or remote SHA is empty', () async {
      final setup = await setupTestGitRepo(tempDir);
      final currentBranch = setup.branch;
      final context = setup.context;

      final status = await fetchPrSyncStatus(
        context,
        remoteBranch: currentBranch,
        remoteHeadSha: '',
      );

      expect(status.isSynced, isFalse);
      expect(status.syncState, equals('unknown'));
      expect(status.warning, contains('Could not determine'));
    });

    test(
      'returns behind_remote when remote commit is not found in local repo',
      () async {
        final setup = await setupTestGitRepo(tempDir);
        final currentBranch = setup.branch;
        final context = setup.context;

        // Simulated remote commit SHA that does not exist in local repo object store
        const nonExistentSha = '0123456789abcdef0123456789abcdef01234567';

        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: currentBranch,
          remoteHeadSha: nonExistentSha,
        );

        expect(status.isSynced, isFalse);
        expect(status.syncState, equals('not_fetched'));
        expect(
          status.warning,
          contains('is not present in your local repository'),
        );
      },
    );
  });

  group('resolvePrContext unit tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resolve_pr_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> mockRunCommand(
      String command,
      List<String> args, {
      String? workingDirectory,
    }) async {
      if (command == 'gh' &&
          args.length >= 2 &&
          args[0] == 'repo' &&
          args[1] == 'view') {
        return jsonEncode({
          'owner': {'login': 'kevmoo'},
          'name': 'kevmoo_skills',
        });
      }
      return runCommand(command, args, workingDirectory: workingDirectory);
    }

    test(
      'allows localOwner != owner when localRepo matches repo (fork workflow)',
      () async {
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'remote',
          'add',
          'origin',
          'https://github.com/kevmoo/kevmoo_skills.git',
        ], workingDirectory: tempDir.path);

        final context = await resolvePrContext(
          [
            '--dir',
            tempDir.path,
            '--pr',
            'https://github.com/forkcontributor/kevmoo_skills/pull/10',
          ],
          onFail: (message) => fail('Should not fail: $message'),
          runCommand: mockRunCommand,
        );

        expect(context.owner, equals('forkcontributor'));
        expect(context.repo, equals('kevmoo_skills'));
        expect(context.prNumber, equals('10'));
      },
    );

    test(
      'allows localRepo != repo when owner/repo matches configured git remote',
      () async {
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'remote',
          'add',
          'origin',
          'https://github.com/kevmoo/kevmoo_skills.git',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'remote',
          'add',
          'upstream',
          'https://github.com/upstreamowner/some_other_repo.git',
        ], workingDirectory: tempDir.path);

        final context = await resolvePrContext(
          [
            '--dir',
            tempDir.path,
            '--pr',
            'https://github.com/upstreamowner/some_other_repo/pull/25',
          ],
          onFail: (message) => fail('Should not fail: $message'),
          runCommand: mockRunCommand,
        );

        expect(context.owner, equals('upstreamowner'));
        expect(context.repo, equals('some_other_repo'));
        expect(context.prNumber, equals('25'));
      },
    );

    test(
      'rejects when localRepo != repo and owner/repo is not in git remotes',
      () async {
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'remote',
          'add',
          'origin',
          'https://github.com/kevmoo/kevmoo_skills.git',
        ], workingDirectory: tempDir.path);

        String? failMsg;
        try {
          await resolvePrContext(
            [
              '--dir',
              tempDir.path,
              '--pr',
              'https://github.com/otherowner/unrelated_repo/pull/50',
            ],
            onFail: (message) {
              failMsg = message;
              throw StateError(message);
            },
            runCommand: mockRunCommand,
          );
        } catch (_) {}

        expect(
          failMsg,
          contains(
            'The target directory "${tempDir.path}" is for repository "kevmoo/kevmoo_skills", '
            'but the specified PR is for repository "otherowner/unrelated_repo".',
          ),
        );
      },
    );
  });
}
