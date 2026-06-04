import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  try {
    // 1. Parse CLI arguments.
    String? prInput;
    for (var i = 0; i < args.length; i++) {
      if ((args[i] == '--pr' || args[i] == '-p') && i + 1 < args.length) {
        prInput = args[i + 1];
        break;
      } else if (!args[i].startsWith('-')) {
        prInput = args[i];
      }
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
      final branch = (await runCommand('git', [
        'symbolic-ref',
        '--short',
        'HEAD',
      ])).trim();
      if (branch == 'main' || branch == 'master') {
        stderr.writeln(
          'Active branch is "$branch". Please specify a target PR number or URL.',
        );
        exit(1);
      }

      final listOutput = await runCommand('gh', [
        'pr',
        'list',
        '--head',
        branch,
        '--json',
        'number,url',
      ]);
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
    if (owner == null || repo == null) {
      final repoOutput = await runCommand('gh', [
        'repo',
        'view',
        '--json',
        'owner,name',
      ]);
      final repoData = jsonDecode(repoOutput) as Map<String, dynamic>;
      owner ??= (repoData['owner'] as Map<String, dynamic>)['login'] as String;
      repo ??= repoData['name'] as String;
    }

    final repoArgs = ['-R', '$owner/$repo'];

    // 4. Fetch PR details.
    stdout.writeln('Fetching details for PR #$prNumber from $owner/$repo...');
    final viewOutput = await runCommand('gh', [
      ...repoArgs,
      'pr',
      'view',
      prNumber,
      '--json',
      'number,title,state,reviewDecision,mergeable,headRefName,headRefOid,url',
    ]);
    final prData = jsonDecode(viewOutput) as Map<String, dynamic>;

    // 5. Fetch unresolved review comments.
    stdout.writeln('Fetching unresolved review comments...');
    const query = r'''
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              isResolved
              comments(first: 100) {
                nodes {
                  author { login }
                  body
                  path
                  line
                  originalLine
                  createdAt
                }
              }
            }
          }
        }
      }
    }
    ''';

    final graphqlResponse = await runCommand('gh', [
      'api',
      'graphql',
      '-F',
      'owner=$owner',
      '-F',
      'repo=$repo',
      '-F',
      'pr=$prNumber',
      '-f',
      'query=$query',
    ]);

    final parsedGraphql = jsonDecode(graphqlResponse) as Map<String, dynamic>;
    final threads =
        parsedGraphql['data']?['repository']?['pullRequest']?['reviewThreads']?['nodes']
            as List<dynamic>? ??
        [];
    final unresolvedThreads = threads
        .where((t) => t['isResolved'] == false)
        .toList();

    // 6. Fetch CI check runs.
    stdout.writeln('Fetching check runs...');
    final checksOutput = await runCommand('gh', [
      ...repoArgs,
      'pr',
      'checks',
      prNumber,
      '--json',
      'name,state,bucket,link,workflow',
    ]);
    final checks = jsonDecode(checksOutput) as List<dynamic>;
    final failedChecks = checks.where((c) => c['bucket'] == 'fail').toList();

    // 7. Fetch logs for failed check runs (if they are GitHub Actions).
    final checkLogs = <String, String>{};
    for (final check in failedChecks) {
      final link = check['link'] as String? ?? '';
      final checkName = check['name'] as String? ?? 'Unknown Check';
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
          ]);
          checkLogs[checkName] = truncateLog(logOutput);
        } catch (e) {
          checkLogs[checkName] = 'Failed to fetch logs: $e';
        }
      } else {
        checkLogs[checkName] =
            'Non-GitHub Actions run. Inspect details at: $link';
      }
    }

    // 7. Generate and output the markdown report.
    final report = StringBuffer();
    report.writeln(
      '# PR Triage Report: #${prData['number']} - ${prData['title']}',
    );
    report.writeln();
    report.writeln('**URL**: [PR #${prData['number']}](${prData['url']})');
    report.writeln('**Branch**: `${prData['headRefName']}`');
    report.writeln('**Commit**: `${prData['headRefOid']}`');
    report.writeln('**Review Decision**: `${prData['reviewDecision']}`');
    report.writeln('**Mergeable**: `${prData['mergeable']}`');
    report.writeln();

    report.writeln(
      '## Unresolved Review Comments (${unresolvedThreads.length})',
    );
    report.writeln();
    if (unresolvedThreads.isEmpty) {
      report.writeln('No unresolved review comments found! 🎉');
    } else {
      for (var i = 0; i < unresolvedThreads.length; i++) {
        final thread = unresolvedThreads[i];
        final commentsList =
            thread['comments']?['nodes'] as List<dynamic>? ?? [];
        if (commentsList.isEmpty) continue;

        final firstComment = commentsList.first;
        final path = firstComment['path'] ?? 'Unknown File';
        final line =
            firstComment['line'] ?? firstComment['originalLine'] ?? 'N/A';

        report.writeln('### Comment #${i + 1}: `$path` (Line $line)');
        report.writeln();
        for (final comment in commentsList) {
          final author = comment['author']?['login'] ?? 'ghost';
          final body = comment['body'] as String? ?? '';
          final date = comment['createdAt'] as String? ?? '';
          report.writeln('**@$author** ($date):');
          report.writeln('> ${body.replaceAll('\n', '\n> ')}');
          report.writeln();
        }
        report.writeln('---');
        report.writeln();
      }
    }

    report.writeln('## Failed Status Checks (${failedChecks.length})');
    report.writeln();
    if (failedChecks.isEmpty) {
      report.writeln('All checks passing! ✅');
    } else {
      for (final check in failedChecks) {
        final name = check['name'] ?? 'Unknown Check';
        final link = check['link'] ?? '';
        report.writeln('### ❌ $name');
        report.writeln('Link: $link');
        report.writeln();
        report.writeln('```text');
        report.writeln(checkLogs[name] ?? 'No logs available.');
        report.writeln('```');
        report.writeln();
      }
    }

    stdout.writeln('\n================== REPORT ==================\n');
    stdout.write(report.toString());
  } catch (e, stack) {
    stderr.writeln('Error during triage: $e');
    stderr.writeln(stack);
    exit(1);
  }
}

Future<String> runCommand(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
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

String truncateLog(String log) {
  final lines = log.split('\n');
  if (lines.length <= 100) return log;
  final head = lines.take(15).join('\n');
  final tail = lines.sublist(lines.length - 85).join('\n');
  return '$head\n\n... [TRUNCATED ${lines.length - 100} LINES] ...\n\n$tail';
}
