import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import '../lib/github_landed_pr_cleanup.dart';

ArgParser _buildParser() {
  return ArgParser()
    ..addOption(
      'author',
      abbr: 'a',
      defaultsTo: 'kevmoo',
      help: 'GitHub author username to filter merged PRs.',
    )
    ..addOption(
      'since',
      abbr: 's',
      defaultsTo: '24h',
      help: 'Time window to search for landed PRs (e.g. 24h, 48h, 7d).',
    )
    ..addFlag(
      'include-owned',
      defaultsTo: false,
      negatable: false,
      help: 'Include repositories owned by the author.',
    )
    ..addFlag(
      'apply',
      defaultsTo: false,
      negatable: false,
      help: 'Execute worktree pruning, local branch deletion, and trunk sync.',
    )
    ..addOption(
      'format',
      abbr: 'f',
      defaultsTo: 'markdown',
      allowed: ['markdown', 'json'],
      help: 'Output format (markdown or json).',
    )
    ..addOption(
      'github-dir',
      help: 'Base directory for GitHub repositories (defaults to ~/github).',
    )
    ..addOption(
      'brain-dir',
      help: 'Jetski brain directory for conversation discovery.',
    )
    ..addFlag(
      'skip-sync',
      defaultsTo: false,
      negatable: false,
      help: 'Skip fast-forwarding default branch against origin.',
    )
    ..addFlag(
      'skip-worktrees',
      defaultsTo: false,
      negatable: false,
      help: 'Skip pruning matching sibling worktrees.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message.');
}

Duration _parseDuration(String input) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.endsWith('h')) {
    final hours = int.tryParse(trimmed.substring(0, trimmed.length - 1));
    if (hours != null) return Duration(hours: hours);
  } else if (trimmed.endsWith('d')) {
    final days = int.tryParse(trimmed.substring(0, trimmed.length - 1));
    if (days != null) return Duration(days: days);
  } else if (trimmed.endsWith('w')) {
    final weeks = int.tryParse(trimmed.substring(0, trimmed.length - 1));
    if (weeks != null) return Duration(days: weeks * 7);
  }
  final days = int.tryParse(trimmed);
  if (days != null) return Duration(days: days);
  return const Duration(hours: 24);
}

void main(List<String> args) async {
  final parser = _buildParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  }

  if (results.flag('help')) {
    stdout.writeln('GitHub Landed PR Cleanup Tool\n');
    stdout.writeln('Usage: dart run cleanup.dart [options]\n');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final author = results.option('author')!;
  final since = _parseDuration(results.option('since')!);
  final includeOwned = results.flag('include-owned');
  final apply = results.flag('apply');
  final format = results.option('format')!;
  final githubDir = results.option('github-dir');
  final brainDir = results.option('brain-dir');
  final skipSync = results.flag('skip-sync');
  final skipWorktrees = results.flag('skip-worktrees');

  try {
    stderr.writeln(
      'Querying GitHub for merged PRs authored by $author (since last ${results.option('since')})...',
    );
    final landedPrs = await fetchLandedPrs(
      author: author,
      since: since,
      includeOwned: includeOwned,
    );

    stderr.writeln(
      'Found ${landedPrs.length} landed PR(s). Inspecting local workspaces and Jetski sessions...',
    );

    final cleanupResults = <CleanupResult>[];
    for (final pr in landedPrs) {
      final repoState = await inspectLocalRepo(pr, githubDir: githubDir);
      final jetskiMatches = await findJetskiMatches(pr, brainDir: brainDir);

      final actions = <CleanupAction>[];
      if (apply) {
        actions.addAll(
          await executeCleanup(
            pr,
            repoState,
            skipSync: skipSync,
            skipWorktrees: skipWorktrees,
          ),
        );
      }

      cleanupResults.add(
        CleanupResult(
          pr: pr,
          repoState: repoState,
          jetskiMatches: jetskiMatches,
          actions: actions,
        ),
      );
    }

    if (format == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(formatJsonReport(cleanupResults, applied: apply)),
      );
    } else {
      stdout.write(formatMarkdownReport(cleanupResults, applied: apply));
    }
  } catch (e, stack) {
    stderr.writeln('Error: $e\n$stack');
    exit(1);
  }
}
