import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:deslop_duplication_audit/deslop_report.dart';
import 'package:test/test.dart';

const _sampleDeslopJson = '''
{
  "tool_version": "0.31.0",
  "min_nodes": 30,
  "files_analysed": 18,
  "clusters_hidden": 5,
  "metrics": {
    "analysed_loc": 1000,
    "duplicated_loc": 150,
    "duplication_percent": 15.0,
    "clusters_total": 2,
    "duplicated_files": 2,
    "per_file": [
      {
        "path": "lib/foo.dart",
        "analysed_loc": 500,
        "duplicated_loc": 100,
        "duplication_percent": 20.0
      },
      {
        "path": "lib/bar.dart",
        "analysed_loc": 500,
        "duplicated_loc": 50,
        "duplication_percent": 10.0
      }
    ]
  },
  "action_hints": [
    {
      "pattern": "bucket=identical",
      "recommendation": "Safe to extract"
    }
  ],
  "clusters": [
    {
      "id": "c1",
      "weight": 120.5,
      "size": 2,
      "canonical_node_count": 45,
      "signals": {
        "structural": 1.0,
        "token_jaccard": 0.95
      },
      "bucket": "nearly_identical",
      "category": "logic",
      "occurrences": [
        {
          "path": "lib/foo.dart",
          "start_byte": 100,
          "end_byte": 200,
          "start_line": 10,
          "end_line": 20,
          "hidden": false
        },
        {
          "path": "lib/bar.dart",
          "start_byte": 150,
          "end_byte": 250,
          "start_line": 15,
          "end_line": 25,
          "hidden": false
        }
      ],
      "occurrences_total": 2,
      "summary": "2 copies of a 45-node subtree",
      "interpretation": "Review differences before merging"
    },
    {
      "id": "c2",
      "weight": 80.0,
      "size": 2,
      "canonical_node_count": 30,
      "signals": {
        "structural": 1.0
      },
      "bucket": "identical",
      "category": "data",
      "occurrences": [
        {
          "path": "lib/foo.dart",
          "start_byte": 300,
          "end_byte": 350,
          "start_line": 30,
          "end_line": 35,
          "hidden": false
        },
        {
          "path": "lib/bar.dart",
          "start_byte": 350,
          "end_byte": 400,
          "start_line": 40,
          "end_line": 45,
          "hidden": false
        }
      ],
      "occurrences_total": 2,
      "summary": "2 copies of data table",
      "interpretation": "Repeated data rows"
    }
  ]
}
''';

const _sampleGitDiff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1234567..89abcdef 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -8,5 +8,15 @@ void existing() {}
+void newHelper() {
+  print('hello');
+}
''';

const _sampleJjDiff = '''
Modified regular file lib/bar.dart:
--- a/lib/bar.dart
+++ b/lib/bar.dart
@@ -12,4 +12,8 @@
+void another() {
+  print('world');
+}
''';

void main() {
  group('Diff Parser', () {
    test('parses git unified diff and extracts line spans', () {
      final spans = parseUnifiedDiff(_sampleGitDiff);
      check(spans.containsKey('lib/foo.dart')).isTrue();
      final fooSpans = spans['lib/foo.dart']!;
      check(fooSpans.length).equals(1);
      check(fooSpans.first).equals(const LineSpan(8, 22));
    });

    test('parses jujutsu diff format and extracts line spans', () {
      final spans = parseUnifiedDiff(_sampleJjDiff);
      check(spans.containsKey('lib/bar.dart')).isTrue();
      final barSpans = spans['lib/bar.dart']!;
      check(barSpans.length).equals(1);
      check(barSpans.first).equals(const LineSpan(12, 19));
    });

    test('LineSpan overlap and containment tests', () {
      const span = LineSpan(10, 20);
      check(span.contains(10)).isTrue();
      check(span.contains(15)).isTrue();
      check(span.contains(20)).isTrue();
      check(span.contains(9)).isFalse();
      check(span.contains(21)).isFalse();

      check(span.overlaps(5, 9)).isFalse();
      check(span.overlaps(5, 10)).isTrue();
      check(span.overlaps(15, 25)).isTrue();
      check(span.overlaps(20, 30)).isTrue();
      check(span.overlaps(21, 30)).isFalse();
    });

    test(
      'pathsMatch handles prefixes, relative paths, and rejects partial directory matches',
      () {
        check(pathsMatch('lib/foo.dart', 'lib/foo.dart')).isTrue();
        check(pathsMatch('lib/foo.dart', 'a/lib/foo.dart')).isTrue();
        check(pathsMatch('lib/foo.dart', 'b/lib/foo.dart')).isTrue();
        check(pathsMatch('foo.dart', 'lib/foo.dart')).isTrue();
        check(pathsMatch('lib/foo.dart', 'lib/bar.dart')).isFalse();
        // Partial directory substring rejection
        check(
          pathsMatch('feature_login/view.dart', 'login/view.dart'),
        ).isFalse();
        check(
          pathsMatch('login/view.dart', 'feature_login/view.dart'),
        ).isFalse();
      },
    );

    test(
      'normalizeFilePath handles git prefixes, leading slashes, and backslashes',
      () {
        check(normalizeFilePath('a/lib/foo.dart')).equals('lib/foo.dart');
        check(normalizeFilePath('b/lib/foo.dart')).equals('lib/foo.dart');
        check(normalizeFilePath('/lib/foo.dart')).equals('lib/foo.dart');
        check(normalizeFilePath(r'lib\foo.dart')).equals('lib/foo.dart');
      },
    );
  });

  group('DeslopReport model parsing', () {
    test('parses sample report JSON correctly', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      check(report.toolVersion).equals('0.31.0');
      check(report.minNodes).equals(30);
      check(report.filesAnalysed).equals(18);
      check(report.clustersHidden).equals(5);
      check(report.metrics.analysedLoc).equals(1000);
      check(report.metrics.duplicatedLoc).equals(150);
      check(report.metrics.duplicationPercent).equals(15.0);
      check(report.metrics.perFile).has((p) => p.length, 'length').equals(2);
      check(report.clusters).has((c) => c.length, 'length').equals(2);

      final c1 = report.clusters.first;
      check(c1.id).equals('c1');
      check(c1.bucket).equals('nearly_identical');
      check(c1.bucketLabel).equals('Nearly Identical [Type-3]');
      check(c1.occurrences).has((o) => o.length, 'length').equals(2);
      check(c1.occurrences.first.lineSpan).equals('L10-20');
    });

    test('evaluates cluster diff intersection correctly', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);
      final c1 =
          report.clusters.first; // lib/foo.dart:10-20, lib/bar.dart:15-25
      final c2 = report.clusters.last; // lib/foo.dart:30-35, lib/bar.dart:40-45

      final diffRanges = {
        'lib/foo.dart': [const LineSpan(12, 15)],
      };

      check(c1.intersectsDiff(diffRanges)).isTrue();
      check(c2.intersectsDiff(diffRanges)).isFalse();
    });

    test(
      'evaluates cluster and occurrence diff intersection as false on empty diff',
      () {
        final dynamic decoded = jsonDecode(_sampleDeslopJson);
        final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);
        final c1 = report.clusters.first;
        final occ = c1.occurrences.first;

        check(c1.intersectsDiff({})).isFalse();
        check(c1.occurrencesIntersectingDiff({})).equals(0);
        check(c1.isNewlyIntroduced({})).isFalse();
        check(occ.intersectsDiff({})).isFalse();
      },
    );
  });

  group('formatDeslopMarkdown', () {
    test('renders markdown with proper clickable file links', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      final md = formatDeslopMarkdown(
        report: report,
        targetDir: '/fake/repo',
        htmlReportPath: '/fake/repo/report.html',
        topCount: 5,
      );

      check(md).contains('### 🔬 Deslop Code Duplication Report');
      check(md).contains('**15.0%** (150 / 1000 LOC across 2 / 18 files)');
      check(md).contains(
        '[lib/foo.dart:L10-20](file:///fake/repo/lib/foo.dart#L10-20)',
      );
      check(md).contains(
        '[lib/bar.dart:L15-25](file:///fake/repo/lib/bar.dart#L15-25)',
      );
      check(md).contains(
        '| [lib/foo.dart](file:///fake/repo/lib/foo.dart) | 100 | 500 | 20.0% |',
      );
    });

    test('supports filtering by category', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      final md = formatDeslopMarkdown(
        report: report,
        targetDir: '/fake/repo',
        categoryFilter: 'logic',
      );

      check(md).contains('Nearly Identical [Type-3]');
      check(md).not((s) => s.contains('[Data Table]'));
    });

    test('supports diff-aware delta filtering', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      final diffRanges = {
        'lib/foo.dart': [const LineSpan(12, 15)],
      };

      final md = formatDeslopMarkdown(
        report: report,
        targetDir: '/fake/repo',
        changedRanges: diffRanges,
        onlyChangedCode: true,
      );

      check(md).contains('### 🔬 Deslop Code Duplication Report (CL Delta)');
      check(md).contains('1 cluster(s)** intersect modified code');
      check(md).contains('`[CL Modified]`');
      check(md).contains('`[Existing Code]`');
    });

    test('returns clean status when zero clusters intersect diff', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      final diffRanges = {
        'lib/other.dart': [const LineSpan(1, 50)],
      };

      final md = formatDeslopMarkdown(
        report: report,
        targetDir: '/fake/repo',
        changedRanges: diffRanges,
        onlyChangedCode: true,
      );

      check(md).contains('✅ **Clean** — 0 duplicate code clusters detected');
    });

    test('handles empty diff (0 modified lines) gracefully in delta mode', () {
      final dynamic decoded = jsonDecode(_sampleDeslopJson);
      final report = DeslopReport.fromJson(decoded as Map<String, dynamic>);

      final md = formatDeslopMarkdown(
        report: report,
        targetDir: '/fake/repo',
        changedRanges: {},
        onlyChangedCode: true,
      );

      check(md).contains('### 🔬 Deslop Code Duplication Report (CL Delta)');
      check(md).contains('✅ **Clean** — 0 duplicate code clusters detected');
    });
  });

  group('runner and CLI', () {
    test('findDeslopExecutable returns a non-empty string if installed', () {
      final exe = findDeslopExecutable();
      if (exe != null) {
        check(File(exe).existsSync()).isTrue();
      }
    });

    String resolveRepoRoot() {
      final current = Directory.current.path;
      return current.endsWith('tool') ? Directory.current.parent.path : current;
    }

    test('CLI prints help on -h', () async {
      final repoRoot = resolveRepoRoot();
      final scriptPath =
          '$repoRoot/skills/deslop-duplication-audit/bin/deslop_report.dart';
      final process = await Process.run(Platform.resolvedExecutable, [
        'run',
        scriptPath,
        '-h',
      ]);
      check(process.exitCode).equals(0);
      check(
        process.stdout as String,
      ).contains('Deslop Duplication Audit Report Generator');
    });

    test('CLI processes --report json file and outputs markdown', () async {
      final tempDir = Directory.systemTemp.createTempSync('deslop_test_');
      final tempJson = File('${tempDir.path}/test_report.json');
      await tempJson.writeAsString(_sampleDeslopJson);

      final repoRoot = resolveRepoRoot();
      final scriptPath =
          '$repoRoot/skills/deslop-duplication-audit/bin/deslop_report.dart';

      final process = await Process.run(Platform.resolvedExecutable, [
        'run',
        scriptPath,
        '--report=${tempJson.path}',
        '--dir=/sample/target',
      ]);

      check(process.exitCode).equals(0);
      final stdoutStr = process.stdout as String;
      check(stdoutStr).contains('### 🔬 Deslop Code Duplication Report');
      check(stdoutStr).contains('lib/foo.dart:L10-20');

      tempDir.deleteSync(recursive: true);
    });

    test('CLI supports --diff string and --only-changed', () async {
      final tempDir = Directory.systemTemp.createTempSync('deslop_test_');
      final tempJson = File('${tempDir.path}/test_report.json');
      await tempJson.writeAsString(_sampleDeslopJson);

      final repoRoot = resolveRepoRoot();
      final scriptPath =
          '$repoRoot/skills/deslop-duplication-audit/bin/deslop_report.dart';

      final process = await Process.run(Platform.resolvedExecutable, [
        'run',
        scriptPath,
        '--report=${tempJson.path}',
        '--dir=/sample/target',
        '--diff',
        _sampleGitDiff,
        '--only-changed',
      ]);

      check(process.exitCode).equals(0);
      final stdoutStr = process.stdout as String;
      check(
        stdoutStr,
      ).contains('### 🔬 Deslop Code Duplication Report (CL Delta)');
      check(stdoutStr).contains('`[CL Modified]`');

      tempDir.deleteSync(recursive: true);
    });
  });
}
