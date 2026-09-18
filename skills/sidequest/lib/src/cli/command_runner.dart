import 'command_runner_helpers.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';

import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';
import '../storage/session_store.dart';

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

  String joinRestOrDefault(String fallback) {
    final rest = argResults?.rest;
    return (rest != null && rest.isNotEmpty) ? rest.join(' ') : fallback;
  }

  Future<int> updateQuestStatus(
    QuestStatus status,
    String actionVerb, {
    String? statusNote,
  }) async {
    final id = argResults?.rest.firstOrNull ?? '1';
    final data = await requireData();
    final quest = findQuest(data, id);
    if (quest == null) return 1;
    quest.status = status;
    if (statusNote != null) {
      quest.statusNote = statusNote;
    }
    await store.save(data);
    stdout.writeln('✔ $actionVerb Main Quest $id');
    return 0;
  }

  (String id, String title) requireIdAndTitle(String usage) {
    final rest = argResults?.rest ?? const [];
    if (rest.length < 2) {
      usageException(usage);
    }
    return (rest[0], rest.sublist(1).join(' '));
  }

  Future<int> addSubQuestItem({
    required String usage,
    required TaskType type,
    required TaskStatus status,
    required String label,
  }) async {
    final (subId, title) = requireIdAndTitle(usage);
    final data = await requireData();
    final sub = findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber = nextSuffixNumber(sub.items.map((item) => item.id));
    final itemId = '$subId.$nextItemNumber';
    sub.items.add(
      TaskItem(id: itemId, type: type, title: title, status: status),
    );
    await store.save(data);
    stdout.writeln('✔ Added $label $itemId: "$title"');
    return 0;
  }

  List<String> requireNonEmptyIds(String usage) {
    final ids = extractIds(argResults?.rest ?? const []);
    if (ids.isEmpty) {
      usageException(usage);
    }
    return ids;
  }

  Future<int> mutateItemsByIds({
    required String usage,
    required bool Function(SidequestData data, String id) mutate,
    required String actionLabel,
  }) async {
    final ids = requireNonEmptyIds(usage);
    final data = await requireData();
    final mutatedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      if (mutate(data, id)) {
        mutatedIds.add(id);
      } else {
        notFoundIds.add(id);
      }
    }

    if (mutatedIds.isNotEmpty) {
      recalculateMaxCompletionOrder(data);
      await store.save(data);
      stdout.writeln('✔ $actionLabel item(s): ${mutatedIds.join(", ")}');
    }
    if (notFoundIds.isNotEmpty) {
      stderr.writeln('Error: Items not found: ${notFoundIds.join(", ")}');
      return mutatedIds.isEmpty ? 1 : 0;
    }
    return 0;
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
      printVcsStatus(activeQuest.vcs!);
    }

    printBlockers(activeQuest.subQuests);
    printSubQuests(activeQuest.subQuests, data.lastCompletionOrder);
    printSideQuests([...data.globalSideQuests, ...activeQuest.sideQuests]);

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
    final title = joinRestOrDefault('Main Quest 1');
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
    final title = joinRestOrDefault('New Main Quest');
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
  Future<int> run() => updateQuestStatus(QuestStatus.active, 'Activated');
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
  Future<int> run() => updateQuestStatus(
    QuestStatus.paused,
    'Paused',
    statusNote: argResults?['reason'] as String?,
  );
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
    final (questId, title) = requireIdAndTitle(
      'Usage: subquest add <quest-id> <title>',
    );
    final data = await requireData();
    final quest = findQuest(data, questId);
    if (quest == null) return 1;

    final nextSubNumber = nextSuffixNumber(quest.subQuests.map((sq) => sq.id));
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
  Future<int> run() => addSubQuestItem(
    usage: 'Usage: step add <subquest-id> <title>',
    type: TaskType.step,
    status: TaskStatus.pending,
    label: 'Step',
  );
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
  Future<int> run() => addSubQuestItem(
    usage: 'Usage: blocker add <subquest-id> <title>',
    type: TaskType.blocker,
    status: TaskStatus.inProgress,
    label: 'Blocker',
  );
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
    final title = joinRestOrDefault('New Side Quest');
    final isParked = results['parked'] as bool;
    final status = isParked ? SideQuestStatus.parked : SideQuestStatus.active;
    final note = results['note'] as String?;

    final data = await requireData();
    final isGlobal =
        (results['global'] as bool) ||
        (results['quest'] == null && data.quests.isEmpty);

    if (isGlobal || results['quest'] == null) {
      final id = addGlobalSideQuest(
        data,
        title: title,
        status: status,
        note: note,
      );
      await store.save(data);
      stdout.writeln('✔ Added Global Side Quest $id: "$title"');
    } else {
      final qId = results['quest'] as String;
      final quest = findQuest(data, qId);
      if (quest == null) return 1;
      final id = addQuestSideQuest(
        data,
        quest,
        title: title,
        status: status,
        note: note,
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
    final ids = requireNonEmptyIds('Usage: complete <id> [id2] [id3]...');
    final data = await requireData();
    final completedIds = <String>[];
    final alreadyCompletedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      final nextOrder = data.lastCompletionOrder + 1;
      final result = completeSingleItem(data, id, nextOrder);
      if (result == ItemCompleteResult.completedWithOrder) {
        data.lastCompletionOrder = nextOrder;
        completedIds.add(id);
      } else if (result == ItemCompleteResult.completedNoOrder) {
        completedIds.add(id);
      } else if (result == ItemCompleteResult.alreadyCompleted) {
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
  Future<int> run() => mutateItemsByIds(
    usage: 'Usage: reopen <id> [id2]...',
    mutate: reopenSingleItem,
    actionLabel: 'Reopened',
  );
}

/// `sidequest remove <id...>` command.
class RemoveCommand extends SidequestCommand {
  @override
  final String name = 'remove';

  @override
  final String description = 'Remove one or more items.';

  RemoveCommand(super.runner);

  @override
  Future<int> run() => mutateItemsByIds(
    usage: 'Usage: remove <id> [id2]...',
    mutate: removeSingleItem,
    actionLabel: 'Removed',
  );
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
    final quest = findQuest(data, qId);
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
    final dataClone = SidequestData.fromJson(data.toJson());

    final (int applied, int total) result;
    try {
      result = executeBatchPayload(dataClone, decoded);
    } catch (e) {
      stderr.writeln('Error applying batch: $e');
      return 1;
    }

    final (applied, total) = result;
    if (total > 0 && applied == 0) {
      stderr.writeln('Error: 0 of $total operations applied.');
      return 1;
    }

    await store.save(dataClone);
    stdout.writeln('✔ Executed $applied of $total batch operations');
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
