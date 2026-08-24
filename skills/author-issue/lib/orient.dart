import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Command runner type for testability.
typedef CommandRunner =
    Future<String> Function(
      String command,
      List<String> args, {
      String? workingDirectory,
    });

Future<String> defaultCommandRunner(
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

final _prefixPattern = RegExp(r'^(\[[^\]]+\]|[a-zA-Z0-9_-]+(?:\([^\)]+\))?:)');

/// Extracts title prefix convention (e.g. `[analyzer]`, `feat(scope):`, `pkg:`).
String? extractPrefix(String title) {
  final match = _prefixPattern.firstMatch(title.trim());
  return match?.group(0);
}

/// Encapsulates discovered repository conventions for issues and PRs.
class RepositoryOrientation {
  final String environment;
  final String? repoSlug;
  final List<String> maintainers;
  final List<String> commonIssuePrefixes;
  final List<String> commonPrPrefixes;
  final List<String> detectedLabels;
  final List<String> detectedTemplates;
  final List<String> sampleIssueTitles;
  final List<String> samplePrTitles;

  RepositoryOrientation({
    required this.environment,
    this.repoSlug,
    this.maintainers = const [],
    this.commonIssuePrefixes = const [],
    this.commonPrPrefixes = const [],
    this.detectedLabels = const [],
    this.detectedTemplates = const [],
    this.sampleIssueTitles = const [],
    this.samplePrTitles = const [],
  });

  Map<String, dynamic> toJson() => {
    'environment': environment,
    if (repoSlug != null) 'repoSlug': repoSlug,
    'maintainers': maintainers,
    'commonIssuePrefixes': commonIssuePrefixes,
    'commonPrPrefixes': commonPrPrefixes,
    'detectedLabels': detectedLabels,
    'detectedTemplates': detectedTemplates,
    'sampleIssueTitles': sampleIssueTitles,
    'samplePrTitles': samplePrTitles,
  };

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# Repository Conventions Orientation');
    buffer.writeln();
    buffer.writeln(
      '- **Environment**: $environment'
      '${repoSlug != null ? ' ($repoSlug)' : ''}',
    );
    if (maintainers.isNotEmpty) {
      buffer.writeln(
        '- **Active Maintainers / Reviewers**: '
        '${maintainers.take(8).map((m) => '@$m').join(', ')}',
      );
    }
    if (commonIssuePrefixes.isNotEmpty) {
      buffer.writeln(
        '- **Observed Issue Prefixes**: '
        '${commonIssuePrefixes.map((p) => '`$p`').join(', ')}',
      );
    }
    if (commonPrPrefixes.isNotEmpty) {
      buffer.writeln(
        '- **Observed PR / CL Prefixes**: '
        '${commonPrPrefixes.map((p) => '`$p`').join(', ')}',
      );
    }
    if (detectedLabels.isNotEmpty) {
      buffer.writeln(
        '- **Common Labels**: '
        '${detectedLabels.take(10).map((l) => '`$l`').join(', ')}',
      );
    }
    if (detectedTemplates.isNotEmpty) {
      buffer.writeln('- **Available Templates**:');
      for (final t in detectedTemplates) {
        buffer.writeln('  - `$t`');
      }
    }
    if (sampleIssueTitles.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('### Sample Maintainer Issue Titles');
      for (final title in sampleIssueTitles.take(5)) {
        buffer.writeln('- $title');
      }
    }
    if (samplePrTitles.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('### Sample Merged PR / CL Titles');
      for (final title in samplePrTitles.take(5)) {
        buffer.writeln('- $title');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// Gathers repository conventions from GitHub or Google3 environment.
class OrientationGatherer {
  final CommandRunner runCmd;

  OrientationGatherer({this.runCmd = defaultCommandRunner});

  Future<RepositoryOrientation> gather({
    String? workingDirectory,
    int sampleLimit = 20,
  }) async {
    final targetDir = workingDirectory ?? Directory.current.path;

    // Check if in Google3
    if (targetDir.contains('/google3') ||
        File(p.join(targetDir, 'WORKSPACE')).existsSync() ||
        Directory(p.join(targetDir, 'google3')).existsSync()) {
      return _gatherGoogle3(targetDir, sampleLimit: sampleLimit);
    }

    // Default to GitHub / Git
    return _gatherGitHub(targetDir, sampleLimit: sampleLimit);
  }

  Future<RepositoryOrientation> _gatherGitHub(
    String targetDir, {
    required int sampleLimit,
  }) async {
    String? repoSlug;
    try {
      final repoViewOut = await runCmd('gh', [
        'repo',
        'view',
        '--json',
        'nameWithOwner',
      ], workingDirectory: targetDir);
      final json = jsonDecode(repoViewOut) as Map<String, dynamic>;
      repoSlug = json['nameWithOwner'] as String?;
    } catch (_) {
      // Non-fatal if gh is not configured or in local git clone without remote
    }

    final maintainers = <String>{};
    final prTitles = <String>[];
    final prPrefixCounts = <String, int>{};
    final prLabels = <String>{};

    // 1. Fetch merged PRs to discover maintainers and PR conventions
    try {
      final prsJsonOut = await runCmd('gh', [
        'pr',
        'list',
        '--state',
        'merged',
        '--limit',
        sampleLimit.toString(),
        '--json',
        'author,reviews,title,labels',
      ], workingDirectory: targetDir);

      final prsList = jsonDecode(prsJsonOut) as List<dynamic>;
      for (final pr in prsList) {
        if (pr is! Map<String, dynamic>) continue;
        final authorMap = pr['author'] as Map<String, dynamic>?;
        final login = authorMap?['login'] as String?;
        if (login != null && login.isNotEmpty) {
          maintainers.add(login);
        }

        final reviews = pr['reviews'] as List<dynamic>?;
        if (reviews != null) {
          for (final review in reviews) {
            if (review is Map<String, dynamic>) {
              final reviewAuthor = review['author'] as Map<String, dynamic>?;
              final rLogin = reviewAuthor?['login'] as String?;
              if (rLogin != null && rLogin.isNotEmpty) {
                maintainers.add(rLogin);
              }
            }
          }
        }

        final title = pr['title'] as String?;
        if (title != null && title.isNotEmpty) {
          prTitles.add(title);
          final prefix = extractPrefix(title);
          if (prefix != null) {
            prPrefixCounts[prefix] = (prPrefixCounts[prefix] ?? 0) + 1;
          }
        }

        final labels = pr['labels'] as List<dynamic>?;
        if (labels != null) {
          for (final label in labels) {
            if (label is Map<String, dynamic>) {
              final lName = label['name'] as String?;
              if (lName != null && lName.isNotEmpty) {
                prLabels.add(lName);
              }
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal if gh pr list fails
    }

    // 2. Fetch issues to discover issue conventions and labels
    final issueTitles = <String>[];
    final issuePrefixCounts = <String, int>{};
    final issueLabels = <String>{};

    try {
      final issuesJsonOut = await runCmd('gh', [
        'issue',
        'list',
        '--state',
        'all',
        '--limit',
        sampleLimit.toString(),
        '--json',
        'author,title,labels',
      ], workingDirectory: targetDir);

      final issuesList = jsonDecode(issuesJsonOut) as List<dynamic>;
      for (final issue in issuesList) {
        if (issue is! Map<String, dynamic>) continue;
        final title = issue['title'] as String?;
        if (title != null && title.isNotEmpty) {
          issueTitles.add(title);
          final prefix = extractPrefix(title);
          if (prefix != null) {
            issuePrefixCounts[prefix] = (issuePrefixCounts[prefix] ?? 0) + 1;
          }
        }

        final labels = issue['labels'] as List<dynamic>?;
        if (labels != null) {
          for (final label in labels) {
            if (label is Map<String, dynamic>) {
              final lName = label['name'] as String?;
              if (lName != null && lName.isNotEmpty) {
                issueLabels.add(lName);
              }
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal if gh issue list fails
    }

    // 3. Scan local filesystem for issue/PR templates
    final detectedTemplates = <String>[];
    final templateDirs = [
      p.join(targetDir, '.github', 'ISSUE_TEMPLATE'),
      p.join(targetDir, '.github', 'PULL_REQUEST_TEMPLATE'),
    ];
    for (final dirPath in templateDirs) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          final rel = p.relative(file.path, from: targetDir);
          detectedTemplates.add(rel);
        }
      }
    }
    final rootPrTemplate = File(
      p.join(targetDir, '.github', 'pull_request_template.md'),
    );
    if (rootPrTemplate.existsSync()) {
      detectedTemplates.add('.github/pull_request_template.md');
    }

    // Sort prefixes by frequency
    final sortedIssuePrefixes = issuePrefixCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedPrPrefixes = prPrefixCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RepositoryOrientation(
      environment: 'GitHub',
      repoSlug: repoSlug,
      maintainers: maintainers.toList(),
      commonIssuePrefixes: sortedIssuePrefixes.map((e) => e.key).toList(),
      commonPrPrefixes: sortedPrPrefixes.map((e) => e.key).toList(),
      detectedLabels: {...issueLabels, ...prLabels}.toList(),
      detectedTemplates: detectedTemplates,
      sampleIssueTitles: issueTitles,
      samplePrTitles: prTitles,
    );
  }

  Future<RepositoryOrientation> _gatherGoogle3(
    String targetDir, {
    required int sampleLimit,
  }) async {
    final maintainers = <String>{};
    final detectedTemplates = <String>[];

    // Find nearest OWNERS file
    Directory? curr = Directory(targetDir);
    while (curr != null && curr.path != curr.parent.path) {
      final ownersFile = File(p.join(curr.path, 'OWNERS'));
      if (ownersFile.existsSync()) {
        try {
          final lines = ownersFile.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('#') &&
                !trimmed.contains('=')) {
              maintainers.add(trimmed);
            }
          }
        } catch (_) {}
        detectedTemplates.add(p.relative(ownersFile.path, from: targetDir));
        break;
      }
      curr = curr.parent;
    }

    final sampleCls = <String>[];
    try {
      final p4Out = await runCmd('p4', [
        'changes',
        '-m',
        sampleLimit.toString(),
        '-s',
        'submitted',
        '...',
      ], workingDirectory: targetDir);
      for (final line in p4Out.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          sampleCls.add(trimmed);
        }
      }
    } catch (_) {}

    return RepositoryOrientation(
      environment: 'Google3 / Piper',
      repoSlug: targetDir,
      maintainers: maintainers.toList(),
      samplePrTitles: sampleCls,
      detectedTemplates: detectedTemplates,
    );
  }
}

ArgParser buildArgParser() {
  return ArgParser()
    ..addOption(
      'dir',
      abbr: 'C',
      help: 'Target repository directory path (defaults to current directory)',
    )
    ..addOption(
      'limit',
      abbr: 'l',
      defaultsTo: '20',
      help: 'Sample limit for recent issues and PRs',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Output result as machine-readable JSON',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show CLI usage.');
}
