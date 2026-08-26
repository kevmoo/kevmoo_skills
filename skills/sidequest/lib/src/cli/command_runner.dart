import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';

import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';
import '../storage/session_store.dart';

enum _ItemCompleteResult {
  completedWithOrder,
  completedNoOrder,
  alreadyCompleted,
  notFound,
}

/// Standard [CommandRunner] for the `sidequest` CLI tool.
class SidequestCliRunner extends CommandRunner<int> {
  SessionStore? _store;

  SidequestCliRunner({SessionStore? store})
    : _store = store,
      super('sidequest', 'Deterministic session map manager') {
    argParser.addOption(
      'dir',
      help: 'Path to session artifact directory containing sidequest.json',
    );

    addCommand(StatusCommand(this));
    addCommand(InitCommand(this));
    addCommand(QuestCommand(this));
    addCommand(SubQuestCommand(this));
    addCommand(StepCommand(this));
    addCommand(BlockerCommand(this));
    addCommand(SideQuestCommand(this));
    addCommand(CompleteCommand(this));
    addCommand(ReopenCommand(this));
    addCommand(RemoveCommand(this));
    addCommand(VcsCommand(this));
    addCommand(BatchCommand(this));
    addCommand(RenderCommand(this));
    addCommand(MergeAuditCommand(this));
  }

  SessionStore get store => _store ??= SessionStore();

  @override
  Future<int> run(Iterable<String> args) async {
    final argsList = args.toList();

    if (argsList.contains('-h') ||
        argsList.contains('--help') ||
        (argsList.isNotEmpty && argsList.first == 'help')) {
      printUsage();
      return 0;
    }

    if (argsList.isEmpty) {
      final existing = await store.load();
      if (existing != null && existing.quests.isNotEmpty) {
        return await StatusCommand(this).run();
      }
      printUsage();
      return 0;
    }

    try {
      final results = parse(argsList);
      if (results.wasParsed('dir') && _store == null) {
        _store = SessionStore(directory: results['dir'] as String);
      }
      final exitCode = await runCommand(results);
      return exitCode ?? 0;
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      stderr.writeln();
      stderr.writeln(e.usage);
      return 1;
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    }
  }
}

/// Abstract base class for all `sidequest` commands.
abstract class SidequestCommand extends Command<int> {
  final SidequestCliRunner runner;

  SidequestCommand(this.runner);

  SessionStore get store => runner.store;

  Future<SidequestData> requireData() async {
    var data = await store.load();
    if (data == null) {
      data = SidequestData.initial(firstQuestTitle: 'Main Quest 1');
      await store.save(data);
    }
    return data;
  }
}

/// `sidequest status` command.
class StatusCommand extends SidequestCommand {
  @override
  final String name = 'status';

  @override
  final String description = 'Print compact 10-line session overview.';

  StatusCommand(super.runner);

  @override
  Future<int> run() async {
    final data = await store.load();
    if (data == null || data.quests.isEmpty) {
      stdout.writeln(
        'No active sidequest session map found in ${store.directory}.',
      );
      stdout.writeln(
        'Run "sidequest init <title>" to initialize a session map.',
      );
      return 0;
    }

    final activeQuest =
        data.quests.where((q) => q.status == QuestStatus.active).firstOrNull ??
        data.quests.first;

    stdout.writeln('🧭 Sidequest Status (${store.directory}):');
    stdout.writeln(
      '⚔️  Main Quest ${activeQuest.id}: "${activeQuest.title}" [${activeQuest.status.toJson().toUpperCase()}]',
    );

    if (activeQuest.vcs != null) {
      _printVcsStatus(activeQuest.vcs!);
    }

    _printBlockers(activeQuest.subQuests);
    _printSubQuests(activeQuest.subQuests, data.lastCompletionOrder);
    _printSideQuests([...data.globalSideQuests, ...activeQuest.sideQuests]);

    return 0;
  }
}

/// `sidequest init [title]` command.
class InitCommand extends SidequestCommand {
  @override
  final String name = 'init';

  @override
  final String description = 'Initialize sidequest session map.';

  InitCommand(super.runner);

  @override
  Future<int> run() async {
    final title = argResults?.rest.isNotEmpty == true
        ? argResults!.rest.join(' ')
        : 'Main Quest 1';
    final data = SidequestData.initial(firstQuestTitle: title);
    await store.save(data);
    stdout.writeln('✔ Initialized sidequest.json & rendered sidequest.md');
    return 0;
  }
}

/// `sidequest quest` command.
class QuestCommand extends SidequestCommand {
  @override
  final String name = 'quest';

  @override
  final String description = 'Manage main quests.';

  QuestCommand(super.runner) {
    addSubcommand(QuestAddCommand(runner));
    addSubcommand(QuestActivateCommand(runner));
    addSubcommand(QuestPauseCommand(runner));
  }
}

class QuestAddCommand extends SidequestCommand {
  @override
  final String name = 'add';

  @override
  final String description = 'Add a new main quest.';

  QuestAddCommand(super.runner);

  @override
  Future<int> run() async {
    final title = argResults?.rest.isNotEmpty == true
        ? argResults!.rest.join(' ')
        : 'New Main Quest';
    final data = await requireData();
    final nextQuestNumber =
        data.quests.map((q) => int.tryParse(q.id) ?? 0).fold(0, max) + 1;
    final newId = '$nextQuestNumber';
    data.quests.add(
      MainQuest(id: newId, title: title, status: QuestStatus.active, vcs: null),
    );
    await store.save(data);
    stdout.writeln('✔ Added Main Quest $newId: "$title"');
    return 0;
  }
}

class QuestActivateCommand extends SidequestCommand {
  @override
  final String name = 'activate';

  @override
  final String description = 'Activate a main quest.';

  QuestActivateCommand(super.runner);

  @override
  Future<int> run() async {
    final id = argResults?.rest.firstOrNull ?? '1';
    final data = await requireData();
    final quest = _findQuest(data, id);
    if (quest == null) return 1;
    quest.status = QuestStatus.active;
    await store.save(data);
    stdout.writeln('✔ Activated Main Quest $id');
    return 0;
  }
}

class QuestPauseCommand extends SidequestCommand {
  @override
  final String name = 'pause';

  @override
  final String description = 'Pause a main quest.';

  QuestPauseCommand(super.runner) {
    argParser.addOption('reason', help: 'Reason for pausing the quest.');
  }

  @override
  Future<int> run() async {
    final id = argResults?.rest.firstOrNull ?? '1';
    final data = await requireData();
    final quest = _findQuest(data, id);
    if (quest == null) return 1;
    quest.status = QuestStatus.paused;
    if (argResults?['reason'] != null) {
      quest.statusNote = argResults!['reason'] as String;
    }
    await store.save(data);
    stdout.writeln('✔ Paused Main Quest $id');
    return 0;
  }
}

/// `sidequest subquest` command.
class SubQuestCommand extends SidequestCommand {
  @override
  final String name = 'subquest';

  @override
  final String description = 'Manage sub-quests.';

  SubQuestCommand(super.runner) {
    addSubcommand(SubQuestAddCommand(runner));
  }
}

class SubQuestAddCommand extends SidequestCommand {
  @override
  final String name = 'add';

  @override
  final String description = 'Add a sub-quest under a main quest.';

  SubQuestAddCommand(super.runner);

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.length < 2) {
      usageException('Usage: subquest add <quest-id> <title>');
    }
    final questId = rest[0];
    final title = rest.sublist(1).join(' ');
    final data = await requireData();
    final quest = _findQuest(data, questId);
    if (quest == null) return 1;

    final nextSubNumber = _nextSuffixNumber(quest.subQuests.map((sq) => sq.id));
    final subId = '$questId.$nextSubNumber';
    quest.subQuests.add(
      SubQuest(id: subId, title: title, status: TaskStatus.inProgress),
    );
    await store.save(data);
    stdout.writeln('✔ Added Sub-Quest $subId: "$title"');
    return 0;
  }
}

/// `sidequest step` command.
class StepCommand extends SidequestCommand {
  @override
  final String name = 'step';

  @override
  final String description = 'Manage planned steps.';

  StepCommand(super.runner) {
    addSubcommand(StepAddCommand(runner));
  }
}

class StepAddCommand extends SidequestCommand {
  @override
  final String name = 'add';

  @override
  final String description = 'Add a planned step under a sub-quest.';

  StepAddCommand(super.runner);

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.length < 2) {
      usageException('Usage: step add <subquest-id> <title>');
    }
    final subId = rest[0];
    final title = rest.sublist(1).join(' ');
    final data = await requireData();
    final sub = _findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber = _nextSuffixNumber(sub.items.map((item) => item.id));
    final itemId = '$subId.$nextItemNumber';
    sub.items.add(
      TaskItem(
        id: itemId,
        type: TaskType.step,
        title: title,
        status: TaskStatus.pending,
      ),
    );
    await store.save(data);
    stdout.writeln('✔ Added Step $itemId: "$title"');
    return 0;
  }
}

/// `sidequest blocker` command.
class BlockerCommand extends SidequestCommand {
  @override
  final String name = 'blocker';

  @override
  final String description = 'Manage unplanned blockers.';

  BlockerCommand(super.runner) {
    addSubcommand(BlockerAddCommand(runner));
  }
}

class BlockerAddCommand extends SidequestCommand {
  @override
  final String name = 'add';

  @override
  final String description = 'Add an unplanned blocker under a sub-quest.';

  BlockerAddCommand(super.runner);

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.length < 2) {
      usageException('Usage: blocker add <subquest-id> <title>');
    }
    final subId = rest[0];
    final title = rest.sublist(1).join(' ');
    final data = await requireData();
    final sub = _findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber = _nextSuffixNumber(sub.items.map((item) => item.id));
    final itemId = '$subId.$nextItemNumber';
    sub.items.add(
      TaskItem(
        id: itemId,
        type: TaskType.blocker,
        title: title,
        status: TaskStatus.inProgress,
      ),
    );
    await store.save(data);
    stdout.writeln('✔ Added Blocker $itemId: "$title"');
    return 0;
  }
}

/// `sidequest sidequest` command.
class SideQuestCommand extends SidequestCommand {
  @override
  final String name = 'sidequest';

  @override
  final String description = 'Manage tangents and side quests.';

  SideQuestCommand(super.runner) {
    addSubcommand(SideQuestAddCommand(runner));
  }
}

class SideQuestAddCommand extends SidequestCommand {
  @override
  final String name = 'add';

  @override
  final String description = 'Add a side quest.';

  SideQuestAddCommand(super.runner) {
    argParser
      ..addOption('quest', help: 'Scope to a specific main quest ID.')
      ..addFlag('global', defaultsTo: false, help: 'Scope globally.')
      ..addFlag('parked', defaultsTo: false, help: 'Start in parked status.')
      ..addOption('note', help: 'Optional tracking note.');
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final title = results.rest.isNotEmpty
        ? results.rest.join(' ')
        : 'New Side Quest';
    final isParked = results['parked'] as bool;
    final status = isParked ? SideQuestStatus.parked : SideQuestStatus.active;
    final note = results['note'] as String?;

    final data = await requireData();
    final isGlobal =
        (results['global'] as bool) ||
        (results['quest'] == null && data.quests.isEmpty);

    if (isGlobal || results['quest'] == null) {
      final id = data.generateNextGlobalSideQuestId();
      data.globalSideQuests.add(
        SideQuest(id: id, title: title, status: status, note: note),
      );
      await store.save(data);
      stdout.writeln('✔ Added Global Side Quest $id: "$title"');
    } else {
      final qId = results['quest'] as String;
      final quest = _findQuest(data, qId);
      if (quest == null) return 1;
      final id = data.generateNextSideQuestId(quest);
      quest.sideQuests.add(
        SideQuest(id: id, title: title, status: status, note: note),
      );
      await store.save(data);
      stdout.writeln('✔ Added Side Quest $id (for Quest $qId): "$title"');
    }
    return 0;
  }
}

/// `sidequest complete <id...>` command.
class CompleteCommand extends SidequestCommand {
  @override
  final String name = 'complete';

  @override
  final String description = 'Mark one or more items completed.';

  CompleteCommand(super.runner);

  @override
  Future<int> run() async {
    final ids = _extractIds(argResults?.rest ?? const []);
    if (ids.isEmpty) {
      usageException('Usage: complete <id> [id2] [id3]...');
    }
    final data = await requireData();
    final completedIds = <String>[];
    final alreadyCompletedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      final nextOrder = data.lastCompletionOrder + 1;
      final result = _completeSingleItem(data, id, nextOrder);
      if (result == _ItemCompleteResult.completedWithOrder) {
        data.lastCompletionOrder = nextOrder;
        completedIds.add(id);
      } else if (result == _ItemCompleteResult.completedNoOrder) {
        completedIds.add(id);
      } else if (result == _ItemCompleteResult.alreadyCompleted) {
        alreadyCompletedIds.add(id);
      } else {
        notFoundIds.add(id);
      }
    }

    if (completedIds.isNotEmpty) {
      await store.save(data);
      final orderSuffix = data.lastCompletionOrder > 0
          ? ' (Order [#${data.lastCompletionOrder} ⭐])'
          : '';
      stdout.writeln(
        '✔ Completed item(s): ${completedIds.join(", ")}$orderSuffix',
      );
    }
    if (alreadyCompletedIds.isNotEmpty) {
      stdout.writeln('ℹ Already completed: ${alreadyCompletedIds.join(", ")}');
    }
    if (notFoundIds.isNotEmpty) {
      stderr.writeln('Error: Items not found: ${notFoundIds.join(", ")}');
      return completedIds.isEmpty && alreadyCompletedIds.isEmpty ? 1 : 0;
    }
    return 0;
  }
}

/// `sidequest reopen <id...>` command.
class ReopenCommand extends SidequestCommand {
  @override
  final String name = 'reopen';

  @override
  final String description = 'Reopen one or more completed items.';

  ReopenCommand(super.runner);

  @override
  Future<int> run() async {
    final ids = _extractIds(argResults?.rest ?? const []);
    if (ids.isEmpty) {
      usageException('Usage: reopen <id> [id2]...');
    }
    final data = await requireData();
    final reopenedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      if (_reopenSingleItem(data, id)) {
        reopenedIds.add(id);
      } else {
        notFoundIds.add(id);
      }
    }

    if (reopenedIds.isNotEmpty) {
      _recalculateMaxCompletionOrder(data);
      await store.save(data);
      stdout.writeln('✔ Reopened item(s): ${reopenedIds.join(", ")}');
    }
    if (notFoundIds.isNotEmpty) {
      stderr.writeln('Error: Items not found: ${notFoundIds.join(", ")}');
      return reopenedIds.isEmpty ? 1 : 0;
    }
    return 0;
  }
}

/// `sidequest remove <id...>` command.
class RemoveCommand extends SidequestCommand {
  @override
  final String name = 'remove';

  @override
  final String description = 'Remove one or more items.';

  RemoveCommand(super.runner);

  @override
  Future<int> run() async {
    final ids = _extractIds(argResults?.rest ?? const []);
    if (ids.isEmpty) {
      usageException('Usage: remove <id> [id2]...');
    }
    final data = await requireData();
    final removedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      if (_removeSingleItem(data, id)) {
        removedIds.add(id);
      } else {
        notFoundIds.add(id);
      }
    }

    if (removedIds.isNotEmpty) {
      _recalculateMaxCompletionOrder(data);
      await store.save(data);
      stdout.writeln('✔ Removed item(s): ${removedIds.join(", ")}');
    }
    if (notFoundIds.isNotEmpty) {
      stderr.writeln('Error: Items not found: ${notFoundIds.join(", ")}');
      return removedIds.isEmpty ? 1 : 0;
    }
    return 0;
  }
}

/// `sidequest vcs <qId>` command.
class VcsCommand extends SidequestCommand {
  @override
  final String name = 'vcs';

  @override
  final String description = 'Update VCS state for a main quest.';

  VcsCommand(super.runner) {
    argParser
      ..addOption('stage', defaultsTo: 'dirty')
      ..addOption('branch')
      ..addOption('files')
      ..addOption('details');
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final qId = results.rest.isNotEmpty ? results.rest[0] : '1';
    final data = await requireData();
    final quest = _findQuest(data, qId);
    if (quest == null) return 1;

    final filesStr = results['files'] as String?;
    final files = filesStr != null
        ? filesStr
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    quest.vcs = VcsState(
      stage: VcsStage.fromJson(results['stage'] as String),
      branch: results['branch'] as String?,
      modifiedFiles: files,
      details: results['details'] as String?,
    );

    await store.save(data);
    stdout.writeln('✔ Updated VCS state for Main Quest $qId');
    return 0;
  }
}

/// `sidequest batch <json>` command.
class BatchCommand extends SidequestCommand {
  @override
  final String name = 'batch';

  @override
  final String description = 'Execute multiple mutations in a single call.';

  BatchCommand(super.runner);

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.isEmpty) {
      usageException('Usage: batch <json-string>');
    }
    final decoded = jsonDecode(rest[0]);
    final data = await requireData();

    if (decoded is List) {
      _applyBatchList(data, decoded);
    } else if (decoded is Map<String, dynamic>) {
      _applyBatchMap(data, decoded);
    }

    await store.save(data);
    stdout.writeln('✔ Executed batch operations');
    return 0;
  }
}

/// `sidequest render` command.
class RenderCommand extends SidequestCommand {
  @override
  final String name = 'render';

  @override
  final String description = 'Re-render sidequest.md from sidequest.json.';

  RenderCommand(super.runner);

  @override
  Future<int> run() async {
    final data = await store.load();
    if (data == null) {
      stderr.writeln('Error: sidequest.json not found in ${store.directory}');
      return 1;
    }
    await store.save(data);
    stdout.writeln('✔ Rendered sidequest.md');
    return 0;
  }
}

/// `sidequest merge-audit` command.
class MergeAuditCommand extends SidequestCommand {
  @override
  final String name = 'merge-audit';

  @override
  final String description = 'Merge audited delta JSON into session map.';

  MergeAuditCommand(super.runner) {
    argParser.addOption('input', help: 'Path to audited delta JSON file.');
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final inputPath = (results['input'] as String?) ?? results.rest.firstOrNull;
    if (inputPath == null || !await File(inputPath).exists()) {
      stderr.writeln('Error: Missing or invalid --input file for merge-audit');
      return 1;
    }

    final auditContent = await File(inputPath).readAsString();
    final auditJson = jsonDecode(auditContent) as Map<String, dynamic>;
    final auditedData = SidequestData.fromJson(auditJson);

    await store.save(auditedData);
    stdout.writeln('✔ Merged audit delta and rendered sidequest.md');
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Pure domain helper functions (Extracted for low cognitive complexity)
// ---------------------------------------------------------------------------

void _printVcsStatus(VcsState vcs) {
  final branch = vcs.branch ?? 'N/A';
  final files = vcs.modifiedFiles.isEmpty
      ? 'none'
      : vcs.modifiedFiles.join(', ');
  stdout.writeln(
    '   VCS: ${vcs.stage.badge} | Branch: $branch | Modified: $files',
  );
}

void _printBlockers(List<SubQuest> subQuests) {
  final blockers = <String>[];
  for (final sq in subQuests) {
    for (final item in sq.items) {
      if (item.status != TaskStatus.completed &&
          item.type == TaskType.blocker) {
        blockers.add('👾 Blocker ${item.id}: "${item.title}"');
      }
    }
  }

  if (blockers.isNotEmpty) {
    stdout.writeln('   Blockers:');
    for (final b in blockers) {
      stdout.writeln('     * $b');
    }
  }
}

void _printSubQuests(List<SubQuest> subQuests, int lastCompletionOrder) {
  if (subQuests.isEmpty) return;

  stdout.writeln('   Sub-Quests & Steps:');
  for (final sq in subQuests) {
    final doneStr = sq.status == TaskStatus.completed
        ? '✔ (Done)'
        : '⏳ (In Progress)';
    stdout.writeln('     🛡️  Sub-Quest ${sq.id}: "${sq.title}" $doneStr');
    for (final item in sq.items) {
      _printTaskItem(item, lastCompletionOrder);
    }
  }
}

void _printTaskItem(TaskItem item, int lastCompletionOrder) {
  final itemDone = item.status == TaskStatus.completed ? '✔' : ' ';
  final icon = item.type == TaskType.blocker ? '👾' : '👣';
  final order = item.completionOrder != null
      ? (item.completionOrder == lastCompletionOrder
            ? '[#${item.completionOrder} ⭐]'
            : '[#${item.completionOrder}]')
      : '';
  final orderStr = order.isNotEmpty ? '$order ' : '';
  stdout.writeln(
    '        [$itemDone] $orderStr$icon ${item.id}: "${item.title}"',
  );
}

void _printSideQuests(List<SideQuest> sideQuests) {
  if (sideQuests.isEmpty) return;

  stdout.writeln('   🌿 Side Quests:');
  for (final sq in sideQuests) {
    final statusIcon = switch (sq.status) {
      SideQuestStatus.completed => '✔ Completed',
      SideQuestStatus.parked => '🎒 Parked',
      SideQuestStatus.active => '⚡ Active',
    };
    final note = sq.note != null ? ' (${sq.note})' : '';
    stdout.writeln('     * [$statusIcon] ${sq.id}: "${sq.title}"$note');
  }
}

List<String> _extractIds(List<String> args) => args
    .expand((arg) => arg.split(','))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

_ItemCompleteResult _completeSingleItem(
  SidequestData data,
  String id,
  int nextOrder,
) {
  for (final q in data.quests) {
    final qResult = _completeQuest(q, id, nextOrder);
    if (qResult != _ItemCompleteResult.notFound) return qResult;
  }

  for (final sq in data.globalSideQuests) {
    final sqResult = _completeSideQuest(sq, id, nextOrder);
    if (sqResult != _ItemCompleteResult.notFound) return sqResult;
  }

  return _ItemCompleteResult.notFound;
}

_ItemCompleteResult _completeQuest(MainQuest q, String id, int nextOrder) {
  if (q.id == id) {
    if (q.status == QuestStatus.completed) {
      return _ItemCompleteResult.alreadyCompleted;
    }
    q.status = QuestStatus.completed;
    return _ItemCompleteResult.completedNoOrder;
  }

  for (final sq in q.subQuests) {
    final sqResult = _completeSubQuest(sq, id, nextOrder);
    if (sqResult != _ItemCompleteResult.notFound) return sqResult;
  }

  for (final sq in q.sideQuests) {
    final sqResult = _completeSideQuest(sq, id, nextOrder);
    if (sqResult != _ItemCompleteResult.notFound) return sqResult;
  }

  return _ItemCompleteResult.notFound;
}

_ItemCompleteResult _completeSubQuest(SubQuest sq, String id, int nextOrder) {
  if (sq.id == id) {
    if (sq.status == TaskStatus.completed) {
      return _ItemCompleteResult.alreadyCompleted;
    }
    sq.status = TaskStatus.completed;
    sq.completionOrder = nextOrder;
    return _ItemCompleteResult.completedWithOrder;
  }

  for (final item in sq.items) {
    if (item.id == id) {
      if (item.status == TaskStatus.completed) {
        return _ItemCompleteResult.alreadyCompleted;
      }
      item.status = TaskStatus.completed;
      item.completionOrder = nextOrder;
      return _ItemCompleteResult.completedWithOrder;
    }
  }

  return _ItemCompleteResult.notFound;
}

_ItemCompleteResult _completeSideQuest(SideQuest sq, String id, int nextOrder) {
  if (sq.id != id) return _ItemCompleteResult.notFound;
  if (sq.status == SideQuestStatus.completed) {
    return _ItemCompleteResult.alreadyCompleted;
  }
  sq.status = SideQuestStatus.completed;
  sq.completionOrder = nextOrder;
  return _ItemCompleteResult.completedWithOrder;
}

bool _reopenSingleItem(SidequestData data, String id) {
  for (final q in data.quests) {
    if (_reopenQuest(q, id)) return true;
  }

  for (final sq in data.globalSideQuests) {
    if (sq.id == id) {
      sq.status = SideQuestStatus.active;
      sq.completionOrder = null;
      return true;
    }
  }

  return false;
}

bool _reopenQuest(MainQuest q, String id) {
  if (q.id == id) {
    q.status = QuestStatus.active;
    return true;
  }
  for (final sq in q.subQuests) {
    if (sq.id == id) {
      sq.status = TaskStatus.inProgress;
      sq.completionOrder = null;
      return true;
    }
    for (final item in sq.items) {
      if (item.id == id) {
        item.status = TaskStatus.pending;
        item.completionOrder = null;
        return true;
      }
    }
  }
  for (final sq in q.sideQuests) {
    if (sq.id == id) {
      sq.status = SideQuestStatus.active;
      sq.completionOrder = null;
      return true;
    }
  }
  return false;
}

bool _removeSingleItem(SidequestData data, String id) {
  bool found = false;
  if (data.quests.any((q) => q.id == id)) {
    data.quests.removeWhere((q) => q.id == id);
    return true;
  }

  for (final q in data.quests) {
    if (q.subQuests.any((sq) => sq.id == id)) {
      q.subQuests.removeWhere((sq) => sq.id == id);
      found = true;
    }
    for (final sq in q.subQuests) {
      if (sq.items.any((item) => item.id == id)) {
        sq.items.removeWhere((item) => item.id == id);
        found = true;
      }
    }
    if (q.sideQuests.any((sq) => sq.id == id)) {
      q.sideQuests.removeWhere((sq) => sq.id == id);
      found = true;
    }
  }

  if (data.globalSideQuests.any((sq) => sq.id == id)) {
    data.globalSideQuests.removeWhere((sq) => sq.id == id);
    found = true;
  }

  return found;
}

void _applyBatchList(SidequestData data, List<dynamic> list) {
  for (final op in list) {
    if (op is Map<String, dynamic>) {
      _applyBatchOp(data, op);
    }
  }
}

void _applyBatchMap(SidequestData data, Map<String, dynamic> map) {
  if (map['operations'] is List) {
    _applyBatchList(data, map['operations'] as List);
    return;
  }
  _applyLegacyBatchMap(data, map);
}

void _applyLegacyBatchMap(SidequestData data, Map<String, dynamic> map) {
  if (map['complete'] is List) {
    for (final id in map['complete'] as List) {
      final nextOrder = data.lastCompletionOrder + 1;
      final result = _completeSingleItem(data, id.toString(), nextOrder);
      if (result == _ItemCompleteResult.completedWithOrder) {
        data.lastCompletionOrder = nextOrder;
      }
    }
  }

  if (map['addSubQuest'] is Map) {
    final sqMap = map['addSubQuest'] as Map<String, dynamic>;
    final qId = sqMap['quest'] as String? ?? '1';
    final quest = _findQuest(data, qId);
    if (quest != null) {
      final nextSubNumber = _nextSuffixNumber(
        quest.subQuests.map((sq) => sq.id),
      );
      final subId = '$qId.$nextSubNumber';
      quest.subQuests.add(
        SubQuest(
          id: subId,
          title: sqMap['title'] as String? ?? 'New SubQuest',
          status: TaskStatus.inProgress,
        ),
      );
    }
  }

  if (map['vcs'] is Map) {
    final vcsMap = map['vcs'] as Map<String, dynamic>;
    final qId = vcsMap['quest'] as String? ?? '1';
    final quest = _findQuest(data, qId);
    if (quest != null) {
      final files =
          (vcsMap['files'] as List<dynamic>?)?.cast<String>() ?? const [];
      quest.vcs = VcsState(
        stage: VcsStage.fromJson(vcsMap['stage'] as String? ?? 'dirty'),
        branch: vcsMap['branch'] as String?,
        modifiedFiles: files,
        details: vcsMap['details'] as String?,
      );
    }
  }
}

void _applyBatchOp(SidequestData data, Map<String, dynamic> op) {
  final type = (op['type'] as String? ?? '').toLowerCase();

  switch (type) {
    case 'quest_add':
      _applyBatchQuestAdd(data, op);
    case 'complete':
      _applyBatchComplete(data, op);
    case 'subquest_add':
      _applyBatchSubQuestAdd(data, op);
    case 'step_add':
      _applyBatchStepAdd(data, op);
    case 'blocker_add':
      _applyBatchBlockerAdd(data, op);
    case 'sidequest_add':
      _applyBatchSideQuestAdd(data, op);
    case 'vcs':
      _applyBatchVcs(data, op);
  }
}

void _applyBatchQuestAdd(SidequestData data, Map<String, dynamic> op) {
  final title =
      op['title']?.toString() ??
      op['description']?.toString() ??
      'New Main Quest';
  final nextQuestNumber =
      data.quests.map((q) => int.tryParse(q.id) ?? 0).fold(0, max) + 1;
  data.quests.add(
    MainQuest(
      id: '$nextQuestNumber',
      title: title,
      status: QuestStatus.active,
      vcs: const VcsState(stage: VcsStage.dirty),
    ),
  );
}

void _applyBatchComplete(SidequestData data, Map<String, dynamic> op) {
  final rawIds = op['ids'] ?? op['id'];
  final idList = rawIds is List
      ? rawIds.map((e) => e.toString()).toList()
      : [rawIds?.toString() ?? ''];
  for (final id in idList.where((s) => s.isNotEmpty)) {
    final nextOrder = data.lastCompletionOrder + 1;
    final result = _completeSingleItem(data, id, nextOrder);
    if (result == _ItemCompleteResult.completedWithOrder) {
      data.lastCompletionOrder = nextOrder;
    }
  }
}

void _applyBatchSubQuestAdd(SidequestData data, Map<String, dynamic> op) {
  final qId = op['questId']?.toString() ?? op['quest']?.toString() ?? '1';
  final title =
      op['title']?.toString() ?? op['description']?.toString() ?? 'SubQuest';
  final quest = data.quests.where((q) => q.id == qId).firstOrNull;
  if (quest != null) {
    final nextSubNumber = _nextSuffixNumber(quest.subQuests.map((sq) => sq.id));
    final subId = '$qId.$nextSubNumber';
    quest.subQuests.add(
      SubQuest(id: subId, title: title, status: TaskStatus.inProgress),
    );
  }
}

void _applyBatchStepAdd(SidequestData data, Map<String, dynamic> op) {
  final subId =
      op['subquestId']?.toString() ?? op['subquest']?.toString() ?? '1.1';
  final title =
      op['title']?.toString() ?? op['description']?.toString() ?? 'Step';
  final sub = _findSubQuest(data, subId);
  if (sub != null) {
    final nextNumber = _nextSuffixNumber(sub.items.map((i) => i.id));
    sub.items.add(
      TaskItem(
        id: '$subId.$nextNumber',
        type: TaskType.step,
        title: title,
        status: TaskStatus.pending,
      ),
    );
  }
}

void _applyBatchBlockerAdd(SidequestData data, Map<String, dynamic> op) {
  final subId =
      op['subquestId']?.toString() ?? op['subquest']?.toString() ?? '1.1';
  final title =
      op['title']?.toString() ?? op['description']?.toString() ?? 'Blocker';
  final sub = _findSubQuest(data, subId);
  if (sub != null) {
    final nextNumber = _nextSuffixNumber(sub.items.map((i) => i.id));
    sub.items.add(
      TaskItem(
        id: '$subId.$nextNumber',
        type: TaskType.blocker,
        title: title,
        status: TaskStatus.inProgress,
      ),
    );
  }
}

void _applyBatchSideQuestAdd(SidequestData data, Map<String, dynamic> op) {
  final title =
      op['title']?.toString() ?? op['description']?.toString() ?? 'Side Quest';
  final isGlobal =
      op['global'] == true || (op['quest'] == null && data.quests.isEmpty);
  final isParked = op['parked'] == true;
  final status = isParked ? SideQuestStatus.parked : SideQuestStatus.active;
  final note = op['note']?.toString();

  if (isGlobal || op['quest'] == null) {
    final id = data.generateNextGlobalSideQuestId();
    data.globalSideQuests.add(
      SideQuest(id: id, title: title, status: status, note: note),
    );
  } else {
    final qId = op['quest'].toString();
    final quest = data.quests.where((q) => q.id == qId).firstOrNull;
    if (quest != null) {
      final id = data.generateNextSideQuestId(quest);
      quest.sideQuests.add(
        SideQuest(id: id, title: title, status: status, note: note),
      );
    }
  }
}

void _applyBatchVcs(SidequestData data, Map<String, dynamic> op) {
  final qId = op['quest']?.toString() ?? '1';
  final quest = data.quests.where((q) => q.id == qId).firstOrNull;
  if (quest != null) {
    final files = (op['files'] as List<dynamic>?)?.cast<String>() ?? const [];
    quest.vcs = VcsState(
      stage: VcsStage.fromJson(op['stage']?.toString() ?? 'dirty'),
      branch: op['branch']?.toString(),
      modifiedFiles: files,
      details: op['details']?.toString(),
    );
  }
}

MainQuest? _findQuest(SidequestData data, String id) {
  final q = data.quests.where((e) => e.id == id).firstOrNull;
  if (q == null) stderr.writeln('Error: Main Quest "$id" not found.');
  return q;
}

SubQuest? _findSubQuest(SidequestData data, String subId) {
  for (final q in data.quests) {
    for (final sq in q.subQuests) {
      if (sq.id == subId) return sq;
    }
  }
  stderr.writeln('Error: Sub-Quest "$subId" not found.');
  return null;
}

int _nextSuffixNumber(Iterable<String> ids) =>
    ids.map((id) => int.tryParse(id.split('.').last) ?? 0).fold(0, max) + 1;

void _recalculateMaxCompletionOrder(SidequestData data) {
  int maxOrder = 0;
  for (final q in data.quests) {
    for (final sq in q.subQuests) {
      if (sq.completionOrder != null) {
        maxOrder = max(maxOrder, sq.completionOrder!);
      }
      for (final item in sq.items) {
        if (item.completionOrder != null) {
          maxOrder = max(maxOrder, item.completionOrder!);
        }
      }
    }
    for (final sq in q.sideQuests) {
      if (sq.completionOrder != null) {
        maxOrder = max(maxOrder, sq.completionOrder!);
      }
    }
  }
  for (final sq in data.globalSideQuests) {
    if (sq.completionOrder != null) {
      maxOrder = max(maxOrder, sq.completionOrder!);
    }
  }
  data.lastCompletionOrder = maxOrder;
}
