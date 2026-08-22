import 'dart:io';

import 'package:path/path.dart' as p;
import '../../skills/github-pr-triage/lib/github_cli.dart';

Future<
  ({List<String> commitShas, String headSha, String branch, PrContext context})
>
setupTestGitRepo(Directory dir, {int commits = 1}) async {
  await runCommand('git', ['init'], workingDirectory: dir.path);
  await runCommand('git', [
    'config',
    'user.name',
    'Test User',
  ], workingDirectory: dir.path);
  await runCommand('git', [
    'config',
    'user.email',
    'test@example.com',
  ], workingDirectory: dir.path);

  final shas = <String>[];
  for (var i = 0; i < commits; i++) {
    File(p.join(dir.path, 'file_$i.txt')).writeAsStringSync('hello $i');
    await runCommand('git', ['add', '.'], workingDirectory: dir.path);
    await runCommand('git', [
      'commit',
      '-m',
      'commit $i',
    ], workingDirectory: dir.path);
    final sha = (await runCommand('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: dir.path)).trim();
    shas.add(sha);
  }

  final branch = (await runCommand('git', [
    'symbolic-ref',
    '--short',
    'HEAD',
  ], workingDirectory: dir.path)).trim();

  final context = PrContext(
    workingDir: dir.path,
    prNumber: '1',
    owner: 'testowner',
    repo: 'testrepo',
  );

  return (
    commitShas: shas,
    headSha: shas.isNotEmpty ? shas.last : '',
    branch: branch,
    context: context,
  );
}
