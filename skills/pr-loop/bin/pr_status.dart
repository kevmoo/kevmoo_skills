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

    final inProgressChecks = <String>[];
    final failedChecks = <String>[];

    try {
      final checks = await fetchPrChecks(context);
      for (final check in checks) {
        if (check.bucket == 'pending') {
          inProgressChecks.add(check.name);
        } else if (check.bucket == 'fail') {
          failedChecks.add(check.name);
        }
      }
    } catch (e) {
      rethrow;
    }

    var unresolvedThreadsCount = 0;
    var hasActiveEyesReaction = false;
    String? graphqlError;

    try {
      final graphData = await fetchPrGraphQLData(context);

      DateTime? lastReviewRequestTime;
      for (final comment in graphData.comments) {
        if (comment.body.contains('/gemini review')) {
          final dt = DateTime.tryParse(comment.createdAt);
          if (dt != null &&
              (lastReviewRequestTime == null ||
                  dt.isAfter(lastReviewRequestTime))) {
            lastReviewRequestTime = dt;
          }
        }
      }

      DateTime? lastBotReviewTime;
      for (final review in graphData.reviews) {
        if (review.author.startsWith('gemini-code-assist') ||
            review.author.startsWith('gemini-code-review')) {
          final dt = DateTime.tryParse(review.submittedAt);
          if (dt != null &&
              (lastBotReviewTime == null || dt.isAfter(lastBotReviewTime))) {
            lastBotReviewTime = dt;
          }
        }
      }

      if (lastBotReviewTime == null) {
        hasActiveEyesReaction = true;
      } else if (lastReviewRequestTime != null &&
          lastReviewRequestTime.isAfter(lastBotReviewTime)) {
        hasActiveEyesReaction = true;
      }

      for (final thread in graphData.reviewThreads) {
        if (!thread.isResolved) {
          unresolvedThreadsCount++;
        }
      }
    } catch (e) {
      graphqlError = e.toString();
    }

    // Evaluate local vs remote sync status using shared helper.
    final syncStatus = await fetchPrSyncStatus(context);

    // Evaluate termination decision.
    bool canTerminate = true;
    String? reason;

    if (!syncStatus.isSynced) {
      canTerminate = false;
      reason =
          syncStatus.warning ?? 'Local branch is out of sync with remote PR';
    } else if (graphqlError != null) {
      canTerminate = false;
      reason = 'Failed to verify PR threads/reactions: $graphqlError';
    } else if (inProgressChecks.isNotEmpty) {
      canTerminate = false;
      reason =
          'CI workflow(s) still in progress: ${inProgressChecks.join(", ")}';
    } else if (failedChecks.isNotEmpty) {
      canTerminate = false;
      reason = 'CI workflow(s) failed: ${failedChecks.join(", ")}';
    } else if (unresolvedThreadsCount > 0) {
      canTerminate = false;
      reason = 'There are $unresolvedThreadsCount unresolved review thread(s)';
    } else if (hasActiveEyesReaction) {
      canTerminate = false;
      reason =
          'Review bot has an active EYES (👀) reaction processing feedback';
    }

    final output = {
      'can_terminate': canTerminate,
      'reason': reason,
      'unresolved_threads': unresolvedThreadsCount,
      'in_progress_checks': inProgressChecks,
      'failed_checks': failedChecks,
      'has_active_eyes_reaction': hasActiveEyesReaction,
      'local_head_sha': syncStatus.localHeadSha,
      'remote_head_sha': syncStatus.remoteHeadSha,
      'is_synced': syncStatus.isSynced,
      'sync_state': syncStatus.syncState,
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  } catch (e, stack) {
    stderr.writeln('Error checking PR status: $e\n$stack');
    final output = {
      'can_terminate': false,
      'reason': 'Error checking PR status: $e',
      'unresolved_threads': 0,
      'in_progress_checks': <String>[],
      'failed_checks': <String>[],
      'has_active_eyes_reaction': false,
      'local_head_sha': '',
      'remote_head_sha': '',
      'is_synced': false,
      'sync_state': 'error',
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    exit(1);
  }
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
