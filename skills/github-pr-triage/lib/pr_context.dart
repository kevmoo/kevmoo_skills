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

/// Function signature for running external process commands.
typedef CommandRunner =
    Future<String> Function(
      String command,
      List<String> args, {
      String? workingDirectory,
    });

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
    final details = [
      result.stderr.toString().trim(),
      result.stdout.toString().trim(),
    ].where((s) => s.isNotEmpty).join('\n');
    throw ProcessException(
      command,
      args,
      'Command failed with exit code ${result.exitCode}:\n$details',
      result.exitCode,
    );
  }
  return result.stdout.toString();
}

/// Represents a status check run on a PR.
typedef PrCheckRun = ({
  String name,
  String state,
  String bucket,
  String link,
  String workflow,
});

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
typedef PrReview = ({
  String id,
  String databaseId,
  String author,
  String body,
  String state,
  String submittedAt,
  String url,
});

/// Container for GraphQL PR data.
typedef PrGraphData = ({
  List<PrComment> comments,
  List<PrReview> reviews,
  List<PrReviewThread> reviewThreads,
});

/// Fetches status check runs for the specified [PrContext].
Future<List<PrCheckRun>> fetchPrChecks(
  PrContext context, {
  CommandRunner runCommand = runCommand,
}) async {
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
Future<PrGraphData> fetchPrGraphQLData(
  PrContext context, {
  CommandRunner runCommand = runCommand,
}) async {
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
            id
            databaseId
            author { login }
            body
            state
            submittedAt
            url
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

  List<T> extractNodes<T>(Map? parent, String field, T Function(Map) mapper) {
    return (parent?[field]?['nodes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(mapper)
        .toList();
  }

  final comments = extractNodes(prData, 'comments', _parsePrComment);
  final reviews = extractNodes(prData, 'reviews', _parsePrReview);

  final threads = <PrReviewThread>[];
  final rawThreads = prData['reviewThreads']?['nodes'] as List<dynamic>? ?? [];
  for (final t in rawThreads) {
    if (t is Map) {
      final threadComments = extractNodes(t, 'comments', _parsePrComment);
      threads.add((
        id: t['id']?.toString() ?? '',
        isResolved: t['isResolved'] == true,
        comments: threadComments,
      ));
    }
  }

  return (comments: comments, reviews: reviews, reviewThreads: threads);
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
    _ => 'ghost',
  };
  return (
    id: json['id']?.toString() ?? '',
    databaseId: json['databaseId']?.toString() ?? '',
    author: authorLogin,
    body: json['body']?.toString() ?? '',
    state: json['state']?.toString() ?? '',
    submittedAt: json['submittedAt']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
  );
}

/// Structured analysis of merge conflicts between a PR's head and base branches.
typedef PrConflictAnalysis = ({
  bool isConflicting,
  String mergeable,
  String mergeStateStatus,
  String baseRefName,
  String headRefName,
  List<String> conflictingFiles,
  List<String> conflictMessages,
  List<String> upstreamCommits,
});

final _hexOidRegExp = RegExp(r'^[0-9a-f]{40,64}$');
final _conflictInFileRegExp = RegExp(r'^CONFLICT \([^)]+\): .* in (.+)$');

/// Parses `git merge-tree --write-tree --name-only` output into conflicting
/// file paths and conflict summary messages.
({List<String> files, List<String> messages}) parseMergeTreeConflictOutput(
  String rawOutput,
) {
  final files = <String>{};
  final messages = <String>[];
  final lines = rawOutput
      .split('\n')
      .map(
        (l) => l
            .replaceFirst(RegExp(r'^Command failed with exit code \d+:'), '')
            .trim(),
      )
      .toList();

  var inNameList = false;
  for (final line in lines) {
    if (line.isEmpty) {
      if (inNameList) inNameList = false;
      continue;
    }
    if (_hexOidRegExp.hasMatch(line)) {
      inNameList = true;
      continue;
    }
    if (line.startsWith('CONFLICT (')) {
      messages.add(line);
      final match = _conflictInFileRegExp.firstMatch(line);
      if (match != null) {
        files.add(match.group(1)!.trim());
      }
      inNameList = false;
      continue;
    }
    if (line.startsWith('Auto-merging ')) {
      inNameList = false;
      continue;
    }
    if (inNameList && !line.contains(' ')) {
      files.add(line);
    }
  }

  return (files: files.toList(), messages: messages);
}

/// Inspects a PR's mergeability state and, if `CONFLICTING` or `DIRTY`, uses
/// local `git fetch`, `git merge-tree`, and `git log` to identify the exact
/// conflicting files and upstream commits on `origin/<baseRefName>`.
Future<PrConflictAnalysis> analyzePrConflicts(
  PrContext context,
  Map<String, dynamic> prData, {
  CommandRunner runCommand = runCommand,
}) async {
  final mergeable = prData['mergeable']?.toString() ?? 'UNKNOWN';
  final mergeStateStatus = prData['mergeStateStatus']?.toString() ?? 'UNKNOWN';
  final baseRefName = prData['baseRefName']?.toString() ?? 'main';
  final headRefName = prData['headRefName']?.toString() ?? '';
  final isConflicting =
      mergeable == 'CONFLICTING' || mergeStateStatus == 'DIRTY';

  if (!isConflicting || headRefName.isEmpty) {
    return (
      isConflicting: isConflicting,
      mergeable: mergeable,
      mergeStateStatus: mergeStateStatus,
      baseRefName: baseRefName,
      headRefName: headRefName,
      conflictingFiles: const <String>[],
      conflictMessages: const <String>[],
      upstreamCommits: const <String>[],
    );
  }

  var conflictingFiles = <String>[];
  var conflictMessages = <String>[];
  var upstreamCommits = <String>[];

  try {
    await runCommand('git', [
      'fetch',
      'origin',
      baseRefName,
      headRefName,
    ], workingDirectory: context.workingDir);
  } catch (_) {
    // Best-effort fetch; proceed with locally available refs if offline.
  }

  String mergeTreeOut = '';
  try {
    mergeTreeOut = await runCommand('git', [
      'merge-tree',
      '--write-tree',
      '--name-only',
      'origin/$baseRefName',
      'origin/$headRefName',
    ], workingDirectory: context.workingDir);
  } on ProcessException catch (e) {
    mergeTreeOut = e.message;
  } catch (_) {}

  if (mergeTreeOut.isNotEmpty) {
    final parsed = parseMergeTreeConflictOutput(mergeTreeOut);
    conflictingFiles = parsed.files;
    conflictMessages = parsed.messages;
  }

  try {
    final logArgs = <String>[
      'log',
      '--oneline',
      '-n',
      '10',
      'origin/$headRefName..origin/$baseRefName',
      if (conflictingFiles.isNotEmpty) ...['--', ...conflictingFiles],
    ];
    final logOut = await runCommand(
      'git',
      logArgs,
      workingDirectory: context.workingDir,
    );
    upstreamCommits = logOut
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  } catch (_) {}

  return (
    isConflicting: true,
    mergeable: mergeable,
    mergeStateStatus: mergeStateStatus,
    baseRefName: baseRefName,
    headRefName: headRefName,
    conflictingFiles: conflictingFiles,
    conflictMessages: conflictMessages,
    upstreamCommits: upstreamCommits,
  );
}
