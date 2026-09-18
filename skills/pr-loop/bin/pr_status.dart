import 'dart:convert';
import 'dart:io';

import '../../github-pr-triage/lib/github_cli.dart';

/// Main entry point for the PR status verification tool (`pr_status.dart`).
///
/// Deterministically checks whether a PR is clean and ready for loop termination by verifying:
/// 1. Every check run in `statusCheckRollup` or `gh pr checks` has `status == 'COMPLETED'` AND (`conclusion == 'SUCCESS'` OR `'NEUTRAL'`).
/// 2. `reviewThreads` has 0 unresolved threads.
/// 3. No review bot has an active `EYES` (👀) reaction on recent review comments or threads.
void main(List<String> args) async {
  try {
    final context = await resolvePrContext(args, onFail: _fail);
    final (inProgressChecks, failedChecks) = await evaluateChecks(context);
    final graphEval = await evaluateGraphData(context);
    final syncStatus = await fetchPrSyncStatus(context);

    final (canTerminate, reason) = evaluateTermination(
      syncStatus: syncStatus,
      graphqlError: graphEval.graphqlError,
      inProgressChecks: inProgressChecks,
      failedChecks: failedChecks,
      unresolvedThreadsCount: graphEval.unresolvedThreadsCount,
      hasActiveEyesReaction: graphEval.hasActiveEyesReaction,
    );

    _writeJsonOutput(
      canTerminate: canTerminate,
      reason: reason,
      unresolvedThreads: graphEval.unresolvedThreadsCount,
      inProgressChecks: inProgressChecks,
      failedChecks: failedChecks,
      hasActiveEyesReaction: graphEval.hasActiveEyesReaction,
      localHeadSha: syncStatus.localHeadSha,
      remoteHeadSha: syncStatus.remoteHeadSha,
      isSynced: syncStatus.isSynced,
      syncState: syncStatus.syncState,
    );
  } catch (e, stack) {
    stderr.writeln('Error checking PR status: $e\n$stack');
    _writeJsonOutput(
      canTerminate: false,
      reason: 'Error checking PR status: $e',
      unresolvedThreads: 0,
      inProgressChecks: const <String>[],
      failedChecks: const <String>[],
      hasActiveEyesReaction: false,
      localHeadSha: '',
      remoteHeadSha: '',
      isSynced: false,
      syncState: 'error',
    );
    exit(1);
  }
}

Future<(List<String> inProgress, List<String> failed)> evaluateChecks(
  PrContext context, {
  CommandRunner runCommand = runCommand,
}) async {
  final checks = await fetchPrChecks(context, runCommand: runCommand);
  final inProgressChecks = <String>[];
  final failedChecks = <String>[];

  for (final check in checks) {
    if (check.bucket == 'pending') {
      inProgressChecks.add(check.name);
    } else if (check.bucket == 'fail') {
      failedChecks.add(check.name);
    }
  }
  return (inProgressChecks, failedChecks);
}

typedef GraphEvaluation = ({
  int unresolvedThreadsCount,
  bool hasActiveEyesReaction,
  String? graphqlError,
});

Future<GraphEvaluation> evaluateGraphData(
  PrContext context, {
  CommandRunner runCommand = runCommand,
}) async {
  try {
    final graphData = await fetchPrGraphQLData(context, runCommand: runCommand);
    final lastReviewRequestTime = latestMatchingTimestamp(
      graphData.comments,
      matches: (c) => c.body.contains('/gemini review'),
      timestampOf: (c) => c.createdAt,
    );
    final lastBotReviewTime = latestMatchingTimestamp(
      graphData.reviews,
      matches: (r) =>
          r.author.startsWith('gemini-code-assist') ||
          r.author.startsWith('gemini-code-review'),
      timestampOf: (r) => r.submittedAt,
    );

    final hasActiveEyesReaction =
        lastBotReviewTime == null ||
        (lastReviewRequestTime != null &&
            lastReviewRequestTime.isAfter(lastBotReviewTime));
    final unresolvedThreadsCount = graphData.reviewThreads
        .where((t) => !t.isResolved)
        .length;

    return (
      unresolvedThreadsCount: unresolvedThreadsCount,
      hasActiveEyesReaction: hasActiveEyesReaction,
      graphqlError: null,
    );
  } catch (e) {
    return (
      unresolvedThreadsCount: 0,
      hasActiveEyesReaction: false,
      graphqlError: e.toString(),
    );
  }
}

DateTime? latestMatchingTimestamp<T>(
  Iterable<T> items, {
  required bool Function(T) matches,
  required String Function(T) timestampOf,
}) {
  DateTime? latest;
  for (final item in items) {
    if (!matches(item)) continue;
    final dt = DateTime.tryParse(timestampOf(item));
    if (dt != null && (latest == null || dt.isAfter(latest))) {
      latest = dt;
    }
  }
  return latest;
}

(bool canTerminate, String? reason) evaluateTermination({
  required PrSyncStatus syncStatus,
  required String? graphqlError,
  required List<String> inProgressChecks,
  required List<String> failedChecks,
  required int unresolvedThreadsCount,
  required bool hasActiveEyesReaction,
}) {
  if (!syncStatus.isSynced) {
    return (
      false,
      syncStatus.warning ?? 'Local branch is out of sync with remote PR',
    );
  }
  if (graphqlError != null) {
    return (false, 'Failed to verify PR threads/reactions: $graphqlError');
  }
  if (inProgressChecks.isNotEmpty) {
    return (
      false,
      'CI workflow(s) still in progress: ${inProgressChecks.join(", ")}',
    );
  }
  if (failedChecks.isNotEmpty) {
    return (false, 'CI workflow(s) failed: ${failedChecks.join(", ")}');
  }
  if (unresolvedThreadsCount > 0) {
    return (
      false,
      'There are $unresolvedThreadsCount unresolved review thread(s)',
    );
  }
  if (hasActiveEyesReaction) {
    return (
      false,
      'Review bot has an active EYES (👀) reaction processing feedback',
    );
  }
  return (true, null);
}

void _writeJsonOutput({
  required bool canTerminate,
  required String? reason,
  required int unresolvedThreads,
  required List<String> inProgressChecks,
  required List<String> failedChecks,
  required bool hasActiveEyesReaction,
  required String localHeadSha,
  required String remoteHeadSha,
  required bool isSynced,
  required String syncState,
}) {
  final output = {
    'can_terminate': canTerminate,
    'reason': reason,
    'unresolved_threads': unresolvedThreads,
    'in_progress_checks': inProgressChecks,
    'failed_checks': failedChecks,
    'has_active_eyes_reaction': hasActiveEyesReaction,
    'local_head_sha': localHeadSha,
    'remote_head_sha': remoteHeadSha,
    'is_synced': isSynced,
    'sync_state': syncState,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
