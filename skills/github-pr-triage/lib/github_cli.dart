import 'dart:convert';
import 'dart:io';

/// Encapsulates context for a target Pull Request and workspace directory.
class PrContext {
  final String workingDir;
  final String prNumber;
  final String owner;
  final String repo;

  PrContext({
    required this.workingDir,
    required this.prNumber,
    required this.owner,
    required this.repo,
  });
}

/// Runs an external process command and returns its standard output.
///
/// Throws a [ProcessException] if the command exits with a non-zero exit code.
Future<String> runCommand(
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

/// Parses CLI arguments and resolves the [PrContext] for git operations.
Future<PrContext> resolvePrContext(
  List<String> args, {
  required Never Function(String message) onFail,
}) async {
  String? prInput;
  String? targetDir;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--pr' || arg == '-p') {
      if (i + 1 < args.length) {
        prInput = args[++i];
      } else {
        onFail('Missing value for option "$arg"');
      }
    } else if (arg == '--dir' || arg == '-C') {
      if (i + 1 < args.length) {
        targetDir = args[++i];
      } else {
        onFail('Missing value for option "$arg"');
      }
    } else if (arg.startsWith('-')) {
      onFail('Unknown option "$arg"');
    } else {
      prInput = arg;
    }
  }

  final workingDir = targetDir != null
      ? Directory(targetDir).absolute.path
      : Directory.current.absolute.path;
  if (!await Directory(workingDir).exists()) {
    onFail('Target directory "$workingDir" does not exist.');
  }

  String? prNumber;
  String? owner;
  String? repo;

  if (prInput != null) {
    final prUrlMatch = RegExp(
      r'github\.com/([^/]+)/([^/]+)/pull/(\d+)',
    ).firstMatch(prInput);
    if (prUrlMatch != null) {
      owner = prUrlMatch.group(1);
      repo = prUrlMatch.group(2);
      prNumber = prUrlMatch.group(3);
    } else if (RegExp(r'^\d+$').hasMatch(prInput)) {
      prNumber = prInput;
    } else {
      onFail(
        'Invalid PR argument. Please provide a PR number or a GitHub PR URL.',
      );
    }
  }

  // Auto-detect PR from current branch if not provided.
  if (prNumber == null) {
    String branch;
    try {
      branch = (await runCommand('git', [
        'symbolic-ref',
        '--short',
        'HEAD',
      ], workingDirectory: workingDir)).trim();
    } catch (_) {
      branch = '';
    }
    if (branch.isEmpty || branch == 'main' || branch == 'master') {
      onFail(
        'Active branch is ${branch.isEmpty ? 'detached HEAD' : '"$branch"'}. '
        'Please specify a target PR number or URL.',
      );
    }

    final listOutput = await runCommand('gh', [
      'pr',
      'list',
      '--head',
      branch,
      '--json',
      'number,url',
    ], workingDirectory: workingDir);
    final decodedList = jsonDecode(listOutput);
    final listJson = decodedList is List<dynamic> ? decodedList : const [];
    if (listJson.isEmpty) {
      onFail(
        'Error: Ambiguous context. No open PR found for branch "$branch". '
        'Do not guess. Please explicitly ask the user for a PR number or URL.',
      );
    }
    if (listJson.length > 1) {
      onFail(
        'Error: Ambiguous context. Multiple open PRs found for branch "$branch". '
        'Do not guess. Please explicitly ask the user which PR number or URL to target.',
      );
    }
    final firstPr = listJson[0];
    if (firstPr is! Map || firstPr['number'] == null) {
      onFail('Error: Unexpected PR data format from "gh pr list".');
    }
    prNumber = firstPr['number'].toString();
  }

  String? localOwner;
  String? localRepo;
  try {
    final repoOutput = await runCommand('gh', [
      'repo',
      'view',
      '--json',
      'owner,name',
    ], workingDirectory: workingDir);
    final repoJson = jsonDecode(repoOutput) as Map<String, dynamic>;
    localOwner = (repoJson['owner'] as Map<String, dynamic>)['login'] as String;
    localRepo = repoJson['name'] as String;
  } catch (e) {
    if (owner == null || repo == null) {
      onFail('Failed to resolve repository owner and name: $e');
    }
  }

  final resolvedOwner = owner ?? localOwner;
  final resolvedRepo = repo ?? localRepo;

  if (resolvedOwner == null || resolvedRepo == null) {
    onFail('Failed to resolve repository owner and name.');
  }

  if (localOwner != null &&
      localRepo != null &&
      owner != null &&
      repo != null) {
    if (localOwner.toLowerCase() != owner.toLowerCase() ||
        localRepo.toLowerCase() != repo.toLowerCase()) {
      onFail(
        'The target directory "$workingDir" is for repository "$localOwner/$localRepo", '
        'but the specified PR is for repository "$owner/$repo".',
      );
    }
  }

  return PrContext(
    workingDir: workingDir,
    prNumber: prNumber,
    owner: resolvedOwner,
    repo: resolvedRepo,
  );
}
