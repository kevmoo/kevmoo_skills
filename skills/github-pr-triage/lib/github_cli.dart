import 'dart:convert';
import 'dart:io';

/// Encapsulates context for a target Pull Request and workspace directory.
class PrContext {
  final String workingDir;
  final String prNumber;
  final String owner;
  final String repo;

  PrContext({
    required this.workingDir,
    required this.prNumber,
    required this.owner,
    required this.repo,
  });
}

/// Runs an external process command and returns its standard output.
///
/// Throws a [ProcessException] if the command exits with a non-zero exit code.
Future<String> runCommand(
  String command,
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    command,
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      command,
      args,
      'Command failed with exit code ${result.exitCode}:\n${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout.toString();
}

/// Parses CLI arguments and resolves the [PrContext] for git operations.
Future<PrContext> resolvePrContext(
  List<String> args, {
  required Never Function(String message) onFail,
}) async {
  String? prInput;
  String? targetDir;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--pr' || arg == '-p') {
      if (i + 1 < args.length) {
        prInput = args[++i];
      } else {
        onFail('Missing value for option "$arg"');
      }
    } else if (arg == '--dir' || arg == '-C') {
      if (i + 1 < args.length) {
        targetDir = args[++i];
      } else {
        onFail('Missing value for option "$arg"');
      }
    } else if (arg.startsWith('-')) {
      onFail('Unknown option "$arg"');
    } else {
      prInput = arg;
    }
  }

  final workingDir = targetDir != null
      ? Directory(targetDir).absolute.path
      : Directory.current.absolute.path;
  if (!await Directory(workingDir).exists()) {
    onFail('Target directory "$workingDir" does not exist.');
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
      onFail(
        'Invalid PR argument. Please provide a PR number or a GitHub PR URL.',
      );
    }
  }

  // Auto-detect PR from current branch if not provided.
  if (prNumber == null) {
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
    prNumber = firstPr['number'].toString();
  }

  String? localOwner;
  String? localRepo;
  try {
    final repoOutput = await runCommand('gh', [
      'repo',
      'view',
      '--json',
      'owner,name',
    ], workingDirectory: workingDir);
    final repoJson = jsonDecode(repoOutput) as Map<String, dynamic>;
    localOwner = (repoJson['owner'] as Map<String, dynamic>)['login'] as String;
    localRepo = repoJson['name'] as String;
  } catch (e) {
    if (owner == null || repo == null) {
      onFail('Failed to resolve repository owner and name: $e');
    }
  }

  final resolvedOwner = owner ?? localOwner;
  final resolvedRepo = repo ?? localRepo;

  if (resolvedOwner == null || resolvedRepo == null) {
    onFail('Failed to resolve repository owner and name.');
  }

  if (localOwner != null &&
      localRepo != null &&
      owner != null &&
      repo != null) {
    if (localOwner.toLowerCase() != owner.toLowerCase() ||
        localRepo.toLowerCase() != repo.toLowerCase()) {
      onFail(
        'The target directory "$workingDir" is for repository "$localOwner/$localRepo", '
        'but the specified PR is for repository "$owner/$repo".',
      );
    }
  }

  return PrContext(
    workingDir: workingDir,
    prNumber: prNumber,
    owner: resolvedOwner,
    repo: resolvedRepo,
  );
}

/// Represents a status check run on a PR.
typedef PrCheckRun = ({
  String name,
  String state,
  String bucket,
  String link,
  String workflow,
});

/// Extension getters for [PrCheckRun].
extension PrCheckRunExt on PrCheckRun {
  bool get isFail => bucket == 'fail';
  bool get isPending => bucket == 'pending';
}

/// Represents a review comment on a PR.
typedef PrComment = ({
  String databaseId,
  String author,
  String body,
  String path,
  dynamic line,
  String createdAt,
  String url,
});

/// Represents a review thread on a PR.
typedef PrReviewThread = ({
  String id,
  bool isResolved,
  List<PrComment> comments,
});

/// Represents a submitted review on a PR.
typedef PrReview = ({String author, String submittedAt});

/// Container for GraphQL PR data.
typedef PrGraphData = ({
  List<PrComment> comments,
  List<PrReview> reviews,
  List<PrReviewThread> reviewThreads,
});

/// Fetches status check runs for the specified [PrContext].
Future<List<PrCheckRun>> fetchPrChecks(PrContext context) async {
  final repoArgs = ['-R', '${context.owner}/${context.repo}'];
  try {
    final checksOutput = await runCommand('gh', [
      ...repoArgs,
      'pr',
      'checks',
      context.prNumber,
      '--json',
      'name,state,bucket,link,workflow',
    ], workingDirectory: context.workingDir);
    final checks = jsonDecode(checksOutput) as List<dynamic>;
    return checks.whereType<Map>().map(_parsePrCheckRun).toList();
  } catch (e) {
    if (e is ProcessException && e.message.contains('no checks reported')) {
      return const [];
    }
    rethrow;
  }
}

/// Fetches comments, reviews, and review threads for the specified [PrContext] using GraphQL.
Future<PrGraphData> fetchPrGraphQLData(PrContext context) async {
  const query = r'''
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        comments(last: 100) {
          nodes {
            databaseId
            author { login }
            body
            createdAt
            url
          }
        }
        reviews(last: 100) {
          nodes {
            author { login }
            submittedAt
          }
        }
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

  final graphqlResponse = await runCommand('gh', [
    'api',
    'graphql',
    '-f',
    'owner=${context.owner}',
    '-f',
    'repo=${context.repo}',
    '-F',
    'pr=${context.prNumber}',
    '-f',
    'query=$query',
  ], workingDirectory: context.workingDir);

  final parsed = jsonDecode(graphqlResponse) as Map<String, dynamic>;
  if (parsed['errors'] != null) {
    throw Exception('GraphQL errors returned: ${parsed['errors']}');
  }

  final repository = parsed['data']?['repository'] as Map?;
  final prData = repository?['pullRequest'] as Map?;
  if (prData == null) {
    throw Exception('Pull request data not found in GraphQL response');
  }

  final comments = (prData['comments']?['nodes'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map(_parsePrComment)
      .toList();

  final reviews = (prData['reviews']?['nodes'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map(_parsePrReview)
      .toList();

  final threads = <PrReviewThread>[];
  final rawThreads = prData['reviewThreads']?['nodes'] as List<dynamic>? ?? [];
  for (final t in rawThreads) {
    if (t is Map) {
      final threadComments = (t['comments']?['nodes'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(_parsePrComment)
          .toList();
      threads.add((
        id: t['id']?.toString() ?? '',
        isResolved: t['isResolved'] == true,
        comments: threadComments,
      ));
    }
  }

  return (comments: comments, reviews: reviews, reviewThreads: threads);
}

/// Posts a reply to a PR review comment using its numeric [commentId].
Future<void> replyToComment(
  PrContext context, {
  required String commentId,
  required String body,
}) async {
  if (!RegExp(r'^\d+$').hasMatch(commentId)) {
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
Future<void> resolveReviewThread(
  PrContext context, {
  required String threadId,
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
}) async {
  final hasCommentId = commentId != null && commentId.trim().isNotEmpty;
  final hasBody = body != null && body.trim().isNotEmpty;
  if (hasCommentId != hasBody) {
    throw ArgumentError(
      'Both commentId and body must be provided and non-empty, or both must be null/empty.',
    );
  }
  if (hasCommentId && hasBody) {
    await replyToComment(context, commentId: commentId, body: body);
  }
  await resolveReviewThread(context, threadId: threadId);
}

PrCheckRun _parsePrCheckRun(Map json) {
  return (
    name: json['name']?.toString() ?? 'Unknown Check',
    state: json['state']?.toString() ?? '',
    bucket: json['bucket']?.toString() ?? '',
    link: json['link']?.toString() ?? '',
    workflow: json['workflow']?.toString() ?? '',
  );
}

PrComment _parsePrComment(Map json) {
  final authorLogin = switch (json['author']) {
    {'login': final String login} => login,
    _ => 'ghost',
  };
  return (
    databaseId: json['databaseId']?.toString() ?? '',
    author: authorLogin,
    body: json['body']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    line: json['line'] ?? json['originalLine'] ?? 'N/A',
    createdAt: json['createdAt']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
  );
}

PrReview _parsePrReview(Map json) {
  final authorLogin = switch (json['author']) {
    {'login': final String login} => login,
    _ => '',
  };
  return (
    author: authorLogin,
    submittedAt: json['submittedAt']?.toString() ?? '',
  );
}
