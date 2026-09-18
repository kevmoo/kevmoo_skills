import 'pr_context.dart';
export 'pr_context.dart'
    show
        PrContext,
        CommandRunner,
        runCommand,
        PrCheckRun,
        PrComment,
        PrReviewThread,
        PrReview,
        PrGraphData,
        fetchPrChecks,
        fetchPrGraphQLData;
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

final _digitsOnly = RegExp(r'^\d+$');
final _prUrlRegExp = RegExp(r'github\.com/([^/]+)/([^/]+)/pull/(\d+)');

ArgParser buildPrContextArgParser() {
  return ArgParser()
    ..addOption('pr', abbr: 'p', help: 'PR number or GitHub PR URL')
    ..addOption(
      'dir',
      abbr: 'C',
      help: 'Path to target git repository directory',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show CLI usage.');
}

/// Parses CLI arguments and resolves the [PrContext] for git operations.
Future<PrContext> resolvePrContext(
  List<String> args, {
  required Never Function(String message) onFail,
  CommandRunner runCommand = runCommand,
}) async {
  final parser = buildPrContextArgParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    onFail(e.message);
  }

  final targetDir = results.option('dir');
  final prInput =
      results.option('pr') ??
      (results.rest.isNotEmpty ? results.rest.first : null);

  return resolvePrContextFromArgs(
    prInput: prInput,
    targetDir: targetDir,
    onFail: onFail,
    runCommand: runCommand,
  );
}

/// Resolves [PrContext] from pre-parsed CLI inputs.
Future<PrContext> resolvePrContextFromArgs({
  String? prInput,
  String? targetDir,
  required Never Function(String message) onFail,
  CommandRunner runCommand = runCommand,
}) async {
  final workingDir = targetDir != null
      ? Directory(targetDir).absolute.path
      : Directory.current.absolute.path;
  if (!await Directory(workingDir).exists()) {
    onFail('Target directory "$workingDir" does not exist.');
  }

  final (owner, repo, parsedPrNumber) = _parsePrInput(prInput, onFail);
  final prNumber =
      parsedPrNumber ??
      await _detectPrNumberFromBranch(workingDir, onFail, runCommand);

  final (localOwner, localRepo) = await _resolveLocalRepoOwner(
    workingDir,
    runCommand,
  );
  final resolvedOwner = owner ?? localOwner;
  final resolvedRepo = repo ?? localRepo;

  if (resolvedOwner == null || resolvedRepo == null) {
    onFail('Failed to resolve repository owner and name.');
  }

  await _verifyRepoCompatibility(
    workingDir: workingDir,
    localOwner: localOwner,
    localRepo: localRepo,
    targetOwner: owner,
    targetRepo: repo,
    onFail: onFail,
    runCommand: runCommand,
  );

  return PrContext(
    workingDir: workingDir,
    prNumber: prNumber,
    owner: resolvedOwner,
    repo: resolvedRepo,
  );
}

(String? owner, String? repo, String? prNumber) _parsePrInput(
  String? prInput,
  Never Function(String message) onFail,
) {
  if (prInput == null) return (null, null, null);
  final prUrlMatch = _prUrlRegExp.firstMatch(prInput);
  if (prUrlMatch != null) {
    return (prUrlMatch.group(1), prUrlMatch.group(2), prUrlMatch.group(3));
  }
  if (_digitsOnly.hasMatch(prInput)) {
    return (null, null, prInput);
  }
  onFail('Invalid PR argument. Please provide a PR number or a GitHub PR URL.');
}

Future<void> _verifyRepoCompatibility({
  required String workingDir,
  required String? localOwner,
  required String? localRepo,
  required String? targetOwner,
  required String? targetRepo,
  required Never Function(String message) onFail,
  required CommandRunner runCommand,
}) async {
  if (localOwner == null ||
      localRepo == null ||
      targetOwner == null ||
      targetRepo == null) {
    return;
  }
  if (localRepo.toLowerCase() == targetRepo.toLowerCase()) {
    return;
  }
  final matchesRemote = await _hasGitRemote(
    workingDir,
    targetOwner,
    targetRepo,
    runCommand: runCommand,
  );
  if (!matchesRemote) {
    onFail(
      'The target directory "$workingDir" is for repository "$localOwner/$localRepo", '
      'but the specified PR is for repository "$targetOwner/$targetRepo".',
    );
  }
}

Future<bool> _hasGitRemote(
  String workingDir,
  String owner,
  String repo, {
  CommandRunner runCommand = runCommand,
}) async {
  try {
    final output = await runCommand('git', [
      'remote',
      '-v',
    ], workingDirectory: workingDir);
    final pattern = RegExp(
      '(?:[/:])${RegExp.escape(owner)}/${RegExp.escape(repo)}(?:\\.git|/|[\\s]|\$)',
      caseSensitive: false,
    );
    return output.split('\n').any(pattern.hasMatch);
  } catch (_) {
    return false;
  }
}

/// Extension getters for [PrCheckRun].
extension PrCheckRunExt on PrCheckRun {
  bool get isFail => bucket == 'fail';
  bool get isPending => bucket == 'pending';
}

/// Sync status information comparing local repository state to remote PR state.
typedef PrSyncStatus = ({
  String localBranch,
  String remoteBranch,
  String localHeadSha,
  String remoteHeadSha,
  bool isSynced,
  String syncState,
  String? warning,
});

/// Evaluates local git repository branch and commit SHA against the remote PR head branch and commit SHA.
Future<PrSyncStatus> fetchPrSyncStatus(
  PrContext context, {
  String? remoteBranch,
  String? remoteHeadSha,
  CommandRunner runCommand = runCommand,
}) async {
  final (rBranch, rHeadSha) = await _resolveRemoteBranchAndSha(
    context,
    remoteBranch: remoteBranch,
    remoteHeadSha: remoteHeadSha,
    runCommand: runCommand,
  );
  final localBranch = await _resolveLocalBranch(context.workingDir, runCommand);
  final localHeadSha = await _resolveLocalHeadSha(
    context.workingDir,
    runCommand,
  );

  PrSyncStatus buildStatus({
    required bool isSynced,
    required String syncState,
    required String? warning,
  }) => (
    localBranch: localBranch,
    remoteBranch: rBranch,
    localHeadSha: localHeadSha,
    remoteHeadSha: rHeadSha,
    isSynced: isSynced,
    syncState: syncState,
    warning: warning,
  );

  if (localBranch.isNotEmpty && rBranch.isNotEmpty && localBranch != rBranch) {
    return buildStatus(
      isSynced: false,
      syncState: 'branch_mismatch',
      warning:
          'Active local branch is "$localBranch", but the PR branch is "$rBranch". '
          'Please checkout the correct branch using: gh pr checkout ${context.prNumber}',
    );
  }

  if (localHeadSha.isEmpty || rHeadSha.isEmpty) {
    return buildStatus(
      isSynced: false,
      syncState: 'unknown',
      warning: localHeadSha.isEmpty
          ? 'Could not determine local HEAD commit SHA. Please ensure you are in a valid git repository.'
          : 'Could not determine remote PR head commit SHA. Please check network connection or GitHub CLI status.',
    );
  }

  if (localHeadSha == rHeadSha) {
    return buildStatus(isSynced: true, syncState: 'in_sync', warning: null);
  }

  final (syncState, warning) = await _compareDiffCommits(
    context.workingDir,
    localHeadSha: localHeadSha,
    remoteHeadSha: rHeadSha,
    runCommand: runCommand,
  );
  return buildStatus(isSynced: false, syncState: syncState, warning: warning);
}

Future<(String, String)> _resolveRemoteBranchAndSha(
  PrContext context, {
  required String? remoteBranch,
  required String? remoteHeadSha,
  required CommandRunner runCommand,
}) async {
  if (remoteBranch != null && remoteHeadSha != null) {
    return (remoteBranch, remoteHeadSha);
  }
  try {
    final viewOutput = await runCommand('gh', [
      '-R',
      '${context.owner}/${context.repo}',
      'pr',
      'view',
      context.prNumber,
      '--json',
      'headRefName,headRefOid',
    ], workingDirectory: context.workingDir);
    final prData = jsonDecode(viewOutput) as Map<String, dynamic>;
    return (
      remoteBranch ?? prData['headRefName']?.toString() ?? '',
      remoteHeadSha ?? prData['headRefOid']?.toString() ?? '',
    );
  } catch (_) {
    return (remoteBranch ?? '', remoteHeadSha ?? '');
  }
}

Future<String> _resolveLocalBranch(
  String workingDir,
  CommandRunner runCommand,
) async {
  try {
    return (await runCommand('git', [
      'symbolic-ref',
      '--short',
      'HEAD',
    ], workingDirectory: workingDir)).trim();
  } catch (_) {
    try {
      return (await runCommand('git', [
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], workingDirectory: workingDir)).trim();
    } catch (_) {
      return '';
    }
  }
}

Future<String> _resolveLocalHeadSha(
  String workingDir,
  CommandRunner runCommand,
) async {
  try {
    return (await runCommand('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: workingDir)).trim();
  } catch (_) {
    return '';
  }
}

Future<bool> _gitCheck(
  String workingDir,
  List<String> args,
  CommandRunner runCommand,
) async {
  try {
    await runCommand('git', args, workingDirectory: workingDir);
    return true;
  } catch (_) {
    return false;
  }
}

Future<(String syncState, String warning)> _compareDiffCommits(
  String workingDir, {
  required String localHeadSha,
  required String remoteHeadSha,
  required CommandRunner runCommand,
}) async {
  final remoteCommitExists = await _gitCheck(workingDir, [
    'cat-file',
    '-e',
    '$remoteHeadSha^{commit}',
  ], runCommand);
  if (!remoteCommitExists) {
    return (
      'not_fetched',
      'Remote PR commit ($remoteHeadSha) is not present in your local repository. '
          'Please run "git fetch" to update your local repository.',
    );
  }

  final isLocalAncestor = await _gitCheck(workingDir, [
    'merge-base',
    '--is-ancestor',
    localHeadSha,
    remoteHeadSha,
  ], runCommand);
  if (isLocalAncestor) {
    return (
      'behind_remote',
      'Local commit ($localHeadSha) is behind remote PR commit ($remoteHeadSha). '
          'Please pull remote changes before making edits.',
    );
  }

  final isRemoteAncestor = await _gitCheck(workingDir, [
    'merge-base',
    '--is-ancestor',
    remoteHeadSha,
    localHeadSha,
  ], runCommand);
  if (isRemoteAncestor) {
    return (
      'ahead_of_remote',
      'Local commit ($localHeadSha) is ahead of remote PR commit ($remoteHeadSha). '
          'Please push local commits to sync remote PR.',
    );
  }

  return (
    'diverged',
    'Local commit ($localHeadSha) and remote PR commit ($remoteHeadSha) have diverged. '
        'Please sync local and remote branches.',
  );
}

/// Extracts the workflow run ID from a GitHub Actions URL (e.g. `.../actions/runs/12345`).
String? parseRunIdFromLink(String link) {
  final rawSegments = Uri.tryParse(link)?.pathSegments ?? const [];
  final segments = rawSegments.where((s) => s.isNotEmpty).toList();
  final idx = segments.indexOf('runs');
  if (idx > 0 && segments[idx - 1] == 'actions' && idx + 1 < segments.length) {
    final candidate = segments[idx + 1];
    if (_digitsOnly.hasMatch(candidate)) return candidate;
  }
  return null;
}

/// Extracts the check run ID from a GitHub check run or job URL.
String? parseCheckRunIdFromLink(String link) {
  final rawSegments = Uri.tryParse(link)?.pathSegments ?? const [];
  final segments = rawSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  final last = segments.last;
  if (!_digitsOnly.hasMatch(last)) return null;

  final length = segments.length;
  if (length >= 2 && segments[length - 2] == 'check-runs') {
    return last;
  }

  if (length >= 3 &&
      (segments[length - 2] == 'job' || segments[length - 2] == 'jobs') &&
      segments.contains('actions') &&
      segments.contains('runs')) {
    return last;
  }

  if (length >= 2 &&
      segments[length - 2] == 'runs' &&
      !segments.contains('actions')) {
    return last;
  }

  return null;
}

/// Fetches logs and annotations for a failed status check.
///
/// Attempts to fetch job-level logs via `/actions/jobs/{job_id}/logs` and
/// check run annotations via `/check-runs/{check_run_id}/annotations` to
/// avoid failures when sibling workflow jobs are still in progress.
/// Falls back to `gh run view --log-failed` if job-level API calls fail.
Future<String> fetchFailedCheckLog(
  PrContext context,
  PrCheckRun check, {
  CommandRunner runCommand = runCommand,
}) async {
  final link = check.link;
  final runId = parseRunIdFromLink(link);
  final checkRunId = parseCheckRunIdFromLink(link);

  Future<String> ghRepoApi(String subpath) => runCommand('gh', [
    'api',
    '--allow-escape-sequences',
    'repos/${context.owner}/${context.repo}/$subpath',
  ], workingDirectory: context.workingDir);

  final annotations = await _fetchCheckRunAnnotations(checkRunId, ghRepoApi);
  final logBody = runId != null
      ? await _fetchActionsRunLog(
          context,
          runId,
          ghRepoApi: ghRepoApi,
          runCommand: runCommand,
        )
      : 'Non-GitHub Actions run. Inspect details at: $link';

  return _prependAnnotations(annotations, logBody);
}

String _prependAnnotations(List<String> annotations, String logBody) {
  if (annotations.isEmpty) return logBody;
  return 'Check Annotations:\n${annotations.join("\n")}\n\n$logBody';
}

Future<String> _fetchActionsRunLog(
  PrContext context,
  String runId, {
  required Future<String> Function(String) ghRepoApi,
  required CommandRunner runCommand,
}) async {
  final combinedLog = await _fetchCheckRunJobLogs(runId, ghRepoApi);
  if (combinedLog != null) return combinedLog;

  try {
    return await runCommand('gh', [
      '-R',
      '${context.owner}/${context.repo}',
      'run',
      'view',
      runId,
      '--log-failed',
    ], workingDirectory: context.workingDir);
  } catch (e) {
    return 'Failed to fetch logs: $e';
  }
}

/// Posts a reply to a PR review comment using its numeric [commentId].
Future<void> _replyToComment(
  PrContext context, {
  required String commentId,
  required String body,
  CommandRunner runCommand = runCommand,
}) async {
  if (!_digitsOnly.hasMatch(commentId)) {
    throw ArgumentError('Comment ID must be a numeric database ID.');
  }
  if (body.trim().isEmpty) {
    throw ArgumentError('Comment body cannot be empty.');
  }

  final endpoint =
      'repos/${context.owner}/${context.repo}/pulls/${context.prNumber}/comments/$commentId/replies';
  await runCommand('gh', [
    'api',
    endpoint,
    '-f',
    'body=$body',
  ], workingDirectory: context.workingDir);
}

/// Resolves a review thread via GraphQL using its [threadId] (e.g. `PRRT_...`).
Future<void> _resolveReviewThread(
  PrContext context, {
  required String threadId,
  CommandRunner runCommand = runCommand,
}) async {
  if (threadId.trim().isEmpty) {
    throw ArgumentError('Thread ID cannot be empty.');
  }
  const mutation = r'''
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread {
        isResolved
      }
    }
  }
  ''';

  final response = await runCommand('gh', [
    'api',
    'graphql',
    '-f',
    'query=$mutation',
    '-f',
    'threadId=$threadId',
  ], workingDirectory: context.workingDir);

  final parsed = jsonDecode(response) as Map<String, dynamic>;
  if (parsed['errors'] != null) {
    throw Exception('GraphQL errors resolving thread: ${parsed['errors']}');
  }
}

/// Replies to a comment (if [commentId] and [body] are provided) and resolves the [threadId].
Future<void> replyAndResolveThread(
  PrContext context, {
  required String threadId,
  String? commentId,
  String? body,
  CommandRunner runCommand = runCommand,
}) async {
  final hasCommentId = commentId != null && commentId.trim().isNotEmpty;
  final hasBody = body != null && body.trim().isNotEmpty;
  if (hasCommentId != hasBody) {
    throw ArgumentError(
      'Both commentId and body must be provided and non-empty, or both must be null/empty.',
    );
  }
  if (hasCommentId && hasBody) {
    await _replyToComment(
      context,
      commentId: commentId,
      body: body,
      runCommand: runCommand,
    );
  }
  await _resolveReviewThread(
    context,
    threadId: threadId,
    runCommand: runCommand,
  );
}

Future<String> _detectPrNumberFromBranch(
  String workingDir,
  Never Function(String) onFail,
  CommandRunner runCommand,
) async {
  String branch;
  try {
    branch = (await runCommand('git', [
      'symbolic-ref',
      '--short',
      'HEAD',
    ], workingDirectory: workingDir)).trim();
  } catch (_) {
    branch = '';
  }
  if (branch.isEmpty || branch == 'main' || branch == 'master') {
    onFail(
      'Active branch is ${branch.isEmpty ? 'detached HEAD' : '"$branch"'}. '
      'Please specify a target PR number or URL.',
    );
  }

  final listOutput = await runCommand('gh', [
    'pr',
    'list',
    '--head',
    branch,
    '--json',
    'number,url',
  ], workingDirectory: workingDir);
  final decodedList = jsonDecode(listOutput);
  final listJson = decodedList is List<dynamic> ? decodedList : const [];
  if (listJson.isEmpty) {
    onFail(
      'Error: Ambiguous context. No open PR found for branch "$branch". '
      'Do not guess. Please explicitly ask the user for a PR number or URL.',
    );
  }
  if (listJson.length > 1) {
    onFail(
      'Error: Ambiguous context. Multiple open PRs found for branch "$branch". '
      'Do not guess. Please explicitly ask the user which PR number or URL to target.',
    );
  }
  final firstPr = listJson[0];
  if (firstPr is! Map || firstPr['number'] == null) {
    onFail('Error: Unexpected PR data format from "gh pr list".');
  }
  return firstPr['number'].toString();
}

Future<(String?, String?)> _resolveLocalRepoOwner(
  String workingDir,
  CommandRunner runCommand,
) async {
  try {
    final repoOutput = await runCommand('gh', [
      'repo',
      'view',
      '--json',
      'owner,name',
    ], workingDirectory: workingDir);
    final repoJson = jsonDecode(repoOutput) as Map<String, dynamic>;
    final localOwner =
        (repoJson['owner'] as Map<String, dynamic>)['login'] as String;
    final localRepo = repoJson['name'] as String;
    return (localOwner, localRepo);
  } catch (_) {
    return (null, null);
  }
}

Future<List<String>> _fetchCheckRunAnnotations(
  String? checkRunId,
  Future<String> Function(String) ghRepoApi,
) async {
  if (checkRunId == null) return const [];
  try {
    final annOutput = await ghRepoApi('check-runs/$checkRunId/annotations');
    final annList = jsonDecode(annOutput) as List<dynamic>;
    return annList
        .whereType<Map>()
        .map(_formatCheckAnnotation)
        .nonNulls
        .toList();
  } catch (_) {
    return const [];
  }
}

String? _formatCheckAnnotation(Map<dynamic, dynamic> ann) {
  final message = ann['message']?.toString() ?? '';
  if (message.isEmpty) return null;

  final path = ann['path']?.toString() ?? '';
  final startLine = ann['start_line'];
  final level = ann['annotation_level']?.toString() ?? '';
  final title = ann['title']?.toString() ?? '';
  final pathPart = path.isNotEmpty ? '$path:$startLine ' : '';
  final titlePart = title.isNotEmpty ? '($title): ' : '';
  return 'Annotation [$level] $pathPart$titlePart$message';
}

Future<String?> _fetchCheckRunJobLogs(
  String runId,
  Future<String> Function(String) ghRepoApi,
) async {
  try {
    final jobsOutput = await ghRepoApi('actions/runs/$runId/jobs');
    final jobsJson = jsonDecode(jobsOutput) as Map<String, dynamic>;
    final jobsList = (jobsJson['jobs'] as List<dynamic>? ?? [])
        .whereType<Map>();
    final failedJobs = jobsList.where(_isFailedJob).toList();
    if (failedJobs.isEmpty) return null;

    final logBuffers = <String>[];
    for (final job in failedJobs) {
      final formatted = await _fetchSingleJobLog(job, ghRepoApi);
      if (formatted != null) logBuffers.add(formatted);
    }
    return logBuffers.isNotEmpty ? logBuffers.join('\n\n') : null;
  } catch (_) {
    return null;
  }
}

bool _isFailedJob(Map<dynamic, dynamic> job) {
  final conc = job['conclusion']?.toString();
  return conc == 'failure' || conc == 'timed_out' || conc == 'action_required';
}

Future<String?> _fetchSingleJobLog(
  Map<dynamic, dynamic> job,
  Future<String> Function(String) ghRepoApi,
) async {
  final jobId = job['id']?.toString();
  if (jobId == null || jobId.isEmpty) return null;

  try {
    final jobLog = await ghRepoApi('actions/jobs/$jobId/logs');
    if (jobLog.trim().isEmpty) return null;
    final jobName = job['name']?.toString() ?? 'Job';
    return '--- Job: $jobName (ID: $jobId) ---\n$jobLog';
  } catch (_) {
    return null;
  }
}
