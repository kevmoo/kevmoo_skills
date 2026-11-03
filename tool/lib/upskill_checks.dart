import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Hard `view_file` / `read_file` per-call truncation ceiling in bytes.
const int hardMaxViewFileBytes = 46080;

/// Maximum character budget for `SKILL.md` per `AGENT_DOCS_STANDARDS.md`.
const int maxSkillMarkdownChars = 25000;

/// Stopwords ignored when deriving topic tokens from `references/<topic>.md`.
const Set<String> refTopicStopwords = {
  'skill',
  'skills',
  'reference',
  'references',
  'guide',
  'guides',
  'doc',
  'docs',
  'notes',
  'overview',
  'common',
  'general',
  'example',
  'examples',
};

final RegExp _inlineCodeSpanRe = RegExp(r'`[^`\n]+`');
final RegExp _cliBinaryRe = RegExp(
  r'/google/bin/releases/[a-zA-Z0-9_-][a-zA-Z0-9_./-]*',
);
final RegExp _delegatedSkillRefRe = RegExp(
  r'\bsee\s+[^\n|]*(?:SKILL\.md|references/[a-zA-Z0-9_.-]+\.md)',
  caseSensitive: false,
);
final RegExp _mdOnlyPathSpanRe = RegExp(
  r'^`(?:[a-zA-Z0-9_./-]*\.md)`$',
  caseSensitive: false,
);
final RegExp _flagTokenRe = RegExp(r'--[a-zA-Z][a-zA-Z0-9_-]+');
final RegExp _skillRelPathTokenRe = RegExp(
  r'\b(?:scripts|references)/[a-zA-Z0-9_][a-zA-Z0-9_./-]*',
);
final RegExp _allowDropCommentRe = RegExp(
  r'<!--\s*allow-drop:\s*([^-]+?)-->',
  caseSensitive: false,
);
final RegExp _trailingPunctRe = RegExp(r'[.,;:)/]+$');

/// Represents a single static diagnostic finding on a skill file.
class SkillStaticFinding {
  final String code;
  final String skillName;
  final String file;
  final String message;

  const SkillStaticFinding({
    required this.code,
    required this.skillName,
    required this.file,
    required this.message,
  });

  @override
  String toString() => '[$code] $skillName ($file): $message';
}

/// Result of a `P5.1` Zero-Content-Loss corpus token-set comparison.
class CorpusDiffResult {
  final Set<String> missingFlags;
  final Set<String> missingPaths;

  const CorpusDiffResult({
    required this.missingFlags,
    required this.missingPaths,
  });

  bool get passed => missingFlags.isEmpty && missingPaths.isEmpty;

  @override
  String toString() =>
      'CorpusDiffResult(passed: $passed, '
      'missingFlags: $missingFlags, missingPaths: $missingPaths)';
}

/// Checks `P1.1` (`SKILL.md` byte/char budgets) and `P1.2` (`references/*.md`
/// byte ceiling) for a skill directory.
List<SkillStaticFinding> checkSkillSizeBudgets(
  Directory skillDir, {
  int maxSkillChars = maxSkillMarkdownChars,
  int maxBytes = hardMaxViewFileBytes,
}) {
  final skillName = p.basename(skillDir.path);
  final findings = <SkillStaticFinding>[];
  final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
  if (skillFile.existsSync()) {
    final bytes = skillFile.readAsBytesSync();
    final content = utf8.decode(bytes);
    if (bytes.length > maxBytes) {
      findings.add(
        SkillStaticFinding(
          code: 'P1.1',
          skillName: skillName,
          file: 'SKILL.md',
          message:
              'SKILL.md is ${bytes.length} bytes '
              '(> $maxBytes view_file byte ceiling).',
        ),
      );
    }
    if (content.length > maxSkillChars) {
      findings.add(
        SkillStaticFinding(
          code: 'P1.1',
          skillName: skillName,
          file: 'SKILL.md',
          message:
              'SKILL.md is ${content.length} chars '
              '(> $maxSkillChars char ceiling).',
        ),
      );
    }
  }
  findings.addAll(_checkReferenceSizeBudgets(skillDir, skillName, maxBytes));
  return findings;
}

List<SkillStaticFinding> _checkReferenceSizeBudgets(
  Directory skillDir,
  String skillName,
  int maxBytes,
) {
  final refsDir = Directory(p.join(skillDir.path, 'references'));
  if (!refsDir.existsSync()) return const [];
  final findings = <SkillStaticFinding>[];
  for (final file in _listMarkdownFiles(refsDir)) {
    final relPath = 'references/${p.basename(file.path)}';
    final byteLen = file.lengthSync();
    if (byteLen > maxBytes) {
      findings.add(
        SkillStaticFinding(
          code: 'P1.2',
          skillName: skillName,
          file: relPath,
          message:
              '$relPath is $byteLen bytes '
              '(> $maxBytes view_file byte ceiling).',
        ),
      );
    }
  }
  return findings;
}

/// Detects `P2.1`: Markdown table rows outside code fences that combine a
/// flagless CLI command stub with a `see ...SKILL.md` or `see references/...md`
/// pointer.
List<String> findIncompleteQuickStartDelegations(String markdown) {
  final badRows = <String>[];
  var inFence = false;
  for (final line in const LineSplitter().convert(markdown)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || !trimmed.contains('|') || trimmed.contains('--')) {
      continue;
    }
    if (_delegatedSkillRefRe.hasMatch(trimmed) && _hasCliCommandStub(trimmed)) {
      badRows.add(trimmed);
    }
  }
  return badRows;
}

bool _hasCliCommandStub(String tableRow) {
  if (_cliBinaryRe.hasMatch(tableRow)) return true;
  for (final match in _inlineCodeSpanRe.allMatches(tableRow)) {
    final span = match.group(0)!;
    if (!_mdOnlyPathSpanRe.hasMatch(span)) {
      return true;
    }
  }
  return false;
}

/// Extracts the YAML frontmatter `description:` string from `SKILL.md` content.
String extractYamlDescription(String skillMdContent) {
  final trimmed = skillMdContent.trimLeft();
  if (!trimmed.startsWith('---')) return '';
  final dashRe = RegExp(r'^---[ \t]*\r?$', multiLine: true);
  final matches = dashRe.allMatches(trimmed).toList();
  if (matches.length < 2 || matches.first.start != 0) return '';
  final yamlText = trimmed.substring(matches.first.end, matches[1].start);
  try {
    final loaded = loadYaml(yamlText);
    if (loaded is Map && loaded['description'] != null) {
      return loaded['description'].toString().trim();
    }
  } on Object catch (_) {}
  return '';
}

/// Extracts `>= 4`-char non-stopword topic tokens from a reference filename.
List<String> extractReferenceTopicTokens(String refFileName) {
  final base = p.basename(refFileName);
  if (base == 'README.md' ||
      base == 'contributing.md' ||
      !base.endsWith('.md')) {
    return const [];
  }
  final stem = base.substring(0, base.length - 3).toLowerCase();
  return stem
      .split(RegExp(r'[_-\s]+'))
      .where((w) => w.length >= 4 && !refTopicStopwords.contains(w))
      .toList();
}

/// Checks `P3.4` (Anti-Frontmatter-Blindness): verifies that every
/// `references/<topic>.md` has at least one `>= 4`-char non-stopword token
/// represented in the skill's YAML `description:`.
List<String> findMissingReferenceTopics({
  required String description,
  required Iterable<String> referenceFileNames,
}) {
  final lowerDesc = description.toLowerCase();
  final missing = <String>[];
  for (final fileName in referenceFileNames) {
    final tokens = extractReferenceTopicTokens(fileName);
    if (tokens.isEmpty) continue;
    final hasMatch = tokens.any(lowerDesc.contains);
    if (!hasMatch) {
      missing.add('${p.basename(fileName)} (tokens: ${tokens.join(', ')})');
    }
  }
  return missing;
}

/// Detects `P4.2` (GFM Table Pipe Hygiene): finds inline code spans containing
/// unescaped `|` pipes (ignoring `\|` and `||`) inside Markdown table rows.
List<String> findUnescapedPipesInTableInlineCode(String markdown) {
  final offending = <String>[];
  var inFence = false;
  for (final line in const LineSplitter().convert(markdown)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || !trimmed.startsWith('|') || !trimmed.endsWith('|')) {
      continue;
    }
    for (final match in _inlineCodeSpanRe.allMatches(line)) {
      final span = match.group(0)!;
      final cleaned = span.replaceAll(r'\|', '').replaceAll('||', '');
      if (cleaned.contains('|')) {
        offending.add(span);
      }
    }
  }
  return offending;
}

/// Returns true if [markdown] contains any unescaped `|` pipe inside an inline
/// code span within a Markdown table row (`P4.2`).
bool hasUnescapedPipeInsideTableInlineCode(String markdown) =>
    findUnescapedPipesInTableInlineCode(markdown).isNotEmpty;

/// Extracts `--flag` tokens (`--[a-zA-Z][a-zA-Z0-9_-]+`) from a skill corpus.
Set<String> extractCliFlags(String corpus) =>
    _extractCleanTokens(_flagTokenRe, corpus);

/// Extracts `scripts/...` and `references/...` relative paths from a skill
/// corpus.
Set<String> extractSkillRelativePaths(String corpus) =>
    _extractCleanTokens(_skillRelPathTokenRe, corpus);

Set<String> _extractCleanTokens(RegExp pattern, String text) {
  final tokens = <String>{};
  for (final match in pattern.allMatches(text)) {
    final cleaned = match.group(0)!.replaceFirst(_trailingPunctRe, '');
    if (cleaned.isNotEmpty) {
      tokens.add(cleaned);
    }
  }
  return tokens;
}

/// Extracts explicitly suppressed tokens from `<!-- allow-drop: ... -->`
/// comments in [corpus].
Set<String> extractAllowedDrops(String corpus) {
  final allowed = <String>{};
  for (final match in _allowDropCommentRe.allMatches(corpus)) {
    final body = match.group(1)!;
    for (final raw in body.split(RegExp(r'[,\s]+'))) {
      final tok = raw.trim();
      if (tok.isNotEmpty) {
        allowed.add(tok);
      }
    }
  }
  return allowed;
}

/// Verifies `P5.1` (Zero-Content-Loss Corpus Token-Set Diff) between
/// [baseCorpus] and [candidateCorpus].
CorpusDiffResult verifySkillCorpusDiff({
  required String baseCorpus,
  required String candidateCorpus,
  Set<String> allowedDrops = const {},
}) {
  final suppressed = {...allowedDrops, ...extractAllowedDrops(candidateCorpus)};
  final baseFlags = extractCliFlags(baseCorpus);
  final candFlags = extractCliFlags(candidateCorpus);
  final basePaths = extractSkillRelativePaths(baseCorpus);
  final candPaths = extractSkillRelativePaths(candidateCorpus);

  return CorpusDiffResult(
    missingFlags: baseFlags.difference(candFlags).difference(suppressed),
    missingPaths: basePaths.difference(candPaths).difference(suppressed),
  );
}

/// Runs static checks `P1.1`, `P1.2`, `P2.1`, `P3.4`, and `P4.2` on
/// [skillDir].
List<SkillStaticFinding> auditSkillDirectory(Directory skillDir) {
  final skillName = p.basename(skillDir.path);
  final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
  if (!skillFile.existsSync()) return const [];

  final skillContent = skillFile.readAsStringSync();
  final refsDir = Directory(p.join(skillDir.path, 'references'));
  final refFiles = _listMarkdownFiles(refsDir);

  final missingTopics = findMissingReferenceTopics(
    description: extractYamlDescription(skillContent),
    referenceFileNames: refFiles.map((f) => p.basename(f.path)),
  );
  return <SkillStaticFinding>[
    ...checkSkillSizeBudgets(skillDir),
    for (final missing in missingTopics)
      SkillStaticFinding(
        code: 'P3.4',
        skillName: skillName,
        file: 'SKILL.md',
        message:
            'Reference topic not represented in YAML description: $missing',
      ),
    ..._checkMarkdownContentFindings(skillName, 'SKILL.md', skillContent),
    for (final refFile in refFiles)
      ..._checkMarkdownContentFindings(
        skillName,
        'references/${p.basename(refFile.path)}',
        refFile.readAsStringSync(),
      ),
  ];
}

List<SkillStaticFinding> _checkMarkdownContentFindings(
  String skillName,
  String relPath,
  String content,
) => <SkillStaticFinding>[
  for (final row in findIncompleteQuickStartDelegations(content))
    SkillStaticFinding(
      code: 'P2.1',
      skillName: skillName,
      file: relPath,
      message: 'Incomplete Quick Start delegation row: $row',
    ),
  for (final span in findUnescapedPipesInTableInlineCode(content))
    SkillStaticFinding(
      code: 'P4.2',
      skillName: skillName,
      file: relPath,
      message: 'Unescaped pipe inside table inline code span: $span',
    ),
];

/// Concatenates `SKILL.md` and sorted `references/*.md` in [skillDir] into a
/// single corpus string.
String loadSkillCorpusFromDirectory(Directory skillDir) {
  final buffer = StringBuffer();
  final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
  if (skillFile.existsSync()) {
    buffer.writeln(skillFile.readAsStringSync());
  }
  final refsDir = Directory(p.join(skillDir.path, 'references'));
  for (final refFile in _listMarkdownFiles(refsDir)) {
    buffer.writeln(refFile.readAsStringSync());
  }
  return buffer.toString();
}

/// Loads the baseline corpus (`SKILL.md + references/*.md`) for [skillName]
/// from [gitRef] in [repoRoot], or returns `null` if the skill did not exist
/// at [gitRef].
String? loadSkillCorpusFromGit({
  required Directory repoRoot,
  required String gitRef,
  required String skillName,
}) {
  final skillPath = 'skills/$skillName/SKILL.md';
  final showSkill = Process.runSync('git', [
    'show',
    '$gitRef:$skillPath',
  ], workingDirectory: repoRoot.path);
  if (showSkill.exitCode != 0) return null;

  final buffer = StringBuffer()..writeln(showSkill.stdout as String);
  final lsRefs = Process.runSync('git', [
    'ls-tree',
    '--name-only',
    '$gitRef:skills/$skillName/references',
  ], workingDirectory: repoRoot.path);
  if (lsRefs.exitCode == 0) {
    final refNames =
        const LineSplitter()
            .convert(lsRefs.stdout as String)
            .where((name) => name.endsWith('.md'))
            .toList()
          ..sort();
    for (final refName in refNames) {
      final showRef = Process.runSync('git', [
        'show',
        '$gitRef:skills/$skillName/references/$refName',
      ], workingDirectory: repoRoot.path);
      if (showRef.exitCode == 0) {
        buffer.writeln(showRef.stdout as String);
      }
    }
  }
  return buffer.toString();
}

/// Resolves the best Git base revision (`origin/main`, `main`, or `HEAD`) for
/// `P5.1` corpus diff checks in [repoRoot].
String resolveDefaultGitBaseRef(Directory repoRoot) {
  for (final candidate in const ['origin/main', 'main', 'HEAD']) {
    final res = Process.runSync('git', [
      'rev-parse',
      '--verify',
      candidate,
    ], workingDirectory: repoRoot.path);
    if (res.exitCode == 0) return candidate;
  }
  return 'HEAD';
}

/// Runs `P5.1` Zero-Content-Loss diff checks for all skills under [skillsDir]
/// that have been modified relative to [baseRef] (or `HEAD`).
Map<String, CorpusDiffResult> verifyModifiedSkillsAgainstGit({
  required Directory skillsDir,
  String? baseRef,
}) {
  final repoRoot = skillsDir.parent;
  final effectiveRef = baseRef ?? resolveDefaultGitBaseRef(repoRoot);
  final modifiedSkills = _findModifiedSkillNames(repoRoot, effectiveRef);
  final results = <String, CorpusDiffResult>{};
  for (final skillName in modifiedSkills) {
    final skillDir = Directory(p.join(skillsDir.path, skillName));
    if (!File(p.join(skillDir.path, 'SKILL.md')).existsSync()) continue;
    final baseCorpus = loadSkillCorpusFromGit(
      repoRoot: repoRoot,
      gitRef: effectiveRef,
      skillName: skillName,
    );
    if (baseCorpus == null) continue;
    final candidateCorpus = loadSkillCorpusFromDirectory(skillDir);
    results[skillName] = verifySkillCorpusDiff(
      baseCorpus: baseCorpus,
      candidateCorpus: candidateCorpus,
    );
  }
  return results;
}

List<String> _findModifiedSkillNames(Directory repoRoot, String gitRef) {
  final diffRes = Process.runSync('git', [
    'diff',
    '--name-only',
    gitRef,
    '--',
    'skills',
  ], workingDirectory: repoRoot.path);
  if (diffRes.exitCode != 0) return const [];

  final modifiedSkills = <String>{};
  for (final line in const LineSplitter().convert(diffRes.stdout as String)) {
    final parts = p.split(line.trim());
    if (parts.length >= 2 && parts.first == 'skills') {
      modifiedSkills.add(parts[1]);
    }
  }
  return modifiedSkills.toList()..sort();
}

List<File> _listMarkdownFiles(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
}
