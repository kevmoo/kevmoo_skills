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
    final workingDir = context.workingDir;
    final prNumber = context.prNumber;
    final owner = context.owner;
    final repo = context.repo;

    final repoArgs = ['-R', '$owner/$repo'];

    // 1. Fetch check runs via gh pr checks.
    var unresolvedThreadsCount = 0;
    final inProgressChecks = <String>[];
    final failedChecks = <String>[];

    try {
      final checksOutput = await _runCommand('gh', [
        ...repoArgs,
        'pr',
        'checks',
        prNumber,
        '--json',
        'name,state,bucket,link,workflow',
      ], workingDirectory: workingDir);
      final decodedChecks = jsonDecode(checksOutput);
      final checks = decodedChecks is List<dynamic> ? decodedChecks : const [];
      for (final check in checks) {
        if (check is! Map) continue;
        final name = check['name']?.toString() ?? 'Unknown Check';
        final bucket = check['bucket']?.toString() ?? '';
        if (bucket == 'pending') {
          inProgressChecks.add(name);
        } else if (bucket == 'fail') {
          failedChecks.add(name);
        }
      }
    } catch (e) {
      if (e is ProcessException && e.message.contains('no checks reported')) {
        // No checks reported.
      } else {
        rethrow;
      }
    }

    // 2. Fetch GraphQL data for reviewThreads and reactions.
    const query = r'''
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reactionGroups {
            content
            users { totalCount }
          }
          reviewThreads(first: 100) {
            nodes {
              isResolved
              comments(first: 50) {
                nodes {
                  author { login }
                  reactionGroups {
                    content
                    users { totalCount }
                  }
                }
              }
            }
          }
        }
      }
    }
    ''';

    var hasActiveEyesReaction = false;
    String? graphqlError;

    try {
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

      final parsed = jsonDecode(graphqlResponse);
      if (parsed is! Map<String, dynamic>) {
        graphqlError = 'Invalid GraphQL response format';
      } else if (parsed['errors'] != null) {
        graphqlError = 'GraphQL errors returned: ${parsed['errors']}';
      } else {
        final data = parsed['data'];
        final repository = data is Map ? data['repository'] : null;
        final prData = repository is Map ? repository['pullRequest'] : null;
        if (prData is Map) {
          if (_hasEyesReaction(prData)) {
            hasActiveEyesReaction = true;
          }

          final reviewThreads = prData['reviewThreads'];
          final rawThreads = reviewThreads is Map
              ? reviewThreads['nodes']
              : null;
          final threads = rawThreads is List<dynamic>
              ? rawThreads
              : const <dynamic>[];
          for (final thread in threads) {
            if (thread is Map && thread['isResolved'] == false) {
              unresolvedThreadsCount++;
              final commentsObj = thread['comments'];
              final rawComments = commentsObj is Map
                  ? commentsObj['nodes']
                  : null;
              final comments = rawComments is List<dynamic>
                  ? rawComments
                  : const <dynamic>[];
              for (final comment in comments) {
                if (_hasEyesReaction(comment)) {
                  hasActiveEyesReaction = true;
                }
              }
            }
          }
        } else {
          graphqlError = 'Pull request data not found in GraphQL response';
        }
      }
    } catch (e) {
      graphqlError = e.toString();
    }

    // Evaluate termination decision.
    bool canTerminate = true;
    String? reason;

    if (graphqlError != null) {
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
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    exit(1);
  }
}

bool _hasEyesReaction(dynamic comment) {
  if (comment is! Map) return false;
  final reactionGroups = comment['reactionGroups'];
  if (reactionGroups is! List) return false;
  for (final group in reactionGroups) {
    if (group is Map && group['content'] == 'EYES') {
      final users = group['users'];
      if (users is Map) {
        final totalCount = users['totalCount'];
        if (totalCount is int && totalCount > 0) {
          return true;
        }
      }
    }
  }
  return false;
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
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
