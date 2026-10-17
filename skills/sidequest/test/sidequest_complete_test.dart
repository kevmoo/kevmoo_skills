import 'dart:io';

import 'package:checks/checks.dart';
import 'package:sidequest/sidequest.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SessionStore store;
  late SidequestCliRunner runner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sidequest_pkg_test_');
    store = SessionStore(directory: tempDir.path);
    runner = SidequestCliRunner(store: store);
    await store.save(SidequestData.initial(firstQuestTitle: 'Main Quest 1'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('completing Main Quest (1 or M1) clears stale vcs.stage=dirty '
      'unless --stage is passed', () async {
    check(
      await runner.run([
        'vcs',
        '1',
        '--stage=dirty',
        '--branch=feat/clean-on-complete',
        '--files=lib/foo.dart',
      ]),
    ).equals(0);

    check(await runner.run(['complete', 'M1'])).equals(0);
    var data = (await store.load())!;
    check(data.quests.first.status).equals(QuestStatus.completed);
    check(data.quests.first.vcs?.stage).equals(VcsStage.clean);
    check(data.quests.first.vcs?.branch).equals('feat/clean-on-complete');
    check(data.quests.first.vcs!.modifiedFiles).isEmpty();

    check(await runner.run(['reopen', 'M1'])).equals(0);
    check(
      await runner.run([
        'vcs',
        'M1',
        '--stage=dirty',
        '--branch=feat/clean-on-complete',
        '--files=lib/foo.dart',
      ]),
    ).equals(0);

    check(await runner.run(['complete', 'M1', '--stage=dirty'])).equals(0);
    data = (await store.load())!;
    check(data.quests.first.status).equals(QuestStatus.completed);
    check(data.quests.first.vcs?.stage).equals(VcsStage.dirty);
    check(data.quests.first.vcs!.modifiedFiles).deepEquals(['lib/foo.dart']);
  });
}
