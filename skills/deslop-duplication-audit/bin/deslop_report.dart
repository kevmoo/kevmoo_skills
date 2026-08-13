import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:deslop_duplication_audit/deslop_report.dart';

ArgParser _buildParser() {
  return ArgParser()
    ..addOption('dir', abbr: 'C', help: 'Target repository directory to scan.')
    ..addOption(
      'report',
      help: 'Path to an existing report.json (skips running Deslop CLI).',
    )
    ..addOption(
      'top',
      defaultsTo: '10',
      help: 'Number of top duplicate clusters to display.',
    )
    ..addOption(
      'min-nodes',
      defaultsTo: '30',
      help: 'Minimum AST subtree node count passed to Deslop.',
    )
    ..addOption(
      'out-dir',
      help: 'Custom directory to store rendered Deslop reports.',
    )
    ..addOption(
      'category',
      defaultsTo: 'all',
      allowed: ['all', 'logic', 'data'],
      help: 'Filter clusters by category.',
    )
    ..addOption(
      'bucket',
      defaultsTo: 'all',
      allowed: [
        'all',
        'identical',
        'nearly_identical',
        'structural_only',
        'loosely_similar',
        'same_behavior',
      ],
      help: 'Filter clusters by bucket.',
    )
    ..addFlag(
      'files',
      defaultsTo: true,
      negatable: true,
      help: 'Include the per-file duplication table in output.',
    )
    ..addFlag(
      'clusters',
      defaultsTo: true,
      negatable: true,
      help: 'Include the clusters list in output.',
    )
    ..addFlag(
      'json',
      defaultsTo: false,
      negatable: false,
      help:
          'Output filtered report as machine-readable JSON instead of Markdown.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );
}

void main(List<String> args) async {
  final parser = _buildParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    print('Deslop Duplication Audit Report Generator\n');
    print(
      'Usage: dart run skills/deslop-duplication-audit/bin/deslop_report.dart [options] [target_dir]\n',
    );
    print(parser.usage);
    exit(0);
  }

  final targetDir =
      results.option('dir') ??
      (results.rest.isNotEmpty ? results.rest.first : Directory.current.path);

  final reportJsonPath = results.option('report');
  final topCount = int.tryParse(results.option('top') ?? '10') ?? 10;
  final minNodes = int.tryParse(results.option('min-nodes') ?? '30') ?? 30;
  final outDir = results.option('out-dir');
  final categoryFilter = results.option('category') ?? 'all';
  final bucketFilter = results.option('bucket') ?? 'all';
  final includeFileTable = results.flag('files');
  final includeClusters = results.flag('clusters');
  final outputJson = results.flag('json');

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
