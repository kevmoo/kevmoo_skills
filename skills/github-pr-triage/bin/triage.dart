import 'dart:convert';
import 'dart:io';

import '../lib/github_cli.dart';

/// Main entry point for the PR triage tool.
///
/// This script retrieves the status, unresolved review comments, and CI check
/// run failures for a specific GitHub Pull Request and outputs a structured
/// markdown triage report.
///
/// ### CLI Arguments:
/// - `-p`, `--pr` (or positional): The PR number (e.g., `123`) or a GitHub PR URL
///   (e.g., `https://github.com/owner/repo/pull/123`).
/// - `-C`, `--dir`: Path to the target git repository directory to run git/gh against.
///   Defaults to the current working directory.
///
/// ### Workflow Lifecycle:
/// 1. **Parse Arguments**: Resolves target directory and PR input.
/// 2. **Auto-detection**: If no PR is explicitly specified, it detects the current
///    git branch and queries GitHub for any associated open pull request.
/// 3. **Repo Verification**: If a PR URL is provided, it validates that the URL
///    matches the local repository configured in the target directory (exits on mismatch).
/// 4. **Details Fetching**: Retrieves PR title, state, mergeable status, etc.
/// 5. **Branch Verification**: Warns the user/agent if the active local branch does not
///    match the PR's source branch, suggesting how to checkout the correct branch.
/// 6. **Unresolved Comments Fetching**: Uses a GitHub GraphQL query to extract only
///    unresolved threads and comments.
/// 7. **CI/CD Checks Triage**: Identifies failed status checks and uses `gh run view`
///    to fetch logs for the failed steps (if they are GitHub Actions).
/// 8. **Report Generation**: Consolidates the results into a markdown format printed to stdout.
void main(List<String> args) async {
  try {
    final contextArgs = <String>[];
    final remainingArgs = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--pr' || arg == '-p' || arg == '--dir' || arg == '-C') {
        if (i + 1 < args.length) {
          contextArgs.add(arg);
          contextArgs.add(args[++i]);
        } else {
          stderr.writeln('Error: Missing value for option "$arg"');
          exit(1);
        }
      } else {
        remainingArgs.add(arg);
      }
    }

    final resolveIndex = remainingArgs.indexOf('resolve');
    if (resolveIndex != -1) {
      contextArgs.addAll(remainingArgs.sublist(0, resolveIndex));
      final subArgs = remainingArgs.sublist(resolveIndex + 1);
      final resolvePositional = <String>[];

      for (var i = 0; i < subArgs.length; i++) {
        final arg = subArgs[i];
        if (arg == '--pr' || arg == '-p' || arg == '--dir' || arg == '-C') {
          if (i + 1 < subArgs.length) {
            contextArgs.add(arg);
            contextArgs.add(subArgs[++i]);
          } else {
            stderr.writeln('Error: Missing value for option "$arg"');
            exit(1);
          }
        } else {
          resolvePositional.add(arg);
        }
      }

      if (resolvePositional.length != 1 && resolvePositional.length != 3) {
        stderr.writeln(
          'Error: Invalid arguments for resolve subcommand.\n'
          'Usage:\n'
          '  dart triage.dart resolve <thread_id>\n'
          '  dart triage.dart resolve <thread_id> <comment_id> "<body_text>"',
        );
        exit(1);
      }
      final threadId = resolvePositional[0];
      final commentId = resolvePositional.length == 3
          ? resolvePositional[1]
          : null;
      final bodyText = resolvePositional.length == 3
          ? resolvePositional[2]
          : null;

      if (commentId != null && !RegExp(r'^\d+$').hasMatch(commentId)) {
        stderr.writeln('Error: <comment_id> must be a numeric database ID.');
        exit(1);
      }
      if (bodyText != null && bodyText.trim().isEmpty) {
        stderr.writeln('Error: <body_text> cannot be empty.');
        exit(1);
      }

      final context = await resolvePrContext(
        contextArgs,
        onFail: (msg) {
          stderr.writeln('Error: $msg');
          exit(1);
        },
      );

      if (commentId != null && bodyText != null) {
        stdout.writeln(
          'Replying to comment $commentId and resolving thread $threadId...',
        );
      } else {
        stdout.writeln('Resolving thread $threadId...');
      }

      await replyAndResolveThread(
        context,
        threadId: threadId,
        commentId: commentId,
        body: bodyText,
      );
      stdout.writeln('Successfully resolved thread $threadId.');
      return;
    }

    final context = await resolvePrContext(
      args,
      onFail: (msg) {
        stderr.writeln('Error: $msg');
        exit(1);
      },
    );

    final workingDir = context.workingDir;
    final prNumber = context.prNumber;
    final owner = context.owner;
    final repo = context.repo;

    final repoArgs = ['-R', '$owner/$repo'];

    // 4. Fetch PR details.
    stdout.writeln('Fetching details for PR #$prNumber from $owner/$repo...');
    stdout.writeln('Target directory: $workingDir');
    final viewOutput = await runCommand('gh', [
      ...repoArgs,
      'pr',
      'view',
      prNumber,
      '--json',
      'number,title,state,reviewDecision,mergeable,headRefName,headRefOid,url',
    ], workingDirectory: workingDir);
    final prData = jsonDecode(viewOutput) as Map<String, dynamic>;

    // Validate local vs remote sync status using shared helper.
    final syncStatus = await fetchPrSyncStatus(
      context,
      remoteBranch: prData['headRefName']?.toString(),
      remoteHeadSha: prData['headRefOid']?.toString(),
    );

    if (syncStatus.warning != null) {
      stdout.writeln('\nWARNING: ${syncStatus.warning}\n');
    }

    // 5. Fetch unresolved review comments using unified GraphQL helper.
    stdout.writeln('Fetching unresolved review comments...');
    final graphData = await fetchPrGraphQLData(context);
    final unresolvedThreads = graphData.reviewThreads
        .where((t) => !t.isResolved)
        .toList();

    // 6. Fetch CI check runs using unified checks helper.
    stdout.writeln('Fetching check runs...');
    final checks = await fetchPrChecks(context);
    final failedChecks = checks.where((c) => c.isFail).toList();
    final pendingChecks = checks.where((c) => c.isPending).toList();

    // 7. Fetch logs for failed check runs (if they are GitHub Actions).
    final checkLogs = <String, String>{};
    for (final check in failedChecks) {
      final link = check.link;
      final checkName = check.name;
      final match = RegExp(r'/actions/runs/(\d+)').firstMatch(link);
      if (match != null) {
        final runId = match.group(1)!;
        stdout.writeln(
          'Fetching failed logs for check "$checkName" (Run ID: $runId)...',
        );
        try {
          final logOutput = await runCommand('gh', [
            ...repoArgs,
            'run',
            'view',
            runId,
            '--log-failed',
          ], workingDirectory: workingDir);
          checkLogs[checkName] = _truncateLog(logOutput);
        } catch (e) {
          checkLogs[checkName] = 'Failed to fetch logs: $e';
        }
      } else {
        checkLogs[checkName] =
            'Non-GitHub Actions run. Inspect details at: $link';
      }
    }

    // 8. Generate and output the markdown report.
    final syncWarningBlock = syncStatus.warning != null
        ? '> [!WARNING]\n> ${syncStatus.warning}\n\n'
        : '';

    final report = StringBuffer('''
# PR Triage Report: #${prData['number']} - ${prData['title']}

**URL**: [PR #${prData['number']}](${prData['url']})
**Branch**: `${prData['headRefName']}`
**Remote Commit**: `${prData['headRefOid']}`
**Local Commit**: `${syncStatus.localHeadSha.isEmpty ? 'N/A' : syncStatus.localHeadSha}`
**Sync Status**: `${syncStatus.syncState}`${syncStatus.isSynced ? ' ✅' : ' ⚠️'}
**Review Decision**: `${prData['reviewDecision']}`
**Mergeable**: `${prData['mergeable']}`

$syncWarningBlock## Unresolved Review Comments (${unresolvedThreads.length})

''');

    if (unresolvedThreads.isEmpty) {
      report.write('No unresolved review comments found! 🎉\n\n');
    } else {
      for (var i = 0; i < unresolvedThreads.length; i++) {
        final thread = unresolvedThreads[i];
        final commentsList = thread.comments;
        if (commentsList.isEmpty) continue;

        final threadId = thread.id;
        final firstComment = commentsList.first;
        final commentDbId = firstComment.databaseId;
        final path = firstComment.path;
        final line = firstComment.line;
        final url = firstComment.url;

        final commentsMarkdown = commentsList
            .map((comment) {
              final author = comment.author;
              final body = comment.body;
              final date = comment.createdAt;
              return '''
**@$author** ($date):
> ${body.replaceAll('\n', '\n> ')}''';
            })
            .join('\n\n');

        report.write('''
### Comment #${i + 1} (Thread `$threadId`, Comment `$commentDbId`): `$path` (Line $line)
Link: $url

$commentsMarkdown

---

''');
      }
    }

    report.write('## Failed Status Checks (${failedChecks.length})\n\n');
    if (failedChecks.isEmpty) {
      report.write('All checks passing! ✅\n\n');
    } else {
      for (final check in failedChecks) {
        final name = check.name;
        final link = check.link;
        report.write('''
### ❌ $name
Link: $link

```text
${checkLogs[name] ?? 'No logs available.'}
```

''');
      }
    }

    if (pendingChecks.isNotEmpty) {
      report.write(
        '## Active/Pending Status Checks (${pendingChecks.length}) ⏳\n\n',
      );
      for (final check in pendingChecks) {
        final name = check.name;
        final link = check.link;
        report.write('- ⏳ **$name**: [Inspect Check Run]($link)\n');
      }
      report.write('\n');
    }

    stdout.writeln('\n================== REPORT ==================\n');
    stdout.write(report.toString());
  } catch (e, stack) {
    stderr.writeln('Error during triage: $e');
    stderr.writeln(stack);
    exit(1);
  }
}

String _truncateLog(String log) {
  final lines = log.split('\n');
  if (lines.length <= 100) return log;
  final head = lines.take(15).join('\n');
  final tail = lines.sublist(lines.length - 85).join('\n');
  return '$head\n\n... [TRUNCATED ${lines.length - 100} LINES] ...\n\n$tail';
}
