import 'dart:convert';
import 'dart:io';

import '../lib/deslop_report.dart';

void _printUsage() {
  print('''
Deslop Duplication Audit Report Generator

Usage:
  dart run skills/deslop-duplication-audit/bin/deslop_report.dart [options] [target_dir]

Options:
  -C, --dir=<path>        Target repository directory to scan (defaults to current directory)
  --report=<path>         Path to an existing report.json (skips running Deslop CLI)
  --top=<count>           Number of top duplicate clusters to display (default: 10)
  --min-nodes=<count>     Minimum AST subtree node count passed to Deslop (default: 30)
  --out-dir=<path>        Custom directory to store rendered Deslop reports
  --category=<cat>        Filter clusters by category: all, logic, data (default: all)
  --bucket=<bucket>       Filter clusters by bucket: all, identical, nearly_identical, structural_only (default: all)
  --no-files              Omit the per-file duplication table from output
  --no-clusters           Omit the clusters list from output
  --json                  Output filtered report as machine-readable JSON instead of Markdown
  -h, --help              Show this help message
''');
}

void main(List<String> args) async {
  String targetDir = Directory.current.path;
  String? reportJsonPath;
  var topCount = 10;
  var minNodes = 30;
  String? outDir;
  var categoryFilter = 'all';
  var bucketFilter = 'all';
  var includeFileTable = true;
  var includeClusters = true;
  var outputJson = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      _printUsage();
      exit(0);
    } else if (arg == '-C' || arg == '--dir') {
      if (i + 1 < args.length) {
        targetDir = args[++i];
      } else {
        stderr.writeln('Error: Missing value for $arg');
        exit(1);
      }
    } else if (arg.startsWith('--dir=')) {
      targetDir = arg.substring('--dir='.length);
    } else if (arg == '--report') {
      if (i + 1 < args.length) {
        reportJsonPath = args[++i];
      } else {
        stderr.writeln('Error: Missing value for --report');
        exit(1);
      }
    } else if (arg.startsWith('--report=')) {
      reportJsonPath = arg.substring('--report='.length);
    } else if (arg == '--top') {
      if (i + 1 < args.length) {
        topCount = int.tryParse(args[++i]) ?? topCount;
      }
    } else if (arg.startsWith('--top=')) {
      topCount = int.tryParse(arg.substring('--top='.length)) ?? topCount;
    } else if (arg == '--min-nodes') {
      if (i + 1 < args.length) {
        minNodes = int.tryParse(args[++i]) ?? minNodes;
      }
    } else if (arg.startsWith('--min-nodes=')) {
      minNodes = int.tryParse(arg.substring('--min-nodes='.length)) ?? minNodes;
    } else if (arg == '--out-dir') {
      if (i + 1 < args.length) {
        outDir = args[++i];
      }
    } else if (arg.startsWith('--out-dir=')) {
      outDir = arg.substring('--out-dir='.length);
    } else if (arg == '--category') {
      if (i + 1 < args.length) {
        categoryFilter = args[++i];
      }
    } else if (arg.startsWith('--category=')) {
      categoryFilter = arg.substring('--category='.length);
    } else if (arg == '--bucket') {
      if (i + 1 < args.length) {
        bucketFilter = args[++i];
      }
    } else if (arg.startsWith('--bucket=')) {
      bucketFilter = arg.substring('--bucket='.length);
    } else if (arg == '--no-files') {
      includeFileTable = false;
    } else if (arg == '--no-clusters') {
      includeClusters = false;
    } else if (arg == '--json') {
      outputJson = true;
    } else if (!arg.startsWith('-')) {
      targetDir = arg;
    } else {
      stderr.writeln('Warning: Unrecognized option "$arg"');
    }
  }

  try {
    DeslopReport report;
    String? htmlReportPath;

    if (reportJsonPath != null) {
      report = await loadReportJson(reportJsonPath);
      final htmlCandidate = reportJsonPath.replaceAll(
        RegExp(r'\.json$'),
        '.html',
      );
      if (File(htmlCandidate).existsSync()) {
        htmlReportPath = htmlCandidate;
      }
    } else {
      String? outputPrefix;
      if (outDir != null) {
        final dir = Directory(outDir);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        outputPrefix = '${dir.path}${Platform.pathSeparator}report';
      }

      final result = await runDeslopScan(
        targetDir: targetDir,
        outputPrefix: outputPrefix,
        minNodes: minNodes,
      );

      report = result.report;
      htmlReportPath = result.htmlPath;
    }

    if (outputJson) {
      final encoder = const JsonEncoder.withIndent('  ');
      print(encoder.convert(report.toJson()));
    } else {
      final markdown = formatDeslopMarkdown(
        report: report,
        targetDir: targetDir,
        htmlReportPath: htmlReportPath,
        topCount: topCount,
        categoryFilter: categoryFilter,
        bucketFilter: bucketFilter,
        includeFileTable: includeFileTable,
        includeClusters: includeClusters,
      );
      print(markdown);
    }
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] == 'true') {
      stderr.writeln(st);
    }
    exit(1);
  }
}
