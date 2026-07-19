import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:sidequest/sidequest.dart';

void main() {
  group('Sidequest Data Model & Serialization', () {
    test('roundtrips complete SidequestData JSON cleanly', () {
      final data = SidequestData(
        version: 1,
        watermark: const Watermark(
          stepIndex: 42,
          timestamp: '2026-07-17T18:19:53Z',
        ),
        lastCompletionOrder: 3,
        globalSideQuests: [
          SideQuest(
            id: 'G1',
            title: 'Fix linter in analysis_options.yaml',
            status: SideQuestStatus.completed,
            completionOrder: 1,
            vcs: const VcsState(stage: VcsStage.clean),
          ),
        ],
        quests: [
          MainQuest(
            id: '1',
            title: 'Migrate UserService to v2 API',
            status: QuestStatus.completed,
            vcs: const VcsState(
              stage: VcsStage.clean,
              details: 'PR #142 (Merged upstream)',
            ),
            subQuests: [
              SubQuest(
                id: '1.1',
                title: 'Identify callers across repository',
                status: TaskStatus.completed,
                completionOrder: 2,
              ),
              SubQuest(
                id: '1.2',
                title: 'Update client stub bindings',
                status: TaskStatus.completed,
                completionOrder: 3,
                items: [
                  TaskItem(
                    id: '1.2.1',
                    type: TaskType.blocker,
                    title: 'Fix build missing proto/public dep',
                    status: TaskStatus.completed,
                    completionOrder: 3,
                  ),
                ],
              ),
            ],
          ),
          MainQuest(
            id: '2',
            title: 'Investigate Thread Leak',
            status: QuestStatus.active,
            vcs: const VcsState(
              stage: VcsStage.dirty,
              branch: 'fix-leak',
              modifiedFiles: ['lib/worker.dart'],
            ),
            subQuests: [
              SubQuest(
                id: '2.1',
                title: 'Check config and run reproduction test',
                status: TaskStatus.inProgress,
                items: [
                  TaskItem(
                    id: '2.1.1',
                    type: TaskType.step,
                    title: 'Run worker profiling script',
                    status: TaskStatus.pending,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final jsonMap = data.toJson();
      final restored = SidequestData.fromJson(jsonMap);

      check(restored.version).equals(1);
      check(restored.watermark?.stepIndex).equals(42);
      check(restored.lastCompletionOrder).equals(3);
      check(restored.quests.length).equals(2);
      check(restored.globalSideQuests.length).equals(1);
      check(restored.quests[0].subQuests.length).equals(2);
      check(restored.quests[0].subQuests[1].items.length).equals(1);
      check(restored.quests[1].vcs?.stage).equals(VcsStage.dirty);
      check(restored.quests[1].vcs!.modifiedFiles).contains('lib/worker.dart');
    });
  });

  group('Markdown Emitter & Formatting (#57 & #58)', () {
    test('renders hierarchical numbering and completion tags with star', () {
      final data = SidequestData(
        version: 1,
        lastCompletionOrder: 2,
        globalSideQuests: [
          SideQuest(
            id: 'G1',
            title: 'Update global dotfiles',
            status: SideQuestStatus.active,
          ),
        ],
        quests: [
          MainQuest(
            id: '1',
            title: 'Migrate UserService API',
            status: QuestStatus.completed,
            vcs: const VcsState(
              stage: VcsStage.clean,
              details: 'PR #142 Merged',
            ),
            subQuests: [
              SubQuest(
                id: '1.1',
                title: 'Identify callers',
                status: TaskStatus.completed,
                completionOrder: 1,
              ),
            ],
            sideQuests: [
              SideQuest(
                id: 'S1',
                title: 'Investigate legacy cache',
                status: SideQuestStatus.parked,
                note: 'Filed Issue #99',
              ),
            ],
          ),
          MainQuest(
            id: '2',
            title: 'Investigate Thread Leak',
            status: QuestStatus.active,
            vcs: const VcsState(
              stage: VcsStage.dirty,
              branch: 'fix-leak',
              modifiedFiles: ['lib/worker.dart'],
            ),
            subQuests: [
              SubQuest(
                id: '2.1',
                title: 'Check config',
                status: TaskStatus.inProgress,
                items: [
                  TaskItem(
                    id: '2.1.1',
                    type: TaskType.blocker,
                    title: 'Fix Docker timeout',
                    status: TaskStatus.completed,
                    completionOrder: 2,
                  ),
                  TaskItem(
                    id: '2.1.2',
                    type: TaskType.step,
                    title: 'Run profiling',
                    status: TaskStatus.pending,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final markdown = MarkdownEmitter.emit(data);

      // Hierarchical Sub-Quest Numbering (#57)
      check(markdown).contains('Sub-Quest 1.1:');
      check(markdown).contains('Sub-Quest 2.1:');

      // SideQuest IDs rendered
      check(markdown).contains('[Active Side-Quest G1]');
      check(markdown).contains('[Parked Side-Quest S1 / Tracked for Later]');

      // Completion Order Numbers (#58)
      check(markdown).contains('[#1]');

      // Recent Completion Star (#58)
      check(markdown).contains('[#2 ⭐]');

      // Vanquished Blocker styling
      check(
        markdown,
      ).contains('💀 ~~*Blocker 2.1.1:* Fix Docker timeout~~ -> *Resolved*');

      // Pending Step styling
      check(markdown).contains('👣 *Step 2.1.2:* Run profiling');

      // Caution header rendering for uncommitted & unpushed files
      check(markdown).contains('> [!CAUTION]');
      check(markdown).contains('> **Uncommitted & Unpushed Changes:**');
      check(
        markdown,
      ).contains('> * **Main Quest 2 (`fix-leak`):** `lib/worker.dart`');

      // VCS state rendering
      check(markdown).contains(
        '> **VCS State:** `📝 Dirty` | Branch: `fix-leak` | Modified: `lib/worker.dart`',
      );
    });

    test('renders CAUTION header for local commit', () {
      final data = SidequestData(
        version: 1,
        quests: [
          MainQuest(
            id: '1',
            title: 'Local Commit Quest',
            status: QuestStatus.active,
            vcs: const VcsState(
              stage: VcsStage.localCommit,
              branch: 'feat/test',
            ),
          ),
        ],
      );

      final markdown = MarkdownEmitter.emit(data);
      check(markdown).contains('> [!CAUTION]');
      check(markdown).contains('> **Uncommitted & Unpushed Changes:**');
      check(
        markdown,
      ).contains('> * **Main Quest 1 (`feat/test`):** Unpushed local commit');
    });

    test('omits CAUTION header when workspace is clean', () {
      final data = SidequestData(
        version: 1,
        quests: [
          MainQuest(
            id: '1',
            title: 'Clean Quest',
            status: QuestStatus.active,
            vcs: const VcsState(stage: VcsStage.clean),
          ),
        ],
      );

      final markdown = MarkdownEmitter.emit(data);
      check(markdown).not((c) => c.contains('> [!CAUTION]'));
    });
  });

  group('SessionStore & Atomic Persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sidequest_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'creates and atomically saves sidequest.json and sidequest.md',
      () async {
        final store = SessionStore(directory: tempDir.path);
        final initialData = SidequestData.initial(
          firstQuestTitle: 'Initial Task',
        );

        await store.save(initialData);

        final jsonFile = File(p.join(tempDir.path, 'sidequest.json'));
        final mdFile = File(p.join(tempDir.path, 'sidequest.md'));

        check(await jsonFile.exists()).isTrue();
        check(await mdFile.exists()).isTrue();

        final loaded = await store.load();
        check(loaded).isNotNull();
        check(loaded!.quests.first.title).equals('Initial Task');
      },
    );
  });

  group('CLI Mutations & Workflow Operations', () {
    late Directory tempDir;
    late SessionStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sidequest_cli_test_');
      store = SessionStore(directory: tempDir.path);
      await store.save(SidequestData.initial(firstQuestTitle: 'Main Quest 1'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'adds subquests, steps, blockers, and handles completions (#57 & #58)',
      () async {
        final runner = SidequestCliRunner(store: store);

        // Add subquest with unquoted multi-word title
        await runner.run(['subquest', 'add', '1', 'SubQuest', 'Title', 'Here']);
        var data = (await store.load())!;
        check(data.quests[0].subQuests.length).equals(1);
        check(data.quests[0].subQuests[0].id).equals('1.1');
        check(data.quests[0].subQuests[0].title).equals('SubQuest Title Here');

        // Add blocker & step
        await runner.run(['blocker', 'add', '1.1', 'Broken Build']);
        await runner.run(['step', 'add', '1.1', 'Run Tests']);
        data = (await store.load())!;
        check(data.quests[0].subQuests[0].items.length).equals(2);
        check(data.quests[0].subQuests[0].items[0].id).equals('1.1.1');
        check(data.quests[0].subQuests[0].items[1].id).equals('1.1.2');

        // Complete blocker (order #1 ⭐)
        await runner.run(['complete', '1.1.1']);
        data = (await store.load())!;
        check(data.lastCompletionOrder).equals(1);
        check(
          data.quests[0].subQuests[0].items[0].status,
        ).equals(TaskStatus.completed);
        check(data.quests[0].subQuests[0].items[0].completionOrder).equals(1);

        // Complete step (order #2 ⭐, removes star from #1)
        await runner.run(['complete', '1.1.2']);
        data = (await store.load())!;
        check(data.lastCompletionOrder).equals(2);
        check(data.quests[0].subQuests[0].items[1].completionOrder).equals(2);

        final md = await File(
          p.join(tempDir.path, 'sidequest.md'),
        ).readAsString();
        check(md).contains('[#1]');
        check(md).contains('[#2 ⭐]');
      },
    );

    test('completes, reopens, and removes MainQuest and SideQuests', () async {
      final runner = SidequestCliRunner(store: store);

      // Add sidequests (Global & Quest-scoped)
      await runner.run(['sidequest', 'add', 'Global Task', '--global']);
      await runner.run(['sidequest', 'add', 'Quest Task', '--quest=1']);

      var data = (await store.load())!;
      check(data.globalSideQuests.length).equals(1);
      check(data.quests[0].sideQuests.length).equals(1);

      // Complete Global SideQuest G1
      await runner.run(['complete', 'G1']);
      data = (await store.load())!;
      check(data.globalSideQuests[0].status).equals(SideQuestStatus.completed);
      check(data.globalSideQuests[0].completionOrder).equals(1);
      check(data.lastCompletionOrder).equals(1);

      // Complete MainQuest 1
      await runner.run(['complete', '1']);
      data = (await store.load())!;
      check(data.quests[0].status).equals(QuestStatus.completed);

      // Reopen Global SideQuest G1
      await runner.run(['reopen', 'G1']);
      data = (await store.load())!;
      check(data.globalSideQuests[0].status).equals(SideQuestStatus.active);
      check(data.globalSideQuests[0].completionOrder).isNull();
      check(data.lastCompletionOrder).equals(0);

      // Add and remove MainQuest 2
      await runner.run(['quest', 'add', 'Temporary Quest']);
      data = (await store.load())!;
      check(data.quests.length).equals(2);

      await runner.run(['remove', '2']);
      data = (await store.load())!;
      check(data.quests.length).equals(1);
    });

    test('executes batch mutations atomically', () async {
      final runner = SidequestCliRunner(store: store);

      final batchJson = jsonEncode({
        'addSubQuest': {'quest': '1', 'title': 'Batch SubQuest'},
        'vcs': {
          'quest': '1',
          'stage': 'dirty',
          'branch': 'feat/test',
          'files': ['lib/a.dart'],
        },
      });

      await runner.run(['batch', batchJson]);
      final data = (await store.load())!;
      check(data.quests[0].subQuests.length).equals(1);
      check(data.quests[0].vcs?.stage).equals(VcsStage.dirty);
      check(data.quests[0].vcs?.branch).equals('feat/test');
    });
  });
}
