import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../lib/github_cli.dart';

/// Main entry point for the PR triage tool.
///
/// This script retrieves the status, unresolved review comments, and CI check
/// run failures for a specific GitHub Pull Request and outputs a structured
/// markdown triage report.
ArgParser _buildParser() {
  final parser = buildPrContextArgParser();
  parser.addCommand('resolve', buildPrContextArgParser());
  return parser;
}

void main(List<String> args) async {
  final parser = _buildParser();
  final results = _parseArgs(args, parser);

  if (results.flag('help') || results.command?.flag('help') == true) {
    _printUsageAndExit(parser);
  }

  try {
    await _runTriage(results);
  } catch (e, stack) {
    stderr.writeln('Error during triage: $e');
    stderr.writeln(stack);
    exit(1);
  }
}

ArgResults _parseArgs(List<String> args, ArgParser parser) {
  try {
    return parser.parse(args);
  } on FormatException catch (e) {
    _exitWithError(e.message);
  }
}

Never _printUsageAndExit(ArgParser parser) {
  stdout.writeln('GitHub PR Triage Tool\n');
  stdout.writeln(
    'Usage:\n'
    '  dart run triage.dart [options]\n'
    '  dart run triage.dart resolve <thread_id> [<comment_id> "<body_text>"]\n',
  );
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  exit(0);
}

Never _exitWithError(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}

Future<void> _runTriage(ArgResults results) async {
  final resolveCmd = results.command;
  if (resolveCmd != null && resolveCmd.name == 'resolve') {
    await _handleResolveCommand(results, resolveCmd);
    return;
  }

  final targetDir = results.option('dir');
  final prInput =
      results.option('pr') ??
      (results.rest.isNotEmpty ? results.rest.first : null);

  final context = await resolvePrContextFromArgs(
    prInput: prInput,
    targetDir: targetDir,
    onFail: _exitWithError,
  );

  final (data, conflictAnalysis) = await _fetchTriageData(context);
  final report = buildTriageReport(data, conflictAnalysis: conflictAnalysis);

  stdout.writeln('\n================== REPORT ==================\n');
  stdout.write(report);
}

({String threadId, String? commentId, String? bodyText}) _parseResolveArgs(
  List<String> positional,
) {
  final (threadId, commentId, bodyText) = switch (positional) {
    [final t] => (t, null, null),
    [final t, final c, final b] => (t, c, b),
    _ => _exitWithError(
      'Invalid arguments for resolve subcommand.\n'
      'Usage:\n'
      '  dart run triage.dart resolve <thread_id>\n'
      '  dart run triage.dart resolve <thread_id> <comment_id> "<body_text>"',
    ),
  };

  if (commentId != null && !RegExp(r'^\d+$').hasMatch(commentId)) {
    _exitWithError('<comment_id> must be a numeric database ID.');
  }
  if (bodyText != null && bodyText.trim().isEmpty) {
    _exitWithError('<body_text> cannot be empty.');
  }

  return (threadId: threadId, commentId: commentId, bodyText: bodyText);
}

Future<void> _handleResolveCommand(
  ArgResults results,
  ArgResults resolveCmd,
) async {
  final parsed = _parseResolveArgs(resolveCmd.rest);
  final targetDir = resolveCmd.option('dir') ?? results.option('dir');
  final prInput = resolveCmd.option('pr') ?? results.option('pr');

  final context = await resolvePrContextFromArgs(
    prInput: prInput,
    targetDir: targetDir,
    onFail: _exitWithError,
  );

  if (parsed.commentId != null && parsed.bodyText != null) {
    stdout.writeln(
      'Replying to comment ${parsed.commentId} and resolving thread ${parsed.threadId}...',
    );
  } else {
    stdout.writeln('Resolving thread ${parsed.threadId}...');
  }

  await replyAndResolveThread(
    context,
    threadId: parsed.threadId,
    commentId: parsed.commentId,
    body: parsed.bodyText,
  );
  stdout.writeln('Successfully resolved thread ${parsed.threadId}.');
}

typedef TriageData = ({
  Map<String, dynamic> prData,
  PrSyncStatus syncStatus,
  List<PrReviewThread> unresolvedThreads,
  List<PrReview> reviewComments,
  List<PrComment> generalComments,
  List<PrCheckRun> failedChecks,
  List<PrCheckRun> pendingChecks,
  Map<String, String> checkLogs,
});

Future<(TriageData, PrConflictAnalysis)> _fetchTriageData(
  PrContext context,
) async {
  stdout.writeln(
    'Fetching details for PR #${context.prNumber} from ${context.owner}/${context.repo}...',
  );
  stdout.writeln('Target directory: ${context.workingDir}');
  final viewOutput = await runCommand('gh', [
    '-R',
    '${context.owner}/${context.repo}',
    'pr',
    'view',
    context.prNumber,
    '--json',
    'number,title,state,reviewDecision,mergeable,mergeStateStatus,baseRefName,headRefName,headRefOid,url',
  ], workingDirectory: context.workingDir);
  final prData = jsonDecode(viewOutput) as Map<String, dynamic>;

  final syncStatus = await fetchPrSyncStatus(
    context,
    remoteBranch: prData['headRefName']?.toString(),
    remoteHeadSha: prData['headRefOid']?.toString(),
  );

  if (syncStatus.warning != null) {
    stdout.writeln('\nWARNING: ${syncStatus.warning}\n');
  }

  final conflictAnalysis = await analyzePrConflicts(context, prData);
  if (conflictAnalysis.isConflicting) {
    stdout.writeln(
      '\nWARNING: PR #${context.prNumber} has MERGE CONFLICTS with '
      'origin/${conflictAnalysis.baseRefName}!\n',
    );
  }

  stdout.writeln('Fetching review comments and threads...');
  final graphData = await fetchPrGraphQLData(context);
  final unresolvedThreads = graphData.reviewThreads
      .where((t) => !t.isResolved)
      .toList();
  final reviewComments = graphData.reviews
      .where((r) => r.body.trim().isNotEmpty)
      .toList();
  final generalComments = graphData.comments
      .where((c) => c.body.trim().isNotEmpty)
      .toList();

  stdout.writeln('Fetching check runs...');
  final checks = await fetchPrChecks(context);
  final failedChecks = checks.where((c) => c.isFail).toList();
  final pendingChecks = checks.where((c) => c.isPending).toList();

  final checkLogs = await _fetchFailedCheckLogs(context, failedChecks);

  return (
    (
      prData: prData,
      syncStatus: syncStatus,
      unresolvedThreads: unresolvedThreads,
      reviewComments: reviewComments,
      generalComments: generalComments,
      failedChecks: failedChecks,
      pendingChecks: pendingChecks,
      checkLogs: checkLogs,
    ),
    conflictAnalysis,
  );
}

Future<Map<String, String>> _fetchFailedCheckLogs(
  PrContext context,
  List<PrCheckRun> failedChecks,
) async {
  final checkLogs = <String, String>{};
  for (final check in failedChecks) {
    final checkName = check.name;
    stdout.writeln('Fetching failed logs for check "$checkName"...');
    try {
      final logOutput = await fetchFailedCheckLog(context, check);
      checkLogs[checkName] = truncateLog(logOutput);
    } catch (e) {
      checkLogs[checkName] = 'Failed to fetch logs: $e';
    }
  }
  return checkLogs;
}

String buildTriageReport(
  TriageData data, {
  PrConflictAnalysis? conflictAnalysis,
}) {
  final prData = data.prData;
  final syncStatus = data.syncStatus;
  final mergeable = prData['mergeable']?.toString() ?? 'UNKNOWN';
  final mergeStateStatus = prData['mergeStateStatus']?.toString() ?? 'UNKNOWN';
  final baseRefName = prData['baseRefName']?.toString() ?? 'main';
  final headRefName = prData['headRefName']?.toString() ?? '';
  final conflict =
      conflictAnalysis ??
      (
        isConflicting:
            mergeable == 'CONFLICTING' || mergeStateStatus == 'DIRTY',
        mergeable: mergeable,
        mergeStateStatus: mergeStateStatus,
        baseRefName: baseRefName,
        headRefName: headRefName,
        conflictingFiles: const <String>[],
        conflictMessages: const <String>[],
        upstreamCommits: const <String>[],
      );
  final syncWarningBlock = syncStatus.warning != null
      ? '> [!WARNING]\n> ${syncStatus.warning}\n\n'
      : '';
  final conflictWarningBlock = conflict.isConflicting
      ? '> [!WARNING]\n'
            '> **MERGE CONFLICT BLOCKER**: This PR has merge conflicts with '
            '`origin/${conflict.baseRefName}` (`mergeable: ${conflict.mergeable}`, '
            '`mergeStateStatus: ${conflict.mergeStateStatus}`) and cannot be merged '
            'until resolved.\n\n'
      : '';
  final localCommit = syncStatus.localHeadSha.isEmpty
      ? 'N/A'
      : syncStatus.localHeadSha;
  final mergeableBadge = switch (conflict.mergeable) {
    'MERGEABLE' => '`MERGEABLE` ✅',
    'CONFLICTING' => '`CONFLICTING` ⚠️ (BLOCKER)',
    _ =>
      conflict.isConflicting
          ? '`${conflict.mergeable}` ⚠️ (`${conflict.mergeStateStatus}`)'
          : '`${prData['mergeable']}`',
  };

  final report = StringBuffer('''
# PR Triage Report: #${prData['number']} - ${prData['title']}

**URL**: [PR #${prData['number']}](${prData['url']})
**Branch**: `${prData['headRefName']}` ➔ `${conflict.baseRefName}`
**Remote Commit**: `${prData['headRefOid']}`
**Local Commit**: `$localCommit`
**Sync Status**: `${syncStatus.syncState}`${syncStatus.isSynced ? ' ✅' : ' ⚠️'}
**Review Decision**: `${prData['reviewDecision']}`
**Mergeable**: $mergeableBadge

$syncWarningBlock$conflictWarningBlock''');

  if (conflict.isConflicting) {
    _writeMergeConflictsSection(report, conflict);
  }
  _writeUnresolvedThreads(report, data.unresolvedThreads);
  _writeReviewComments(report, data.reviewComments);
  _writeConversationComments(report, data.generalComments);
  _writeFailedChecks(
    report,
    data.failedChecks,
    data.checkLogs,
    conflict: conflict,
  );
  _writePendingChecks(report, data.pendingChecks);

  return report.toString();
}

void _writeMergeConflictsSection(
  StringBuffer report,
  PrConflictAnalysis conflict,
) {
  final fileCount = conflict.conflictingFiles.length;
  final countLabel = fileCount > 0 ? '$fileCount conflicting files' : 'Blocker';
  report.write('## ⚠️ Merge Conflicts ($countLabel)\n\n');

  if (conflict.conflictingFiles.isNotEmpty) {
    report.write('### Conflicting Files\n');
    for (final file in conflict.conflictingFiles) {
      report.write('- `$file`\n');
    }
    report.write('\n');
  } else {
    report.write(
      'GitHub reports `mergeable: ${conflict.mergeable}` (`mergeStateStatus: ${conflict.mergeStateStatus}`) '
      'against `origin/${conflict.baseRefName}`.\n\n',
    );
  }

  if (conflict.upstreamCommits.isNotEmpty) {
    report.write(
      '### Conflicting Upstream Commits on `origin/${conflict.baseRefName}`\n',
    );
    for (final commit in conflict.upstreamCommits) {
      report.write('- `$commit`\n');
    }
    report.write('\n');
  }

  report.write('''
### Recommended Conflict Resolution (No Force-Push)
```bash
git fetch origin ${conflict.baseRefName}
git merge origin/${conflict.baseRefName}
```

''');
}

String _formatBlockquoteComment(String author, String timestamp, String body) =>
    '''
**@$author** ($timestamp):
> ${body.replaceAll('\n', '\n> ')}''';

void _writeMarkdownItem(
  StringBuffer report, {
  required String header,
  required String url,
  required String bodyMarkdown,
}) {
  report.write('''
### $header
Link: $url

$bodyMarkdown

---

''');
}

void _writeUnresolvedThreads(
  StringBuffer report,
  List<PrReviewThread> unresolvedThreads,
) {
  report.write(
    '## Unresolved Review Comments (${unresolvedThreads.length})\n\n',
  );
  if (unresolvedThreads.isEmpty) {
    report.write('No unresolved review comments found! 🎉\n\n');
    return;
  }

  for (var i = 0; i < unresolvedThreads.length; i++) {
    final thread = unresolvedThreads[i];
    if (thread.comments.isEmpty) continue;

    final first = thread.comments.first;
    final commentsMarkdown = thread.comments
        .map((c) => _formatBlockquoteComment(c.author, c.createdAt, c.body))
        .join('\n\n');

    _writeMarkdownItem(
      report,
      header:
          'Comment #${i + 1} (Thread `${thread.id}`, Comment `${first.databaseId}`): `${first.path}` (Line ${first.line})',
      url: first.url,
      bodyMarkdown: commentsMarkdown,
    );
  }
}

void _writeReviewComments(StringBuffer report, List<PrReview> reviewComments) {
  if (reviewComments.isEmpty) return;

  report.write('## Top-Level Review Comments (${reviewComments.length})\n\n');
  for (var i = 0; i < reviewComments.length; i++) {
    final review = reviewComments[i];
    _writeMarkdownItem(
      report,
      header:
          'Review #${i + 1} (Review `${review.id}`, Database ID `${review.databaseId}`): `${review.state}` by @${review.author}',
      url: review.url,
      bodyMarkdown: _formatBlockquoteComment(
        review.author,
        review.submittedAt,
        review.body,
      ),
    );
  }
}

void _writeConversationComments(
  StringBuffer report,
  List<PrComment> generalComments,
) {
  if (generalComments.isEmpty) return;

  report.write('## Conversation Comments (${generalComments.length})\n\n');
  for (var i = 0; i < generalComments.length; i++) {
    final comment = generalComments[i];
    _writeMarkdownItem(
      report,
      header:
          'Conversation Comment #${i + 1} (Comment `${comment.databaseId}`) by @${comment.author}',
      url: comment.url,
      bodyMarkdown: _formatBlockquoteComment(
        comment.author,
        comment.createdAt,
        comment.body,
      ),
    );
  }
}

void _writeFailedChecks(
  StringBuffer report,
  List<PrCheckRun> failedChecks,
  Map<String, String> checkLogs, {
  PrConflictAnalysis? conflict,
}) {
  report.write('## Failed Status Checks (${failedChecks.length})\n\n');
  if (failedChecks.isEmpty) {
    if (conflict != null && conflict.isConflicting) {
      report.write(
        'All CI checks passing (✅), but PR is **BLOCKED BY MERGE CONFLICTS** (⚠️) '
        'with `origin/${conflict.baseRefName}`!\n\n',
      );
    } else {
      report.write('All checks passing! ✅\n\n');
    }
    return;
  }

  for (final check in failedChecks) {
    report.write('''
### ❌ ${check.name}
Link: ${check.link}

```text
${checkLogs[check.name] ?? 'No logs available.'}
```

''');
  }
}

void _writePendingChecks(StringBuffer report, List<PrCheckRun> pendingChecks) {
  if (pendingChecks.isEmpty) return;

  report.write(
    '## Active/Pending Status Checks (${pendingChecks.length}) ⏳\n\n',
  );
  for (final check in pendingChecks) {
    report.write('- ⏳ **${check.name}**: [Inspect Check Run](${check.link})\n');
  }
  report.write('\n');
}

String truncateLog(String log) {
  final lines = log.split('\n');
  if (lines.length <= 100) return log;
  final head = lines.take(15).join('\n');
  final tail = lines.sublist(lines.length - 85).join('\n');
  return '$head\n\n... [TRUNCATED ${lines.length - 100} LINES] ...\n\n$tail';
}
