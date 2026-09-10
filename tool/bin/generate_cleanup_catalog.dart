import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const startTag = '<!-- DART_CLEANUP_CATALOG_START -->';
const endTag = '<!-- DART_CLEANUP_CATALOG_END -->';

void main(List<String> arguments) {
  final parser = ArgParser()
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

  final results = parser.parse(arguments);
  final writeMode = results['write'] as bool;
  final validateMode = results['validate'] as bool;
  final checkEnvMode = results['check-env'] as bool;

  final repoRoot = _findRepoRoot(Directory.current);
  if (repoRoot == null) {
    stderr.writeln('Error: Could not find repository root containing skills.');
    exit(1);
  }

  final catalogJsonFile = File(
    p.join(repoRoot.path, 'tool', 'data', 'dart_cleanup_catalog.json'),
  );
  if (!catalogJsonFile.existsSync()) {
    stderr.writeln(
      'Error: Catalog JSON file not found at ${catalogJsonFile.path}',
    );
    exit(1);
  }

  final dynamic catalogData;
  try {
    catalogData = jsonDecode(catalogJsonFile.readAsStringSync());
  } catch (e) {
    stderr.writeln('Error parsing catalog JSON: $e');
    exit(1);
  }

  if (catalogData is! Map<String, dynamic>) {
    stderr.writeln('Error: Catalog JSON root must be a JSON object.');
    exit(1);
  }

  final repositories =
      catalogData['repositories'] as Map<String, dynamic>? ?? {};
  final categories = catalogData['categories'] as List<dynamic>? ?? [];

  // Check environment & local system setup
  final envIssues = checkLocalEnvironment(repositories, categories);
  if (envIssues.isNotEmpty) {
    print('------------------------------------------------------------');
    print('🔍 Local System Environment Audit:');
    for (final issue in envIssues) {
      print(issue);
    }
    print('------------------------------------------------------------');
  }

  if (checkEnvMode) {
    if (envIssues.any(
      (i) =>
          i.contains('⚠️ [UNCATALOGED SKILL]') ||
          i.contains('⚠️ [MISSING SKILL]'),
    )) {
      exit(1);
    }
    exit(0);
  }

  // Validate catalog data structure and sorting
  final validationErrors = validateCatalogStructure(categories);
  if (validationErrors.isNotEmpty) {
    stderr.writeln('Catalog validation errors:');
    for (final err in validationErrors) {
      stderr.writeln('  * $err');
    }
    exit(1);
  }

  // Generate markdown
  final generatedMarkdown = generateCatalogMarkdown(categories, repositories);

  final targetSkillFile = File(
    p.join(repoRoot.path, 'skills', 'dart-cleanup', 'SKILL.md'),
  );
  if (!targetSkillFile.existsSync()) {
    stderr.writeln('Error: SKILL.md not found at ${targetSkillFile.path}');
    exit(1);
  }

  final skillContent = targetSkillFile.readAsStringSync();
  final startIndex = skillContent.indexOf(startTag);
  final endIndex = startIndex == -1
      ? -1
      : skillContent.indexOf(endTag, startIndex);

  if (startIndex == -1 || endIndex == -1) {
    stderr.writeln(
      'Error: Could not find markers $startTag and $endTag in ${targetSkillFile.path}',
    );
    stderr.writeln(
      'Please add the markers around the catalog section in SKILL.md.',
    );
    exit(1);
  }

  final updatedContent = skillContent.replaceRange(
    startIndex,
    endIndex + endTag.length,
    '$startTag\n$generatedMarkdown\n$endTag',
  );

  if (validateMode) {
    final normalizedOriginal = skillContent.replaceAll('\r\n', '\n');
    final normalizedUpdated = updatedContent.replaceAll('\r\n', '\n');
    if (normalizedOriginal == normalizedUpdated) {
      print('skills/dart-cleanup/SKILL.md catalog is up-to-date!');
      exit(0);
    } else {
      stderr.writeln(
        'Error: skills/dart-cleanup/SKILL.md catalog is out-of-date.',
      );
      stderr.writeln(
        'Run `dart tool/bin/generate_cleanup_catalog.dart --write` to update it.',
      );
      exit(1);
    }
  }

  if (writeMode) {
    targetSkillFile.writeAsStringSync(updatedContent);
    print(
      'Successfully updated skills/dart-cleanup/SKILL.md with latest catalog!',
    );
  } else {
    print('--- Generated Catalog Markdown ---');
    print(generatedMarkdown);
    print('----------------------------------');
    print(
      'Run with --write (or -w) to save changes to skills/dart-cleanup/SKILL.md.',
    );
  }
}

List<String> checkLocalEnvironment(
  Map<String, dynamic> repositories,
  List<dynamic> categories,
) {
  final issues = <String>[];
  final home = Platform.environment['HOME'] ?? '';
  final allConfiguredSkills = <String, String>{}; // skill -> repoKey

  for (final cat in categories) {
    if (cat is Map<String, dynamic>) {
      final skills = cat['skills'] as List<dynamic>? ?? [];
      for (final s in skills) {
        if (s is Map<String, dynamic>) {
          final name = s['name'] as String? ?? '';
          final repo = s['repo'] as String? ?? '';
          if (name.isNotEmpty) {
            allConfiguredSkills[name] = repo;
          }
        }
      }
    }
  }

  for (final entry in repositories.entries) {
    final repoKey = entry.key;
    final repoConfig = entry.value as Map<String, dynamic>;
    final rawPath = repoConfig['path'] as String? ?? '';
    final cloneUrl = repoConfig['cloneUrl'] as String? ?? '';
    final resolvedPath = rawPath.replaceFirst('~', home);
    final repoDir = Directory(resolvedPath);

    if (!repoDir.existsSync()) {
      issues.add(
        '⚠️ [MISSING REPO] Repository "$repoKey" not found at $resolvedPath\n'
        '   Fix: Clone it via:\n'
        '   git clone $cloneUrl $resolvedPath\n',
      );
      continue;
    }

    final skillsDir = Directory(p.join(repoDir.path, 'skills'));
    if (!skillsDir.existsSync()) {
      continue;
    }

    // Find all skills on disk in this repo
    final onDiskSkills = <String>{};
    for (final child in skillsDir.listSync().whereType<Directory>()) {
      final skillFile = File(p.join(child.path, 'SKILL.md'));
      if (skillFile.existsSync()) {
        final skillName = p.basename(child.path);
        onDiskSkills.add(skillName);

        if (!allConfiguredSkills.containsKey(skillName)) {
          issues.add(
            '⚠️ [UNCATALOGED SKILL] Found skill "$skillName" in "$repoKey" not listed in tool/data/dart_cleanup_catalog.json.\n'
            '   Fix: Add "$skillName" to a category in tool/data/dart_cleanup_catalog.json with a summary.\n',
          );
        }
      }
    }

    // Check skills configured for this repo in JSON exist on disk
    for (final skillEntry in allConfiguredSkills.entries) {
      if (skillEntry.value == repoKey) {
        final skillName = skillEntry.key;
        if (!onDiskSkills.contains(skillName)) {
          issues.add(
            '⚠️ [MISSING SKILL] Skill "$skillName" configured for "$repoKey" was not found on disk at ${p.join(skillsDir.path, skillName, 'SKILL.md')}\n'
            '   Fix: Verify the skill exists in the repo or remove it from tool/data/dart_cleanup_catalog.json.\n',
          );
        }
      }
    }
  }

  return issues;
}

List<String> validateCatalogStructure(List<dynamic> categories) {
  final errors = <String>[];
  final seenSkills = <String>{};

  for (final cat in categories) {
    if (cat is! Map<String, dynamic>) {
      errors.add('Category entry must be a JSON object: $cat');
      continue;
    }
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
      if (name.isEmpty) {
        errors.add('Skill missing name in category "$catName"');
        continue;
      }
      if (seenSkills.contains(name)) {
        errors.add('Duplicate skill "$name" found across categories.');
      }
      seenSkills.add(name);

      if (prevSkillName != null && name.compareTo(prevSkillName) < 0) {
        errors.add(
          'Skills in category "$catName" must be sorted alphabetically: "$name" should appear before "$prevSkillName".',
        );
      }
      prevSkillName = name;
    }
  }

  return errors;
}

String generateCatalogMarkdown(
  List<dynamic> categories,
  Map<String, dynamic> repositories,
) {
  final buffer = StringBuffer();
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
