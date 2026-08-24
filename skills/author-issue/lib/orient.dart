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

final _prefixPattern = RegExp(
  r'^(\[[^\]]+\]|[a-zA-Z0-9_\-\/]+(?:\([^\)]+\))?:\s*)',
);

/// Extracts title prefix convention (e.g. `[analyzer]`, `feat(scope):`, `pkg:`).
/// Normalizes excess internal whitespace.
String? extractPrefix(String title) {
  final match = _prefixPattern.firstMatch(title.trim());
  if (match == null) return null;
  return match
      .group(0)!
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r':\s*$'), ':');
}

/// Checks whether a GitHub login corresponds to an automated bot or service account.
bool isBotAccount(String login) {
  final l = login.toLowerCase();
  return l.contains('[bot]') ||
      l.startsWith('app/') ||
      l.contains('copilot') ||
      l.endsWith('bot') ||
      l.contains('-bot') ||
      l.contains('bot-') ||
      l.contains('gemini-') ||
      l.contains('codecov') ||
      l == 'github-actions';
}

/// Extracts top-level form field IDs and labels from a GitHub YAML issue form.
List<String> extractYamlFormFields(String yamlContent) {
  final fields = <String>[];
  final lines = yamlContent.split('\n');
  String? currentId;
  String? currentLabel;

  for (final line in lines) {
    final idMatch = RegExp(r'^\s*id:\s*([a-zA-Z0-9_-]+)').firstMatch(line);
    if (idMatch != null) {
      if (currentId != null) {
        fields.add(
          currentLabel != null ? '$currentId ($currentLabel)' : currentId,
        );
        currentLabel = null;
      }
      currentId = idMatch.group(1);
      continue;
    }

    final labelMatch = RegExp(
      r'^\s*label:\s*["'
      ']?([^"'
      '\n]+)["'
      ']?',
    ).firstMatch(line);
    if (labelMatch != null && currentId != null && currentLabel == null) {
      currentLabel = labelMatch.group(1)?.trim();
    }
  }

  if (currentId != null) {
    fields.add(currentLabel != null ? '$currentId ($currentLabel)' : currentId);
  }

  return fields;
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
  final Map<String, List<String>> templateSchemas;
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
    this.templateSchemas = const {},
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
    if (templateSchemas.isNotEmpty) 'templateSchemas': templateSchemas,
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
        final schema = templateSchemas[t];
        if (schema != null && schema.isNotEmpty) {
          buffer.writeln('  - `$t`:');
          for (final field in schema) {
            buffer.writeln('    - `$field`');
          }
        } else {
          buffer.writeln('  - `$t`');
        }
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
    String? repo,
    int sampleLimit = 20,
  }) async {
    final targetDir = workingDirectory ?? Directory.current.path;

    // Remote repo target explicitly passed
    if (repo != null && repo.isNotEmpty) {
      return _gatherGitHub(
        targetDir,
        remoteRepo: repo,
        sampleLimit: sampleLimit,
      );
    }

    // Check if in Google3
    if (targetDir.contains('/google3') ||
        File(p.join(targetDir, 'WORKSPACE')).existsSync() ||
        Directory(p.join(targetDir, 'google3')).existsSync()) {
      return _gatherGoogle3(targetDir, sampleLimit: sampleLimit);
    }

    // Default to local GitHub / Git clone
    return _gatherGitHub(targetDir, sampleLimit: sampleLimit);
  }

  Future<RepositoryOrientation> _gatherGitHub(
    String targetDir, {
    String? remoteRepo,
    required int sampleLimit,
  }) async {
    String? repoSlug = remoteRepo;
    if (repoSlug == null) {
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
        // Non-fatal if gh repo view fails
      }
    }

    final repoArgs = repoSlug != null ? ['-R', repoSlug] : <String>[];

    final maintainers = <String>{};
    final prTitles = <String>[];
    final prPrefixCounts = <String, int>{};
    final prLabels = <String>{};

    // 1. Fetch merged PRs to discover maintainers and PR conventions
    try {
      final prsJsonOut = await runCmd('gh', [
        'pr',
        'list',
        ...repoArgs,
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
        if (login != null && login.isNotEmpty && !isBotAccount(login)) {
          maintainers.add(login);
        }

        final reviews = pr['reviews'] as List<dynamic>?;
        if (reviews != null) {
          for (final review in reviews) {
            if (review is Map<String, dynamic>) {
              final reviewAuthor = review['author'] as Map<String, dynamic>?;
              final rLogin = reviewAuthor?['login'] as String?;
              if (rLogin != null &&
                  rLogin.isNotEmpty &&
                  !isBotAccount(rLogin)) {
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
        ...repoArgs,
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

    // 3. Scan local filesystem or remote API for issue/PR templates and parse YAML forms
    final detectedTemplates = <String>[];
    final templateSchemas = <String, List<String>>{};

    if (remoteRepo != null) {
      // Fetch templates via GitHub API
      try {
        final apiOut = await runCmd('gh', [
          'api',
          'repos/$remoteRepo/contents/.github/ISSUE_TEMPLATE',
        ], workingDirectory: targetDir);
        final list = jsonDecode(apiOut) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final path = item['path'] as String?;
            final downloadUrl = item['download_url'] as String?;
            if (path != null) {
              detectedTemplates.add(path);
              if (downloadUrl != null &&
                  (path.endsWith('.yml') || path.endsWith('.yaml'))) {
                try {
                  final content = await runCmd('gh', [
                    'api',
                    'repos/$remoteRepo/contents/$path',
                    '--jq',
                    '.content',
                  ], workingDirectory: targetDir);
                  final decoded = utf8.decode(
                    base64.decode(content.replaceAll('\n', '')),
                  );
                  final fields = extractYamlFormFields(decoded);
                  if (fields.isNotEmpty) {
                    templateSchemas[path] = fields;
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    } else {
      // Scan local workspace
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
            if (rel.endsWith('.yml') || rel.endsWith('.yaml')) {
              try {
                final content = file.readAsStringSync();
                final fields = extractYamlFormFields(content);
                if (fields.isNotEmpty) {
                  templateSchemas[rel] = fields;
                }
              } catch (_) {}
            }
          }
        }
      }
      final rootPrTemplate = File(
        p.join(targetDir, '.github', 'pull_request_template.md'),
      );
      if (rootPrTemplate.existsSync()) {
        detectedTemplates.add('.github/pull_request_template.md');
      }
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
      templateSchemas: templateSchemas,
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
      'repo',
      abbr: 'R',
      help: 'Target GitHub repository slug in owner/repo format',
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
