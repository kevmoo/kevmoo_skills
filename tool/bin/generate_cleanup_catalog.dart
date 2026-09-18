import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

const startTag = '<!-- DART_CLEANUP_CATALOG_START -->';
const endTag = '<!-- DART_CLEANUP_CATALOG_END -->';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

ArgParser _buildArgParser() => ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print usage information.',
  )
  ..addFlag(
    'write',
    abbr: 'w',
    negatable: false,
    help: 'Writes the updated catalog to skills/dart-cleanup/SKILL.md.',
  )
  ..addFlag(
    'validate',
    negatable: false,
    help: 'Validates that dart-cleanup/SKILL.md is up-to-date and sorted.',
  )
  ..addFlag(
    'check-env',
    negatable: false,
    help: 'Checks local repositories for missing or uncataloged skills.',
  );

int _run(List<String> arguments) {
  final parser = _buildArgParser();

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln('Error: ${e.message}\n')
      ..writeln('Usage: dart tool/bin/generate_cleanup_catalog.dart [flags]\n')
      ..writeln(parser.usage);
    return ExitCode.usage.code;
  }

  if (results.flag('help')) {
    stdout
      ..writeln(
        'Generates and validates the dart-cleanup skill routing catalog.\n',
      )
      ..writeln('Usage: dart tool/bin/generate_cleanup_catalog.dart [flags]\n')
      ..writeln(parser.usage);
    return ExitCode.success.code;
  }

  final repoRoot = _findRepoRoot(Directory.current);
  if (repoRoot == null) {
    stderr.writeln('Error: Could not find repository root containing skills.');
    return ExitCode.config.code;
  }

  final loaded = _loadCatalogJson(repoRoot);
  if (loaded.exitCode != null) {
    return loaded.exitCode!;
  }
  final catalogJsonFile = loaded.file!;
  final catalogData = loaded.data!;
  final repositories =
      catalogData['repositories'] as Map<String, dynamic>? ?? {};
  final categories = catalogData['categories'] as List<dynamic>? ?? [];

  final envIssues = checkLocalEnvironment(repositories, categories);
  _printEnvIssues(envIssues);

  if (results.flag('check-env')) {
    return envIssues.any((i) => i.isFatal)
        ? ExitCode.config.code
        : ExitCode.success.code;
  }

  final writeMode = results.flag('write');
  if (writeMode) {
    _syncRepositoryCommits(repositories);
    const encoder = JsonEncoder.withIndent('  ');
    catalogJsonFile.writeAsStringSync('${encoder.convert(catalogData)}\n');
  }

  final validationErrors = validateCatalogStructure(categories, repositories);
  if (validationErrors.isNotEmpty) {
    stderr.writeln('Catalog validation errors:');
    for (final err in validationErrors) {
      stderr.writeln('  * $err');
    }
    return ExitCode.data.code;
  }

  final generatedMarkdown = generateCatalogMarkdown(categories, repositories);
  return _applySkillCatalogUpdate(
    repoRoot,
    generatedMarkdown,
    writeMode: writeMode,
    validateMode: results.flag('validate'),
  );
}

({File? file, Map<String, dynamic>? data, int? exitCode}) _loadCatalogJson(
  Directory repoRoot,
) {
  final catalogJsonFile = File(
    p.join(repoRoot.path, 'tool', 'data', 'dart_cleanup_catalog.json'),
  );
  if (!catalogJsonFile.existsSync()) {
    stderr.writeln(
      'Error: Catalog JSON file not found at ${catalogJsonFile.path}',
    );
    return (file: null, data: null, exitCode: ExitCode.config.code);
  }

  final dynamic catalogData;
  try {
    catalogData = jsonDecode(catalogJsonFile.readAsStringSync());
  } catch (e) {
    stderr.writeln('Error parsing catalog JSON: $e');
    return (file: null, data: null, exitCode: ExitCode.data.code);
  }

  if (catalogData is! Map<String, dynamic>) {
    stderr.writeln('Error: Catalog JSON root must be a JSON object.');
    return (file: null, data: null, exitCode: ExitCode.data.code);
  }

  return (file: catalogJsonFile, data: catalogData, exitCode: null);
}

void _printEnvIssues(List<EnvIssue> envIssues) {
  if (envIssues.isEmpty) return;
  stderr.writeln(
    '------------------------------------------------------------',
  );
  stderr.writeln('🔍 Local System Environment Audit:');
  for (final issue in envIssues) {
    stderr.writeln(issue);
  }
  stderr.writeln(
    '------------------------------------------------------------',
  );
}

int _applySkillCatalogUpdate(
  Directory repoRoot,
  String generatedMarkdown, {
  required bool writeMode,
  required bool validateMode,
}) {
  final targetSkillFile = File(
    p.join(repoRoot.path, 'skills', 'dart-cleanup', 'SKILL.md'),
  );
  if (!targetSkillFile.existsSync()) {
    stderr.writeln('Error: SKILL.md not found at ${targetSkillFile.path}');
    return ExitCode.config.code;
  }

  final skillContent = targetSkillFile.readAsStringSync();
  final startIndex = skillContent.indexOf(startTag);
  final endIndex = startIndex == -1
      ? -1
      : skillContent.indexOf(endTag, startIndex);

  if (startIndex == -1 || endIndex == -1) {
    stderr
      ..writeln(
        'Error: Could not find markers $startTag and $endTag in ${targetSkillFile.path}',
      )
      ..writeln(
        'Please add the markers around the catalog section in SKILL.md.',
      );
    return ExitCode.data.code;
  }

  final updatedContent = skillContent.replaceRange(
    startIndex,
    endIndex + endTag.length,
    '$startTag\n\n<!-- prettier-ignore-start -->\n\n$generatedMarkdown\n\n<!-- prettier-ignore-end -->\n\n$endTag',
  );

  if (validateMode) {
    final normalizedOriginal = skillContent.replaceAll('\r\n', '\n');
    final normalizedUpdated = updatedContent.replaceAll('\r\n', '\n');
    if (normalizedOriginal == normalizedUpdated) {
      stdout.writeln('skills/dart-cleanup/SKILL.md catalog is up-to-date!');
      return ExitCode.success.code;
    }
    stderr
      ..writeln('Error: skills/dart-cleanup/SKILL.md catalog is out-of-date.')
      ..writeln(
        'Run `dart tool/bin/generate_cleanup_catalog.dart --write` to update it.',
      );
    return ExitCode.data.code;
  }

  if (writeMode) {
    targetSkillFile.writeAsStringSync(updatedContent);
    stdout.writeln(
      'Successfully updated skills/dart-cleanup/SKILL.md and catalog JSON with latest catalog!',
    );
  } else {
    stdout
      ..writeln('--- Generated Catalog Markdown ---')
      ..writeln(generatedMarkdown)
      ..writeln('----------------------------------')
      ..writeln(
        'Run with --write (or -w) to save changes to skills/dart-cleanup/SKILL.md.',
      );
  }
  return ExitCode.success.code;
}

Directory _resolveRepoDir(Map<String, dynamic> repoConfig, String home) {
  final rawPath = repoConfig['path'] as String? ?? '';
  return Directory(rawPath.replaceFirst('~', home));
}

void _syncRepositoryCommits(Map<String, dynamic> repositories) {
  final home = Platform.environment['HOME'] ?? '';
  for (final entry in repositories.entries) {
    final repoConfig = entry.value as Map<String, dynamic>;
    final repoDir = _resolveRepoDir(repoConfig, home);
    final resolvedPath = repoDir.path;

    if (!repoDir.existsSync()) continue;

    final shaResult = Process.runSync('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: resolvedPath);
    if (shaResult.exitCode == 0) {
      final sha = shaResult.stdout.toString().trim();
      if (sha.isNotEmpty) {
        repoConfig['commitSha'] = sha;
      }
    }

    final dateResult = Process.runSync('git', [
      'log',
      '-1',
      '--format=%cI',
    ], workingDirectory: resolvedPath);
    if (dateResult.exitCode == 0) {
      final date = dateResult.stdout.toString().trim();
      if (date.isNotEmpty) {
        repoConfig['commitDate'] = date;
      }
    }
  }
}

enum EnvIssueType {
  missingRepo('MISSING REPO', isFatal: false),
  notGitRepo('NOT A GIT REPO', isFatal: true),
  mismatchedRemote('MISMATCHED REPO REMOTE', isFatal: true),
  uncatalogedSkill('UNCATALOGED SKILL', isFatal: true),
  missingSkill('MISSING SKILL', isFatal: true);

  const EnvIssueType(this.tag, {required this.isFatal});

  final String tag;
  final bool isFatal;
}

class EnvIssue {
  const EnvIssue(this.type, this.message, {this.fix});

  final EnvIssueType type;
  final String message;
  final String? fix;

  bool get isFatal => type.isFatal;

  @override
  String toString() {
    final buffer = StringBuffer('⚠️ [${type.tag}] $message\n');
    if (fix != null) {
      buffer.writeln('   Fix: $fix');
    }
    return buffer.toString();
  }
}

List<EnvIssue> checkLocalEnvironment(
  Map<String, dynamic> repositories,
  List<dynamic> categories,
) {
  final issues = <EnvIssue>[];
  final home = Platform.environment['HOME'] ?? '';
  final allConfiguredSkills = _collectConfiguredSkills(categories);

  for (final entry in repositories.entries) {
    final repoConfig = entry.value as Map<String, dynamic>;
    issues.addAll(
      _checkSingleRepository(entry.key, repoConfig, home, allConfiguredSkills),
    );
  }

  return issues;
}

Map<String, String> _collectConfiguredSkills(List<dynamic> categories) {
  final allConfiguredSkills = <String, String>{};
  for (final cat in categories.whereType<Map<String, dynamic>>()) {
    final skills = cat['skills'] as List<dynamic>? ?? [];
    for (final s in skills.whereType<Map<String, dynamic>>()) {
      final name = s['name'] as String? ?? '';
      final repo = s['repo'] as String? ?? '';
      if (name.isNotEmpty) {
        allConfiguredSkills[name] = repo;
      }
    }
  }
  return allConfiguredSkills;
}

List<EnvIssue> _checkSingleRepository(
  String repoKey,
  Map<String, dynamic> repoConfig,
  String home,
  Map<String, String> allConfiguredSkills,
) {
  final cloneUrl = repoConfig['cloneUrl'] as String? ?? '';
  final repoDir = _resolveRepoDir(repoConfig, home);
  final resolvedPath = repoDir.path;

  if (!repoDir.existsSync()) {
    return [
      EnvIssue(
        EnvIssueType.missingRepo,
        'Repository "$repoKey" not found at $resolvedPath',
        fix: 'Clone it via:\n   git clone $cloneUrl $resolvedPath',
      ),
    ];
  }

  final gitCheck = Process.runSync('git', [
    'rev-parse',
    '--is-inside-work-tree',
  ], workingDirectory: resolvedPath);
  if (gitCheck.exitCode != 0) {
    return [
      EnvIssue(
        EnvIssueType.notGitRepo,
        'Directory at $resolvedPath is not a git repository.',
        fix: 'Ensure a valid git clone of $cloneUrl is placed at $resolvedPath',
      ),
    ];
  }

  final issues = <EnvIssue>[];
  final remoteIssue = _checkRemoteOrigin(resolvedPath, cloneUrl);
  if (remoteIssue != null) {
    issues.add(remoteIssue);
  }

  final skillsDir = Directory(p.join(repoDir.path, 'skills'));
  if (skillsDir.existsSync()) {
    issues.addAll(
      _auditRepositorySkills(repoKey, skillsDir, allConfiguredSkills),
    );
  }
  return issues;
}

EnvIssue? _checkRemoteOrigin(String resolvedPath, String cloneUrl) {
  final remoteCheck = Process.runSync('git', [
    'config',
    '--get',
    'remote.origin.url',
  ], workingDirectory: resolvedPath);
  if (remoteCheck.exitCode != 0) return null;

  final actualUrl = remoteCheck.stdout.toString().trim();
  final actualSlug = parseRepoSlugFromUrl(actualUrl);
  final expectedSlug = parseRepoSlugFromUrl(cloneUrl);
  if (actualSlug != null &&
      expectedSlug != null &&
      actualSlug != expectedSlug) {
    return EnvIssue(
      EnvIssueType.mismatchedRemote,
      'Directory "$resolvedPath" points to remote "$actualUrl" ($actualSlug),\n'
      '   expected "$cloneUrl" ($expectedSlug).',
      fix: 'Ensure the correct repository is checked out at $resolvedPath',
    );
  }
  return null;
}

List<EnvIssue> _auditRepositorySkills(
  String repoKey,
  Directory skillsDir,
  Map<String, String> allConfiguredSkills,
) {
  final issues = <EnvIssue>[];
  final onDiskSkills = <String>{};
  for (final child in skillsDir.listSync().whereType<Directory>()) {
    final skillFile = File(p.join(child.path, 'SKILL.md'));
    if (!skillFile.existsSync()) continue;
    final skillName = p.basename(child.path);
    onDiskSkills.add(skillName);

    if (!allConfiguredSkills.containsKey(skillName)) {
      issues.add(
        EnvIssue(
          EnvIssueType.uncatalogedSkill,
          'Found skill "$skillName" in "$repoKey" not listed in tool/data/dart_cleanup_catalog.json.',
          fix:
              'Add "$skillName" to a category in tool/data/dart_cleanup_catalog.json with a summary.',
        ),
      );
    }
  }

  for (final skillEntry in allConfiguredSkills.entries) {
    if (skillEntry.value == repoKey && !onDiskSkills.contains(skillEntry.key)) {
      final skillName = skillEntry.key;
      issues.add(
        EnvIssue(
          EnvIssueType.missingSkill,
          'Skill "$skillName" configured for "$repoKey" was not found on disk at ${p.join(skillsDir.path, skillName, 'SKILL.md')}',
          fix:
              'Verify the skill exists in the repo or remove it from tool/data/dart_cleanup_catalog.json.',
        ),
      );
    }
  }
  return issues;
}

List<String> validateCatalogStructure(
  List<dynamic> categories,
  Map<String, dynamic> repositories,
) {
  final errors = <String>[..._validateRepositories(repositories)];
  final seenSkills = <String>{};

  for (final cat in categories) {
    errors.addAll(_validateCategory(cat, repositories, seenSkills));
  }

  return errors;
}

List<String> _validateRepositories(Map<String, dynamic> repositories) {
  final errors = <String>[];
  for (final entry in repositories.entries) {
    final key = entry.key;
    final config = entry.value;
    if (config is! Map<String, dynamic>) {
      errors.add('Repository "$key" configuration must be a JSON object.');
      continue;
    }
    final rawPath = config['path'] as String? ?? '';
    final cloneUrl = config['cloneUrl'] as String? ?? '';
    if (rawPath.isEmpty) {
      errors.add('Repository "$key" missing "path".');
    }
    if (cloneUrl.isEmpty) {
      errors.add('Repository "$key" missing "cloneUrl".');
    } else if (parseRepoSlugFromUrl(cloneUrl) == null) {
      errors.add(
        'Repository "$key" cloneUrl "$cloneUrl" is not a valid GitHub URL.',
      );
    }
  }
  return errors;
}

List<String> _validateCategory(
  dynamic cat,
  Map<String, dynamic> repositories,
  Set<String> seenSkills,
) {
  if (cat is! Map<String, dynamic>) {
    return ['Category entry must be a JSON object: $cat'];
  }
  final errors = <String>[];
  final catName = cat['name'] as String? ?? '';
  if (catName.isEmpty) {
    errors.add('Category missing name: $cat');
  }

  final skills = cat['skills'] as List<dynamic>? ?? [];
  String? prevSkillName;
  for (final s in skills) {
    if (s is! Map<String, dynamic>) {
      errors.add(
        'Skill entry must be a JSON object: $s in category "$catName"',
      );
      continue;
    }
    final name = s['name'] as String? ?? '';
    final repo = s['repo'] as String? ?? '';
    if (name.isEmpty) {
      errors.add('Skill missing name in category "$catName"');
      continue;
    }
    if (!repositories.containsKey(repo)) {
      errors.add(
        'Skill "$name" references unknown repository key "$repo" in category "$catName".',
      );
    }
    if (!seenSkills.add(name)) {
      errors.add('Duplicate skill "$name" found across categories.');
    }
    if (prevSkillName != null && name.compareTo(prevSkillName) < 0) {
      errors.add(
        'Skills in category "$catName" must be sorted alphabetically: "$name" should appear before "$prevSkillName".',
      );
    }
    prevSkillName = name;
  }
  return errors;
}

String generateCatalogMarkdown(
  List<dynamic> categories,
  Map<String, dynamic> repositories,
) {
  final buffer = StringBuffer();

  // 1. Required Local Repositories table
  buffer.writeln('### Required Local Repositories');
  buffer.writeln();
  buffer.writeln('<!-- mdformat off(prevent table wrapping) -->');
  buffer.writeln('| Repository | Local Directory | Synced Commit |');
  buffer.writeln('| :--- | :--- | :--- |');

  final sortedEntries = repositories.entries.toList()
    ..sort((a, b) {
      final slugA =
          parseRepoSlugFromUrl(a.value['cloneUrl'] as String? ?? '') ?? a.key;
      final slugB =
          parseRepoSlugFromUrl(b.value['cloneUrl'] as String? ?? '') ?? b.key;
      return slugA.compareTo(slugB);
    });

  for (final entry in sortedEntries) {
    final config = entry.value as Map<String, dynamic>;
    final cloneUrl = config['cloneUrl'] as String? ?? '';
    final rawPath = config['path'] as String? ?? '';
    final slug = parseRepoSlugFromUrl(cloneUrl) ?? entry.key;
    final commitSha = config['commitSha'] as String?;

    final webUrl = 'https://github.com/$slug';
    final repoLink = '[`$slug`]($webUrl)';
    final commitLink = commitSha != null && commitSha.length >= 7
        ? '[`${commitSha.substring(0, 7)}`]($webUrl/commit/$commitSha)'
        : '*(unpinned)*';

    buffer.writeln('| $repoLink | `$rawPath` | $commitLink |');
  }

  buffer.writeln('<!-- mdformat on -->');
  buffer.writeln();

  // 2. Categorized Skills
  const letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  for (var i = 0; i < categories.length; i++) {
    final cat = categories[i] as Map<String, dynamic>;
    final catName = cat['name'] as String;
    final letter = i < letters.length ? letters[i] : '${i + 1}';
    final skills = cat['skills'] as List<dynamic>? ?? [];

    buffer.writeln('### $letter. $catName');

    for (final s in skills) {
      final skill = s as Map<String, dynamic>;
      final name = skill['name'] as String;
      final repoKey = skill['repo'] as String;
      final summary = skill['summary'] as String;

      final repoConfig = repositories[repoKey] as Map<String, dynamic>?;
      final rawRepoPath = repoConfig?['path'] as String? ?? '~/github/$repoKey';
      final skillPath = '$rawRepoPath/skills/$name/SKILL.md';

      final entry = _formatSkillEntry(
        name: name,
        summary: summary,
        path: skillPath,
      );
      buffer.write(entry);
    }

    if (i < categories.length - 1) {
      buffer.writeln();
    }
  }

  return buffer.toString().trimRight();
}

String _formatSkillEntry({
  required String name,
  required String summary,
  required String path,
}) {
  final buffer = StringBuffer();
  final lead = '* **`$name`**: ';
  final wrappedSummary = _wrapProse(lead, summary, indent: '  ', maxWidth: 80);
  buffer.writeln(wrappedSummary);
  buffer.writeln('  * *Path*: `$path`');
  return buffer.toString();
}

String _wrapProse(
  String lead,
  String text, {
  required String indent,
  int maxWidth = 80,
}) {
  final words = text.split(RegExp(r'\s+'));
  final lines = <String>[];
  var currentLine = lead;

  for (final word in words) {
    if (currentLine.isEmpty) {
      currentLine = indent + word;
    } else if (currentLine.length + 1 + word.length <= maxWidth) {
      if (currentLine == lead) {
        currentLine += word;
      } else {
        currentLine += ' $word';
      }
    } else {
      lines.add(currentLine);
      currentLine = '$indent$word';
    }
  }
  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }
  return lines.join('\n');
}

String? parseRepoSlugFromUrl(String rawUrl) {
  var url = rawUrl.trim();
  if (!url.contains('://') && url.contains('@') && url.contains(':')) {
    url = 'ssh://${url.replaceFirst(':', '/')}';
  }

  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.toLowerCase() != 'github.com') {
    return null;
  }

  if (uri.pathSegments.where((s) => s.isNotEmpty).toList() case [
    final owner,
    var repo,
    ...,
  ]) {
    if (repo.endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }
    if (owner.isNotEmpty && repo.isNotEmpty) {
      return '$owner/$repo';
    }
  }

  return null;
}

Directory? _findRepoRoot(Directory startDir) {
  var dir = startDir;
  while (true) {
    if (Directory(p.join(dir.path, 'skills')).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}
