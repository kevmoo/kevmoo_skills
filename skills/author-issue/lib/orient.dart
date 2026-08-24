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
  r'^(\[[^\]]+\]|[a-zA-Z0-9_\-\/]+(?:\([^\)]+\))?!*:\s*)',
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

/// Helper to safely extract non-empty label names from a raw JSON label list.
Set<String> _extractLabels(List<dynamic>? labelsList) {
  final result = <String>{};
  if (labelsList == null) return result;
  for (final label in labelsList) {
    if (label is Map<String, dynamic>) {
      final name = label['name'] as String?;
      if (name != null && name.isNotEmpty) {
        result.add(name);
      }
    }
  }
  return result;
}

/// Helper to record title prefix frequencies into a map and list.
void _recordTitle(
  String? title,
  List<String> titlesList,
  Map<String, int> prefixCounts,
) {
  if (title == null || title.isEmpty) return;
  titlesList.add(title);
  final prefix = extractPrefix(title);
  if (prefix != null) {
    prefixCounts[prefix] = (prefixCounts[prefix] ?? 0) + 1;
  }
}

/// Extracts top-level form field IDs and labels from a GitHub YAML issue form.
List<String> extractYamlFormFields(String yamlContent) {
  final fields = <String>[];
  final lines = yamlContent.split('\n');
  String? currentId;
  String? currentLabel;

  void flush() {
    if (currentId == null) return;
    fields.add(
      currentLabel != null ? '$currentId ($currentLabel)' : currentId!,
    );
    currentId = null;
    currentLabel = null;
  }

  for (final line in lines) {
    final idMatch = RegExp(r'^\s*id:\s*([a-zA-Z0-9_-]+)').firstMatch(line);
    if (idMatch != null) {
      flush();
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

  flush();
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
    buffer.writeln('# Repository Conventions Orientation\n');
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
    _writeTemplatesSection(buffer);
    _writeSampleSection(
      buffer,
      'Sample Maintainer Issue Titles',
      sampleIssueTitles,
    );
    _writeSampleSection(buffer, 'Sample Merged PR / CL Titles', samplePrTitles);
    return buffer.toString().trimRight();
  }

  void _writeTemplatesSection(StringBuffer buffer) {
    if (detectedTemplates.isEmpty) return;
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

  void _writeSampleSection(
    StringBuffer buffer,
    String heading,
    List<String> samples,
  ) {
    if (samples.isEmpty) return;
    buffer.writeln('\n### $heading');
    for (final title in samples.take(5)) {
      buffer.writeln('- $title');
    }
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

    if (repo != null && repo.isNotEmpty) {
      return _gatherGitHub(
        targetDir,
        remoteRepo: repo,
        sampleLimit: sampleLimit,
      );
    }

    if (targetDir.contains('/google3') ||
        File(p.join(targetDir, 'WORKSPACE')).existsSync() ||
        Directory(p.join(targetDir, 'google3')).existsSync()) {
      return _gatherGoogle3(targetDir, sampleLimit: sampleLimit);
    }

    return _gatherGitHub(targetDir, sampleLimit: sampleLimit);
  }

  Future<RepositoryOrientation> _gatherGitHub(
    String targetDir, {
    String? remoteRepo,
    required int sampleLimit,
  }) async {
    final repoSlug = await _resolveRepoSlug(targetDir, remoteRepo);
    final repoArgs = repoSlug != null ? ['-R', repoSlug] : <String>[];

    final maintainers = <String>{};
    final prTitles = <String>[];
    final prPrefixCounts = <String, int>{};
    final prLabels = <String>{};

    await _fetchMergedPrs(
      targetDir,
      repoArgs,
      sampleLimit,
      maintainers,
      prTitles,
      prPrefixCounts,
      prLabels,
    );

    final issueTitles = <String>[];
    final issuePrefixCounts = <String, int>{};
    final issueLabels = <String>{};

    await _fetchIssues(
      targetDir,
      repoArgs,
      sampleLimit,
      issueTitles,
      issuePrefixCounts,
      issueLabels,
    );

    final detectedTemplates = <String>[];
    final templateSchemas = <String, List<String>>{};

    await _scanTemplates(
      targetDir,
      remoteRepo,
      detectedTemplates,
      templateSchemas,
    );

    return RepositoryOrientation(
      environment: 'GitHub',
      repoSlug: repoSlug,
      maintainers: maintainers.toList(),
      commonIssuePrefixes: _sortPrefixes(issuePrefixCounts),
      commonPrPrefixes: _sortPrefixes(prPrefixCounts),
      detectedLabels: {...issueLabels, ...prLabels}.toList(),
      detectedTemplates: detectedTemplates,
      templateSchemas: templateSchemas,
      sampleIssueTitles: issueTitles,
      samplePrTitles: prTitles,
    );
  }

  Future<String?> _resolveRepoSlug(String targetDir, String? remoteRepo) async {
    if (remoteRepo != null) return remoteRepo;
    try {
      final repoViewOut = await runCmd('gh', [
        'repo',
        'view',
        '--json',
        'nameWithOwner',
      ], workingDirectory: targetDir);
      final json = jsonDecode(repoViewOut) as Map<String, dynamic>;
      return json['nameWithOwner'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchMergedPrs(
    String targetDir,
    List<String> repoArgs,
    int sampleLimit,
    Set<String> maintainers,
    List<String> prTitles,
    Map<String, int> prPrefixCounts,
    Set<String> prLabels,
  ) async {
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
        _addMaintainer(maintainers, pr['author']);

        final reviews = pr['reviews'] as List<dynamic>?;
        if (reviews != null) {
          for (final review in reviews) {
            if (review is Map<String, dynamic>) {
              _addMaintainer(maintainers, review['author']);
            }
          }
        }

        _recordTitle(pr['title'] as String?, prTitles, prPrefixCounts);
        prLabels.addAll(_extractLabels(pr['labels'] as List<dynamic>?));
      }
    } catch (_) {}
  }

  void _addMaintainer(Set<String> maintainers, dynamic authorMap) {
    if (authorMap is Map<String, dynamic>) {
      final login = authorMap['login'] as String?;
      if (login != null && login.isNotEmpty && !isBotAccount(login)) {
        maintainers.add(login);
      }
    }
  }

  Future<void> _fetchIssues(
    String targetDir,
    List<String> repoArgs,
    int sampleLimit,
    List<String> issueTitles,
    Map<String, int> issuePrefixCounts,
    Set<String> issueLabels,
  ) async {
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
        _recordTitle(issue['title'] as String?, issueTitles, issuePrefixCounts);
        issueLabels.addAll(_extractLabels(issue['labels'] as List<dynamic>?));
      }
    } catch (_) {}
  }

  Future<void> _scanTemplates(
    String targetDir,
    String? remoteRepo,
    List<String> detectedTemplates,
    Map<String, List<String>> templateSchemas,
  ) async {
    if (remoteRepo != null) {
      await _scanRemoteTemplates(
        targetDir,
        remoteRepo,
        detectedTemplates,
        templateSchemas,
      );
    } else {
      _scanLocalTemplates(targetDir, detectedTemplates, templateSchemas);
    }
  }

  Future<void> _scanRemoteTemplates(
    String targetDir,
    String remoteRepo,
    List<String> detectedTemplates,
    Map<String, List<String>> templateSchemas,
  ) async {
    final remoteDirs = [
      '.github/ISSUE_TEMPLATE',
      '.github/PULL_REQUEST_TEMPLATE',
    ];
    for (final remoteDir in remoteDirs) {
      try {
        final apiOut = await runCmd('gh', [
          'api',
          'repos/$remoteRepo/contents/$remoteDir',
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
                await _fetchRemoteYamlSchema(
                  targetDir,
                  remoteRepo,
                  path,
                  templateSchemas,
                );
              }
            }
          }
        }
      } catch (_) {}
    }

    try {
      final prFileOut = await runCmd('gh', [
        'api',
        'repos/$remoteRepo/contents/.github/pull_request_template.md',
      ], workingDirectory: targetDir);
      final json = jsonDecode(prFileOut) as Map<String, dynamic>;
      if (json['path'] != null) {
        detectedTemplates.add('.github/pull_request_template.md');
      }
    } catch (_) {}
  }

  Future<void> _fetchRemoteYamlSchema(
    String targetDir,
    String remoteRepo,
    String path,
    Map<String, List<String>> templateSchemas,
  ) async {
    try {
      final content = await runCmd('gh', [
        'api',
        'repos/$remoteRepo/contents/$path',
        '--jq',
        '.content',
      ], workingDirectory: targetDir);
      final decoded = utf8.decode(
        base64.decode(content.replaceAll(RegExp(r'\s+'), '')),
      );
      final fields = extractYamlFormFields(decoded);
      if (fields.isNotEmpty) {
        templateSchemas[path] = fields;
      }
    } catch (_) {}
  }

  void _scanLocalTemplates(
    String targetDir,
    List<String> detectedTemplates,
    Map<String, List<String>> templateSchemas,
  ) {
    final templateDirs = [
      p.join(targetDir, '.github', 'ISSUE_TEMPLATE'),
      p.join(targetDir, '.github', 'PULL_REQUEST_TEMPLATE'),
    ];
    for (final dirPath in templateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        _processLocalTemplateFile(
          file,
          targetDir,
          detectedTemplates,
          templateSchemas,
        );
      }
    }
    final rootPrTemplate = File(
      p.join(targetDir, '.github', 'pull_request_template.md'),
    );
    if (rootPrTemplate.existsSync()) {
      detectedTemplates.add('.github/pull_request_template.md');
    }
  }

  void _processLocalTemplateFile(
    File file,
    String targetDir,
    List<String> detectedTemplates,
    Map<String, List<String>> templateSchemas,
  ) {
    final rel = p.relative(file.path, from: targetDir);
    detectedTemplates.add(rel);
    if (!rel.endsWith('.yml') && !rel.endsWith('.yaml')) return;
    try {
      final fields = extractYamlFormFields(file.readAsStringSync());
      if (fields.isNotEmpty) {
        templateSchemas[rel] = fields;
      }
    } catch (_) {}
  }

  List<String> _sortPrefixes(Map<String, int> prefixCounts) {
    final sorted = prefixCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  Future<RepositoryOrientation> _gatherGoogle3(
    String targetDir, {
    required int sampleLimit,
  }) async {
    final maintainers = _findGoogle3Owners(targetDir);
    final sampleCls = await _fetchP4Changes(targetDir, sampleLimit);

    return RepositoryOrientation(
      environment: 'Google3 / Piper',
      repoSlug: targetDir,
      maintainers: maintainers,
      samplePrTitles: sampleCls,
    );
  }

  List<String> _findGoogle3Owners(String targetDir) {
    final maintainers = <String>{};
    Directory? curr = Directory(targetDir);
    while (curr != null && curr.path != curr.parent.path) {
      final ownersFile = File(p.join(curr.path, 'OWNERS'));
      if (ownersFile.existsSync()) {
        try {
          for (final line in ownersFile.readAsLinesSync()) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('#') &&
                !trimmed.startsWith('include ') &&
                !trimmed.contains('/') &&
                !trimmed.contains(' ') &&
                !trimmed.contains('=')) {
              maintainers.add(trimmed);
            }
          }
        } catch (_) {}
        break;
      }
      curr = curr.parent;
    }
    return maintainers.toList();
  }

  Future<List<String>> _fetchP4Changes(
    String targetDir,
    int sampleLimit,
  ) async {
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
    return sampleCls;
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
