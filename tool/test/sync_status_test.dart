import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
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
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.name',
          'Test User',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.email',
          'test@example.com',
        ], workingDirectory: tempDir.path);

        File(p.join(tempDir.path, 'file.txt')).writeAsStringSync('hello');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'initial commit',
        ], workingDirectory: tempDir.path);

        final headSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();
        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = PrContext(
          workingDir: tempDir.path,
          prNumber: '1',
          owner: 'testowner',
          repo: 'testrepo',
        );

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
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.name',
          'Test User',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.email',
          'test@example.com',
        ], workingDirectory: tempDir.path);

        File(p.join(tempDir.path, 'file.txt')).writeAsStringSync('hello');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'initial commit',
        ], workingDirectory: tempDir.path);

        final headSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();
        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = PrContext(
          workingDir: tempDir.path,
          prNumber: '1',
          owner: 'testowner',
          repo: 'testrepo',
        );

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
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.name',
          'Test User',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.email',
          'test@example.com',
        ], workingDirectory: tempDir.path);

        File(p.join(tempDir.path, 'file1.txt')).writeAsStringSync('first');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'commit 1',
        ], workingDirectory: tempDir.path);
        final firstCommitSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        File(p.join(tempDir.path, 'file2.txt')).writeAsStringSync('second');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'commit 2',
        ], workingDirectory: tempDir.path);
        final secondCommitSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = PrContext(
          workingDir: tempDir.path,
          prNumber: '1',
          owner: 'testowner',
          repo: 'testrepo',
        );

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
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.name',
          'Test User',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.email',
          'test@example.com',
        ], workingDirectory: tempDir.path);

        File(p.join(tempDir.path, 'file1.txt')).writeAsStringSync('first');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'commit 1',
        ], workingDirectory: tempDir.path);
        final firstCommitSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        File(p.join(tempDir.path, 'file2.txt')).writeAsStringSync('second');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'commit 2',
        ], workingDirectory: tempDir.path);
        final secondCommitSha = (await runCommand('git', [
          'rev-parse',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

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

        final context = PrContext(
          workingDir: tempDir.path,
          prNumber: '1',
          owner: 'testowner',
          repo: 'testrepo',
        );

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
      await runCommand('git', ['init'], workingDirectory: tempDir.path);
      await runCommand('git', [
        'config',
        'user.name',
        'Test User',
      ], workingDirectory: tempDir.path);
      await runCommand('git', [
        'config',
        'user.email',
        'test@example.com',
      ], workingDirectory: tempDir.path);

      final context = PrContext(
        workingDir: tempDir.path,
        prNumber: '1',
        owner: 'testowner',
        repo: 'testrepo',
      );

      final status = await fetchPrSyncStatus(
        context,
        remoteBranch: 'main',
        remoteHeadSha: '',
      );

      expect(status.isSynced, isFalse);
      expect(status.syncState, equals('unknown'));
      expect(status.warning, contains('Could not determine'));
    });

    test(
      'returns behind_remote when remote commit is not found in local repo',
      () async {
        await runCommand('git', ['init'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.name',
          'Test User',
        ], workingDirectory: tempDir.path);
        await runCommand('git', [
          'config',
          'user.email',
          'test@example.com',
        ], workingDirectory: tempDir.path);

        File(p.join(tempDir.path, 'file1.txt')).writeAsStringSync('first');
        await runCommand('git', ['add', '.'], workingDirectory: tempDir.path);
        await runCommand('git', [
          'commit',
          '-m',
          'commit 1',
        ], workingDirectory: tempDir.path);

        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = PrContext(
          workingDir: tempDir.path,
          prNumber: '1',
          owner: 'testowner',
          repo: 'testrepo',
        );

        // Simulated remote commit SHA that does not exist in local repo object store
        const nonExistentSha = '0123456789abcdef0123456789abcdef01234567';

        final status = await fetchPrSyncStatus(
          context,
          remoteBranch: currentBranch,
          remoteHeadSha: nonExistentSha,
        );

        expect(status.isSynced, isFalse);
        expect(status.syncState, equals('behind_remote'));
        expect(status.warning, contains('was not found locally'));
      },
    );
  });
}
