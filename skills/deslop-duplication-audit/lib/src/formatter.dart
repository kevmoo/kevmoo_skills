/// Formats Deslop duplication reports into token-efficient Markdown summaries.
library;

import 'dart:io';

import 'models.dart';

String _resolveAbsolutePath(String baseDir, String relativePath) {
  final file = File(relativePath);
  if (file.isAbsolute) {
    return file.absolute.path;
  }
  final combined = baseDir.endsWith(Platform.pathSeparator)
      ? '$baseDir$relativePath'
      : '$baseDir${Platform.pathSeparator}$relativePath';
  return File(combined).absolute.path;
}

/// Formats a [DeslopReport] into a high-density, token-efficient Markdown document.
String formatDeslopMarkdown({
  required DeslopReport report,
  required String targetDir,
  String? htmlReportPath,
  int topCount = 10,
  String categoryFilter = 'all',
  String bucketFilter = 'all',
  bool includeFileTable = true,
  bool includeClusters = true,
}) {
  final buffer = StringBuffer();
  final absTargetDir = Directory(targetDir).absolute.path;

  // 1. Overview Summary Header
  final totalLoc = report.metrics.analysedLoc;
  final dupLoc = report.metrics.duplicatedLoc;
  final dupPercent = report.metrics.duplicationPercent.toStringAsFixed(1);
  final totalFiles = report.filesAnalysed;
  final dupFiles = report.metrics.duplicatedFiles;
  final totalClusters = report.metrics.clustersTotal;

  buffer.writeln('### 🔬 Deslop Code Duplication Report');
  buffer.writeln();
  buffer.writeln(
    '* **Duplication Score**: **$dupPercent%** ($dupLoc / $totalLoc LOC across $dupFiles / $totalFiles files)',
  );

  // Group cluster counts by bucket
  final bucketCounts = <String, int>{};
  for (final cluster in report.clusters) {
    bucketCounts[cluster.bucket] = (bucketCounts[cluster.bucket] ?? 0) + 1;
  }

  final bucketBreakdown = <String>[];
  if (bucketCounts.containsKey('identical')) {
    bucketBreakdown.add('${bucketCounts['identical']} identical [Type-1/2]');
  }
  if (bucketCounts.containsKey('nearly_identical')) {
    bucketBreakdown.add(
      '${bucketCounts['nearly_identical']} near-identical [Type-3]',
    );
  }
  if (bucketCounts.containsKey('structural_only')) {
    bucketBreakdown.add(
      '${bucketCounts['structural_only']} structural-only shape matches',
    );
  }
  if (bucketCounts.containsKey('loosely_similar')) {
    bucketBreakdown.add('${bucketCounts['loosely_similar']} loosely similar');
  }
  if (bucketCounts.containsKey('same_behavior')) {
    bucketBreakdown.add('${bucketCounts['same_behavior']} AI semantic matches');
  }

  final breakdownText = bucketBreakdown.isNotEmpty
      ? ' (${bucketBreakdown.join(', ')})'
      : '';
  buffer.writeln('* **Total Clusters**: $totalClusters$breakdownText');

  if (htmlReportPath != null && File(htmlReportPath).existsSync()) {
    final htmlUri = Uri.file(File(htmlReportPath).absolute.path).toString();
    buffer.writeln('* **Interactive HTML Report**: [report.html]($htmlUri)');
  }

  buffer.writeln();

  // 2. Top Duplication Clusters
  if (includeClusters) {
    var filteredClusters = List<DeslopCluster>.of(report.clusters);

    if (categoryFilter != 'all') {
      filteredClusters = filteredClusters
          .where((c) => c.category == categoryFilter)
          .toList();
    }

    if (bucketFilter != 'all') {
      filteredClusters = filteredClusters
          .where((c) => c.bucket == bucketFilter)
          .toList();
    }

    // Sort by weight descending
    filteredClusters.sort((a, b) => b.weight.compareTo(a.weight));

    final displayClusters = filteredClusters.take(topCount).toList();

    if (displayClusters.isEmpty) {
      buffer.writeln('_No duplicate clusters match the specified filters._');
      buffer.writeln();
    } else {
      buffer.writeln(
        '#### Top Duplication Clusters (Ranked by Weight & Potential Savings)',
      );
      buffer.writeln();

      for (var i = 0; i < displayClusters.length; i++) {
        final c = displayClusters[i];
        final rank = i + 1;
        final weightStr = c.weight.toStringAsFixed(1);
        final categoryTag = c.category == 'data' ? ' [Data Table]' : '';

        buffer.writeln(
          '**#$rank ${c.bucketLabel}$categoryTag** — ${c.size} copies · ${c.canonicalNodeCount} AST nodes · weight $weightStr',
        );

        if (c.interpretation.isNotEmpty) {
          buffer.writeln('> ${c.interpretation}');
        }

        for (final occ in c.occurrences) {
          final relPath = occ.path;
          final absFilePath = _resolveAbsolutePath(absTargetDir, relPath);
          final lineSuffix = occ.lineSpan;
          final linkText = '$relPath:$lineSuffix';
          final targetUrl = '${Uri.file(absFilePath)}#$lineSuffix';
          buffer.writeln('* [$linkText]($targetUrl)');
        }
        buffer.writeln();
      }

      if (filteredClusters.length > topCount) {
        final remaining = filteredClusters.length - topCount;
        buffer.writeln(
          '_... $remaining more clusters hidden (use `--top=${filteredClusters.length}` to display all)_',
        );
        buffer.writeln();
      }
    }
  }

  // 3. Per-File Duplication Breakdown Table
  if (includeFileTable) {
    final duplicatedFiles = report.metrics.perFile
        .where((f) => f.duplicatedLoc > 0)
        .toList();

    // Sort by duplicated LOC descending
    duplicatedFiles.sort((a, b) => b.duplicatedLoc.compareTo(a.duplicatedLoc));

    if (duplicatedFiles.isNotEmpty) {
      buffer.writeln('#### Duplicated Source Files');
      buffer.writeln();
      buffer.writeln('| File | Duplicated LOC | Total LOC | Duplication % |');
      buffer.writeln('| :--- | :---: | :---: | :---: |');

      for (final file in duplicatedFiles) {
        final relPath = file.path;
        final absFilePath = _resolveAbsolutePath(absTargetDir, relPath);
        final linkText = relPath;
        final targetUrl = Uri.file(absFilePath).toString();
        final filePercent = file.duplicationPercent.toStringAsFixed(1);

        buffer.writeln(
          '| [$linkText]($targetUrl) | ${file.duplicatedLoc} | ${file.analysedLoc} | $filePercent% |',
        );
      }
      buffer.writeln();
    }
  }

  return buffer.toString().trimRight();
}
