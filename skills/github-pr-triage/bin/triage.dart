import 'dart:convert';
import 'dart:io';

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
    // 1. Parse CLI arguments.
    String? prInput;
    String? targetDir;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--pr' || arg == '-p') {
        if (i + 1 < args.length) {
          prInput = args[i + 1];
          i++;
        } else {
          stderr.writeln('Error: Missing value for option "$arg"');
          exit(1);
        }
      } else if (arg == '--dir' || arg == '-C') {
        if (i + 1 < args.length) {
          targetDir = args[i + 1];
          i++;
        } else {
          stderr.writeln('Error: Missing value for option "$arg"');
          exit(1);
        }
      } else if (arg.startsWith('-')) {
        stderr.writeln('Error: Unknown option "$arg"');
        exit(1);
      } else {
        prInput = arg;
      }
    }

    final workingDir = targetDir != null
        ? Directory(targetDir).absolute.path
        : Directory.current.absolute.path;
    if (!await Directory(workingDir).exists()) {
      stderr.writeln('Error: Target directory "$workingDir" does not exist.');
      exit(1);
    }

    String? prNumber;
    String? owner;
    String? repo;

    if (prInput != null) {
      final prUrlMatch = RegExp(
        r'github\.com/([^/]+)/([^/]+)/pull/(\d+)',
      ).firstMatch(prInput);
      if (prUrlMatch != null) {
        owner = prUrlMatch.group(1);
        repo = prUrlMatch.group(2);
        prNumber = prUrlMatch.group(3);
      } else if (RegExp(r'^\d+$').hasMatch(prInput)) {
        prNumber = prInput;
      } else {
        stderr.writeln(
          'Invalid PR argument. Please provide a PR number or a GitHub PR URL.',
        );
        exit(1);
      }
    }

    // 2. Auto-detect PR from current branch if not provided.
    if (prNumber == null) {
      String branch;
      try {
        branch = (await _runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: workingDir)).trim();
      } catch (_) {
        branch = '';
      }
      if (branch.isEmpty || branch == 'main' || branch == 'master') {
        stderr.writeln(
          'Active branch is ${branch.isEmpty ? 'detached HEAD' : '"$branch"'}. Please specify a target PR number or URL.',
        );
        exit(1);
      }

      final listOutput = await _runCommand('gh', [
        'pr',
        'list',
        '--head',
        branch,
        '--json',
        'number,url',
      ], workingDirectory: workingDir);
      final listJson = jsonDecode(listOutput) as List<dynamic>;
      if (listJson.isEmpty) {
        stderr.writeln(
          'No open PR found for branch "$branch". Please specify a PR number or URL.',
        );
        exit(1);
      }
      prNumber = listJson[0]['number'].toString();
    }

    // 3. Resolve owner and repo for context.
    // 3. Resolve owner and repo for context.
    String? localOwner;
    String? localRepo;
    try {
      final repoOutput = await _runCommand('gh', [
        'repo',
        'view',
        '--json',
        'owner,name',
      ], workingDirectory: workingDir);
      final repoData = jsonDecode(repoOutput) as Map<String, dynamic>;
      final ownerData = repoData['owner'];
      if (ownerData is Map) {
        localOwner = ownerData['login']?.toString();
      }
      localRepo = repoData['name']?.toString();
    } catch (_) {
      // Not a valid git repository or gh configuration not found.
    }

    if (owner == null || repo == null) {
      owner = localOwner;
      repo = localRepo;
    } else if (localOwner != null && localRepo != null) {
      if (localOwner.toLowerCase() != owner.toLowerCase() ||
          localRepo.toLowerCase() != repo.toLowerCase()) {
        stderr.writeln(
          'Error: The target directory "$workingDir" is for repository "$localOwner/$localRepo", '
          'but the specified PR is for repository "$owner/$repo".',
        );
        exit(1);
      }
    }

    if (owner == null || repo == null) {
      stderr.writeln(
        'Error: Could not resolve GitHub repository owner or name.',
      );
      exit(1);
    }

    final repoArgs = ['-R', '$owner/$repo'];

    // 4. Fetch PR details.
    stdout.writeln('Fetching details for PR #$prNumber from $owner/$repo...');
    stdout.writeln('Target directory: $workingDir');
    final viewOutput = await _runCommand('gh', [
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
      activeBranch = (await _runCommand('git', [
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

    // 5. Fetch unresolved review comments.
    stdout.writeln('Fetching unresolved review comments...');
    const query = r'''
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 100) {
                nodes {
                  databaseId
                  author { login }
                  body
                  path
                  line
                  originalLine
                  createdAt
                  url
                }
              }
            }
          }
        }
      }
    }
    ''';

    final graphqlResponse = await _runCommand('gh', [
      'api',
      'graphql',
      '-f',
      'owner=$owner',
      '-f',
      'repo=$repo',
      '-F',
      'pr=$prNumber',
      '-f',
      'query=$query',
    ], workingDirectory: workingDir);

    final parsedGraphql = jsonDecode(graphqlResponse) as Map<String, dynamic>;
    if (parsedGraphql['errors'] != null) {
      stderr.writeln('GraphQL errors returned from GitHub API:');
      stderr.writeln(jsonEncode(parsedGraphql['errors']));
      exit(1);
    }
    final threads =
        parsedGraphql['data']?['repository']?['pullRequest']?['reviewThreads']?['nodes']
            as List<dynamic>? ??
        [];
    final unresolvedThreads = threads
        .where((t) => t['isResolved'] == false)
        .toList();

    // 6. Fetch CI check runs.
    stdout.writeln('Fetching check runs...');
    var failedChecks = <dynamic>[];
    var pendingChecks = <dynamic>[];
    try {
      final checksOutput = await _runCommand('gh', [
        ...repoArgs,
        'pr',
        'checks',
        prNumber,
        '--json',
        'name,state,bucket,link,workflow',
      ], workingDirectory: workingDir);
      final checks = jsonDecode(checksOutput) as List<dynamic>;
      failedChecks = checks.where((c) => c['bucket'] == 'fail').toList();
      pendingChecks = checks.where((c) => c['bucket'] == 'pending').toList();
    } catch (e) {
      if (e is ProcessException && e.message.contains('no checks reported')) {
        stdout.writeln('No checks reported for this PR.');
      } else {
        rethrow;
      }
    }

    // 7. Fetch logs for failed check runs (if they are GitHub Actions).
    final checkLogs = <String, String>{};
    for (final check in failedChecks) {
      final link = check['link']?.toString() ?? '';
      final checkName = check['name']?.toString() ?? 'Unknown Check';
      final match = RegExp(r'/actions/runs/(\d+)').firstMatch(link);
      if (match != null) {
        final runId = match.group(1)!;
        stdout.writeln(
          'Fetching failed logs for check "$checkName" (Run ID: $runId)...',
        );
        try {
          final logOutput = await _runCommand('gh', [
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

    // 7. Generate and output the markdown report.
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
        final commentsList =
            thread['comments']?['nodes'] as List<dynamic>? ?? [];
        if (commentsList.isEmpty) continue;

        final threadId = thread['id']?.toString() ?? 'Unknown Thread';
        final firstComment = commentsList.first;
        final commentDbId =
            firstComment['databaseId']?.toString() ?? 'Unknown Comment';
        final path = firstComment['path'] ?? 'Unknown File';
        final line =
            firstComment['line'] ?? firstComment['originalLine'] ?? 'N/A';
        final url = firstComment['url']?.toString() ?? '';

        final commentsMarkdown = commentsList
            .map((comment) {
              final author = comment['author']?['login']?.toString() ?? 'ghost';
              final body = comment['body']?.toString() ?? '';
              final date = comment['createdAt']?.toString() ?? '';
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
        final name = check['name'] ?? 'Unknown Check';
        final link = check['link'] ?? '';
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
        final name = check['name'] ?? 'Unknown Check';
        final link = check['link'] ?? '';
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

Future<String> _runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString();
}

String _truncateLog(String log) {
  final lines = log.split('\n');
  if (lines.length <= 100) return log;
  final head = lines.take(15).join('\n');
  final tail = lines.sublist(lines.length - 85).join('\n');
  return '$head\n\n... [TRUNCATED ${lines.length - 100} LINES] ...\n\n$tail';
}
