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

    // Validate active local branch matches PR head branch.
    final prHeadBranch = prData['headRefName']?.toString();
    String activeBranch;
    try {
      activeBranch = (await runCommand('git', [
        'symbolic-ref',
        '--short',
        'HEAD',
      ], workingDirectory: workingDir)).trim();
    } catch (_) {
      activeBranch = '';
    }

    if (activeBranch.isNotEmpty &&
        prHeadBranch != null &&
        activeBranch != prHeadBranch) {
      stdout.writeln(
        '\nWARNING: Active local branch is "$activeBranch", but the PR branch is "$prHeadBranch".\n'
        'Please ensure you are on the correct branch before making edits. You can checkout this PR by running:\n'
        '  gh pr checkout $prNumber\n',
      );
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
    final report = StringBuffer('''
# PR Triage Report: #${prData['number']} - ${prData['title']}

**URL**: [PR #${prData['number']}](${prData['url']})
**Branch**: `${prData['headRefName']}`
**Commit**: `${prData['headRefOid']}`
**Review Decision**: `${prData['reviewDecision']}`
**Mergeable**: `${prData['mergeable']}`

## Unresolved Review Comments (${unresolvedThreads.length})

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
