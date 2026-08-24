import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Represents a merged GitHub Pull Request.
class LandedPr {
  final String repository;
  final int number;
  final String title;
  final String url;
  final DateTime closedAt;
  final String headRefName;
  final String baseRefName;
  final String? mergeCommitSha;
  final String body;

  LandedPr({
    required this.repository,
    required this.number,
    required this.title,
    required this.url,
    required this.closedAt,
    required this.headRefName,
    required this.baseRefName,
    this.mergeCommitSha,
    this.body = '',
  });

  String get owner => repository.contains('/') ? repository.split('/')[0] : '';
  String get repoName =>
      repository.contains('/') ? repository.split('/')[1] : repository;

  factory LandedPr.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? viewData,
  }) {
    final repoObj = json['repository'];
    final repoNameWithOwner = repoObj is Map
        ? repoObj['nameWithOwner']?.toString() ?? ''
        : json['repository']?.toString() ?? '';
    final closedAtStr =
        json['closedAt']?.toString() ?? DateTime.now().toIso8601String();

    final headRef =
        viewData?['headRefName']?.toString() ??
        json['headRefName']?.toString() ??
        '';
    final baseRef =
        viewData?['baseRefName']?.toString() ??
        json['baseRefName']?.toString() ??
        'main';
    final mergeCommitObj = viewData?['mergeCommit'] ?? json['mergeCommit'];
    final mergeSha = mergeCommitObj is Map
        ? mergeCommitObj['oid']?.toString()
        : mergeCommitObj?.toString();
    final bodyText =
        viewData?['body']?.toString() ?? json['body']?.toString() ?? '';

    return LandedPr(
      repository: repoNameWithOwner,
      number: json['number'] as int,
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      closedAt: DateTime.tryParse(closedAtStr) ?? DateTime.now(),
      headRefName: headRef,
      baseRefName: baseRef,
      mergeCommitSha: mergeSha,
      body: bodyText,
    );
  }
}

/// Information about a Git worktree.
class WorktreeInfo {
  final String path;
  final String head;
  final String branch;

  WorktreeInfo({required this.path, required this.head, required this.branch});
}

/// Status of the local git repository matching a landed PR.
class LocalRepoState {
  final String repoPath;
  final bool exists;
  final String? currentBranch;
  final List<WorktreeInfo> worktrees;
  final List<String> localBranches;

  LocalRepoState({
    required this.repoPath,
    required this.exists,
    this.currentBranch,
    this.worktrees = const [],
    this.localBranches = const [],
  });

  WorktreeInfo? findMatchingWorktree(String branchName, String repoName) {
    for (final wt in worktrees) {
      if (wt.path == repoPath) continue; // Skip main worktree root
      if (wt.branch == branchName || wt.branch == 'refs/heads/$branchName') {
        return wt;
      }
      final folderName = p.basename(wt.path);
      if (folderName == '_${repoName}-$branchName' ||
          folderName == '_${repoName}_$branchName') {
        return wt;
      }
    }
    return null;
  }

  bool isDirectlyOnFeatureBranch(String branchName) =>
      currentBranch == branchName;

  bool hasLocalBranch(String branchName) =>
      localBranches.contains(branchName) ||
      localBranches.contains('refs/heads/$branchName');
}

/// Attribution match for a Jetski conversation.
class JetskiMatch {
  final String conversationId;
  final String matchedTerm;
  final List<String> candidateHandles;

  JetskiMatch({
    required this.conversationId,
    required this.matchedTerm,
    this.candidateHandles = const [],
  });
}

/// An action performed during cleanup.
class CleanupAction {
  final String description;
  final bool success;
  final String? error;

  CleanupAction({required this.description, required this.success, this.error});

  Map<String, dynamic> toJson() => {
    'description': description,
    'success': success,
    if (error != null) 'error': error,
  };
}

/// Full result for a landed PR cleanup evaluation or execution.
class CleanupResult {
  final LandedPr pr;
  final LocalRepoState repoState;
  final List<JetskiMatch> jetskiMatches;
  final List<CleanupAction> actions;

  CleanupResult({
    required this.pr,
    required this.repoState,
    required this.jetskiMatches,
    required this.actions,
  });
}

/// Runs an external process and returns standard output, throwing on error.
Future<String> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Process failed with exit code ${result.exitCode}: ${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout.toString();
}

/// Fetches landed PRs from GitHub matching author and timeframe.
Future<List<LandedPr>> fetchLandedPrs({
  required String author,
  required Duration since,
  bool includeOwned = false,
}) async {
  final sinceDate = DateTime.now()
      .subtract(since)
      .toUtc()
      .toIso8601String()
      .split('T')[0];
  final searchArgs = [
    'search',
    'prs',
    '--author=$author',
    '--merged',
    '--merged-at=>=$sinceDate',
    '--json=repository,number,title,url,closedAt,updatedAt',
    '--limit=100',
  ];

  final searchOutput = await runProcess('gh', searchArgs);
  final items = jsonDecode(searchOutput) as List<dynamic>;

  final results = <LandedPr>[];
  for (final rawItem in items) {
    final item = rawItem as Map<String, dynamic>;
    final repoObj = item['repository'];
    final nameWithOwner = repoObj is Map
        ? repoObj['nameWithOwner']?.toString() ?? ''
        : '';

    if (!includeOwned &&
        (nameWithOwner.startsWith('$author/') || nameWithOwner == author)) {
      continue;
    }

    final prUrl = item['url']?.toString() ?? '';
    Map<String, dynamic>? viewData;
    if (prUrl.isNotEmpty) {
      try {
        final viewOutput = await runProcess('gh', [
          'pr',
          'view',
          prUrl,
          '--json=headRefName,baseRefName,mergedAt,mergeCommit,body,title,state',
        ]);
        viewData = jsonDecode(viewOutput) as Map<String, dynamic>;
      } catch (_) {
        // Fall back to search item fields if pr view fails
      }
    }

    results.add(LandedPr.fromJson(item, viewData: viewData));
  }

  return results;
}

/// Inspects local git repository and worktrees for a target PR.
Future<LocalRepoState> inspectLocalRepo(
  LandedPr pr, {
  String? githubDir,
}) async {
  final baseDir =
      githubDir ?? p.join(Platform.environment['HOME'] ?? '', 'github');

  // Standard location: ~/github/<repoName> (or ~/github/<owner>/<repoName> for personal repos)
  var targetPath = p.join(baseDir, pr.repoName);
  if (!Directory(targetPath).existsSync()) {
    final nestedPath = p.join(baseDir, pr.owner, pr.repoName);
    if (Directory(nestedPath).existsSync()) {
      targetPath = nestedPath;
    }
  }

  if (!Directory(targetPath).existsSync()) {
    return LocalRepoState(repoPath: targetPath, exists: false);
  }

  // Current branch
  String? currentBranch;
  try {
    final branchOut = await runProcess('git', [
      '-C',
      targetPath,
      'branch',
      '--show-current',
    ]);
    currentBranch = branchOut.trim();
  } catch (_) {}

  // List all local branches
  final localBranches = <String>[];
  try {
    final branchesOut = await runProcess('git', [
      '-C',
      targetPath,
      'branch',
      '--list',
      '--format=%(refname:short)',
    ]);
    for (final line in branchesOut.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) localBranches.add(trimmed);
    }
  } catch (_) {}

  // List worktrees
  final worktrees = <WorktreeInfo>[];
  try {
    final wtOut = await runProcess('git', [
      '-C',
      targetPath,
      'worktree',
      'list',
      '--porcelain',
    ]);
    final blocks = wtOut.split('\n\n');
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      String? wtPath;
      String? wtHead;
      String? wtBranch;
      for (final line in block.split('\n')) {
        if (line.startsWith('worktree ')) {
          wtPath = line.substring('worktree '.length).trim();
        } else if (line.startsWith('HEAD ')) {
          wtHead = line.substring('HEAD '.length).trim();
        } else if (line.startsWith('branch ')) {
          wtBranch = line.substring('branch '.length).trim();
          if (wtBranch.startsWith('refs/heads/')) {
            wtBranch = wtBranch.substring('refs/heads/'.length);
          }
        }
      }
      if (wtPath != null) {
        worktrees.add(
          WorktreeInfo(
            path: wtPath,
            head: wtHead ?? '',
            branch: wtBranch ?? '',
          ),
        );
      }
    }
  } catch (_) {}

  return LocalRepoState(
    repoPath: targetPath,
    exists: true,
    currentBranch: currentBranch,
    worktrees: worktrees,
    localBranches: localBranches,
  );
}

/// Executes git cleanup operations: worktree removal, branch deletion, and trunk sync.
Future<List<CleanupAction>> executeCleanup(
  LandedPr pr,
  LocalRepoState state, {
  bool skipSync = false,
  bool skipWorktrees = false,
}) async {
  final actions = <CleanupAction>[];
  if (!state.exists) {
    actions.add(
      CleanupAction(
        description:
            'Local repository not found at ${state.repoPath}; skipped.',
        success: false,
      ),
    );
    return actions;
  }

  final repoPath = state.repoPath;
  final headBranch = pr.headRefName;
  final baseBranch = pr.baseRefName.isNotEmpty ? pr.baseRefName : 'main';

  // 1. Check and prune matching worktree
  final matchingWt = state.findMatchingWorktree(headBranch, pr.repoName);
  if (matchingWt != null && !skipWorktrees) {
    try {
      await runProcess('git', [
        '-C',
        repoPath,
        'worktree',
        'remove',
        matchingWt.path,
      ]);
      actions.add(
        CleanupAction(
          description: 'Pruned sibling worktree at ${matchingWt.path}',
          success: true,
        ),
      );
    } catch (e) {
      actions.add(
        CleanupAction(
          description: 'Failed to prune worktree at ${matchingWt.path}',
          success: false,
          error: e.toString(),
        ),
      );
    }
  }

  // 2. If main repo checkout is directly on the feature branch, switch to base branch
  if (state.isDirectlyOnFeatureBranch(headBranch)) {
    try {
      await runProcess('git', ['-C', repoPath, 'checkout', baseBranch]);
      actions.add(
        CleanupAction(
          description:
              'Switched from feature branch `$headBranch` to `$baseBranch`',
          success: true,
        ),
      );
    } catch (e) {
      actions.add(
        CleanupAction(
          description: 'Failed to checkout `$baseBranch`',
          success: false,
          error: e.toString(),
        ),
      );
    }
  }

  // 3. Delete local feature branch
  if (headBranch.isNotEmpty && state.hasLocalBranch(headBranch)) {
    try {
      await runProcess('git', ['-C', repoPath, 'branch', '-D', headBranch]);
      actions.add(
        CleanupAction(
          description: 'Deleted local feature branch `$headBranch`',
          success: true,
        ),
      );
    } catch (e) {
      actions.add(
        CleanupAction(
          description: 'Failed to delete local branch `$headBranch`',
          success: false,
          error: e.toString(),
        ),
      );
    }
  }

  // 4. Fetch origin and fast-forward trunk
  if (!skipSync) {
    try {
      await runProcess('git', ['-C', repoPath, 'fetch', 'origin']);
      await runProcess('git', [
        '-C',
        repoPath,
        'merge',
        '--ff-only',
        'origin/$baseBranch',
      ]);
      actions.add(
        CleanupAction(
          description: 'Synced `$baseBranch` to `origin/$baseBranch`',
          success: true,
        ),
      );
    } catch (e) {
      actions.add(
        CleanupAction(
          description:
              'Failed to fast-forward `$baseBranch` to `origin/$baseBranch`',
          success: false,
          error: e.toString(),
        ),
      );
    }
  }

  return actions;
}

/// Discovers Jetski conversations and task handles associated with a landed PR.
Future<List<JetskiMatch>> findJetskiMatches(
  LandedPr pr, {
  String? brainDir,
}) async {
  final defaultBrain =
      brainDir ??
      p.join(Platform.environment['HOME'] ?? '', '.gemini', 'jetski', 'brain');
  final dir = Directory(defaultBrain);
  if (!dir.existsSync()) return [];

  final matches = <JetskiMatch>[];
  final prNumberStr = pr.number.toString();
  final branchName = pr.headRefName;
  // Crockford Base32 handle pattern for PM-OS (#XXXX or #XXXXX)
  final handlePattern = RegExp(
    r'#([0-9A-HJ-KM-NP-TV-Z]{4,5})\b',
    caseSensitive: false,
  );
  const ignoredWords = {
    'HEAD',
    'LINE',
    'DATA',
    'TOOL',
    'NAME',
    'ELSE',
    'ELIF',
    'ENDIF',
    'SLIDE',
    'ABOUT',
    'MIXED',
    'TASK',
    'PATCH',
    'WHEN',
    'CLOUD',
    'BEST',
    'AVOID',
    'ZIPPY',
    'BLAZE',
    'UNDEF',
    'INBOX',
  };

  // Extract handles from PR body
  final prBodyHandles = <String>{};
  for (final m in handlePattern.allMatches(pr.body)) {
    final handle = m.group(0)!.toUpperCase();
    if (!ignoredWords.contains(handle.substring(1))) {
      prBodyHandles.add(handle);
    }
  }

  // Fast path: use rg glob search across brain transcript files
  try {
    final pattern = branchName.isNotEmpty
        ? 'pull/$prNumberStr|$branchName'
        : 'pull/$prNumberStr';
    final result = await Process.run('rg', [
      '-l',
      '--glob',
      'transcript.jsonl',
      pattern,
      defaultBrain,
    ]);
    if (result.exitCode == 0) {
      final matchingPaths = result.stdout
          .toString()
          .split('\n')
          .where((s) => s.trim().isNotEmpty);
      for (final filePath in matchingPaths) {
        final convId = p.basename(
          Directory(filePath).parent.parent.parent.path,
        );
        try {
          final file = File(filePath);
          final content = await file.readAsString();
          final containsPr =
              content.contains('pull/$prNumberStr') ||
              (content.contains(pr.repoName) && content.contains(prNumberStr));
          final containsBranch =
              branchName.isNotEmpty && content.contains(branchName);

          if (containsPr || containsBranch) {
            final matchedTerm = containsPr
                ? 'PR #$prNumberStr'
                : 'Branch `$branchName`';
            final handles = Set<String>.from(prBodyHandles);
            for (final m in handlePattern.allMatches(content)) {
              final h = m.group(0)!.toUpperCase();
              if (!ignoredWords.contains(h.substring(1))) {
                handles.add(h);
              }
            }
            matches.add(
              JetskiMatch(
                conversationId: convId,
                matchedTerm: matchedTerm,
                candidateHandles: handles.toList(),
              ),
            );
          }
        } catch (_) {}
      }
      return matches;
    }
  } catch (_) {
    // Fall back to mtime-filtered scan
  }

  // Fallback: only inspect sessions active in the last 14 days
  final cutoff = DateTime.now().subtract(const Duration(days: 14));
  try {
    final subdirs = dir.listSync().whereType<Directory>();
    for (final sessionDir in subdirs) {
      final transcriptFile = File(
        p.join(
          sessionDir.path,
          '.system_generated',
          'logs',
          'transcript.jsonl',
        ),
      );
      if (!transcriptFile.existsSync()) continue;
      try {
        if (transcriptFile.lastModifiedSync().isBefore(cutoff)) continue;
        final content = await transcriptFile.readAsString();
        final containsPr =
            content.contains('pull/$prNumberStr') ||
            (content.contains(pr.repoName) && content.contains(prNumberStr));
        final containsBranch =
            branchName.isNotEmpty && content.contains(branchName);

        if (containsPr || containsBranch) {
          final matchedTerm = containsPr
              ? 'PR #$prNumberStr'
              : 'Branch `$branchName`';
          final handles = Set<String>.from(prBodyHandles);
          for (final m in handlePattern.allMatches(content)) {
            final h = m.group(0)!.toUpperCase();
            if (!ignoredWords.contains(h.substring(1))) {
              handles.add(h);
            }
          }
          matches.add(
            JetskiMatch(
              conversationId: p.basename(sessionDir.path),
              matchedTerm: matchedTerm,
              candidateHandles: handles.toList(),
            ),
          );
        }
      } catch (_) {}
    }
  } catch (_) {}

  return matches;
}

/// Generates markdown report table and itemized sections.
String formatMarkdownReport(
  List<CleanupResult> results, {
  bool applied = false,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# Landed Pull Requests & Cleanup Report\n');
  buffer.writeln(
    '**Mode**: ${applied ? '✅ Executed Cleanup (`--apply`)' : '🔍 Preview Mode (Dry Run)'}\n',
  );

  if (results.isEmpty) {
    buffer.writeln(
      'No landed pull requests found matching the specified timeframe.\n',
    );
    return buffer.toString();
  }

  buffer.writeln('<!-- mdformat off -->');
  buffer.writeln(
    '| Repository | PR # | Local Directory | Landed (UTC) | Jetski Session | PM-OS / Task Handles | Actions / Status |',
  );
  buffer.writeln('| :--- | :---: | :--- | :---: | :---: | :--- | :--- |');

  for (final res in results) {
    final pr = res.pr;
    final repoLink = '[**${pr.repository}**](${pr.url})';
    final prLink = '[#${pr.number}](${pr.url})';
    final localDir = res.repoState.exists
        ? '[`${res.repoState.repoPath}`](file://${res.repoState.repoPath})'
        : '*(Not checked out)*';
    final landedDate = pr.closedAt
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 16);

    final sessions = res.jetskiMatches.isEmpty
        ? '*(None)*'
        : res.jetskiMatches
              .map(
                (m) =>
                    '[${m.conversationId.substring(0, 8)}](conversation://${m.conversationId})',
              )
              .join(', ');

    final handles = <String>{};
    for (final m in res.jetskiMatches) {
      handles.addAll(m.candidateHandles);
    }
    final handleText = handles.isEmpty ? '-' : handles.join(', ');

    final actionSummary = res.actions.isEmpty
        ? (applied ? 'No action needed' : 'Pending review')
        : res.actions
              .map(
                (a) => a.success ? '✅ ${a.description}' : '❌ ${a.description}',
              )
              .join('<br>');

    buffer.writeln(
      '| $repoLink | $prLink | $localDir | $landedDate | $sessions | $handleText | $actionSummary |',
    );
  }

  buffer.writeln('<!-- mdformat on -->\n');

  buffer.writeln('## Detailed Action Item Breakdown\n');
  for (final res in results) {
    final pr = res.pr;
    buffer.writeln(
      '### ${pr.repository} — [#${pr.number}](${pr.url}): ${pr.title}\n',
    );
    buffer.writeln('- **Landed**: `${pr.closedAt.toIso8601String()}`');
    if (pr.mergeCommitSha != null) {
      buffer.writeln('- **Merge Commit**: `${pr.mergeCommitSha}`');
    }
    buffer.writeln(
      '- **Source Branch**: `${pr.headRefName}` ➔ Target: `${pr.baseRefName}`',
    );
    buffer.writeln(
      '- **Local Directory**: [`${res.repoState.repoPath}`](file://${res.repoState.repoPath})',
    );

    final matchingWt = res.repoState.findMatchingWorktree(
      pr.headRefName,
      pr.repoName,
    );
    if (matchingWt != null) {
      buffer.writeln(
        '- **Associated Worktree**: [`${matchingWt.path}`](file://${matchingWt.path})',
      );
    }

    if (res.jetskiMatches.isNotEmpty) {
      buffer.writeln('- **Jetski Sessions**:');
      for (final m in res.jetskiMatches) {
        buffer.writeln(
          '  - [${m.conversationId}](conversation://${m.conversationId}) (Matched: ${m.matchedTerm})',
        );
        if (m.candidateHandles.isNotEmpty) {
          buffer.writeln(
            '    - Candidate Handles: ${m.candidateHandles.join(', ')}',
          );
        }
      }
    }

    if (res.actions.isNotEmpty) {
      buffer.writeln('- **Actions Log**:');
      for (final a in res.actions) {
        buffer.writeln(
          '  - ${a.success ? '✅' : '❌'} ${a.description}${a.error != null ? ' (Error: ${a.error})' : ''}',
        );
      }
    }
    buffer.writeln();
  }

  return buffer.toString();
}

/// Formats output as structured JSON.
Map<String, dynamic> formatJsonReport(
  List<CleanupResult> results, {
  bool applied = false,
}) {
  return {
    'applied': applied,
    'count': results.length,
    'results': results
        .map(
          (r) => {
            'repository': r.pr.repository,
            'prNumber': r.pr.number,
            'title': r.pr.title,
            'url': r.pr.url,
            'closedAt': r.pr.closedAt.toIso8601String(),
            'headRefName': r.pr.headRefName,
            'baseRefName': r.pr.baseRefName,
            'mergeCommitSha': r.pr.mergeCommitSha,
            'repoPath': r.repoState.repoPath,
            'repoExists': r.repoState.exists,
            'jetskiSessions': r.jetskiMatches
                .map(
                  (m) => {
                    'conversationId': m.conversationId,
                    'matchedTerm': m.matchedTerm,
                    'candidateHandles': m.candidateHandles,
                  },
                )
                .toList(),
            'actions': r.actions.map((a) => a.toJson()).toList(),
          },
        )
        .toList(),
  };
}
