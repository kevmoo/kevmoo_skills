import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

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

class SidequestCliRunner {
  final SessionStore store;

  SidequestCliRunner({required this.store});

  Future<int> run(List<String> args) async {
    if (args.contains('--help') || args.contains('-h')) {
      _printUsage();
      return 0;
    }

    if (args.isEmpty) {
      final existing = await store.load();
      if (existing != null && existing.quests.isNotEmpty) {
        return await _handleStatus();
      }
      _printUsage();
      return 0;
    }

    final command = args[0];
    final subArgs = args.sublist(1);

    try {
      switch (command) {
        case 'help':
          _printUsage();
          return 0;
        case 'status':
        case 'show':
        case 'summary':
        case 'list':
          return await _handleStatus();
        case 'init':
          return await _handleInit(subArgs);
        case 'quest':
          return await _handleQuest(subArgs);
        case 'subquest':
          return await _handleSubQuest(subArgs);
        case 'step':
          return await _handleStep(subArgs);
        case 'blocker':
          return await _handleBlocker(subArgs);
        case 'sidequest':
          return await _handleSideQuest(subArgs);
        case 'add':
          return await _handleDispatchAdd(subArgs);
        case 'complete':
        case 'done':
        case 'finish':
        case 'resolve':
          return await _handleComplete(subArgs);
        case 'reopen':
          return await _handleReopen(subArgs);
        case 'remove':
        case 'delete':
        case 'rm':
          return await _handleRemove(subArgs);
        case 'vcs':
          return await _handleVcs(subArgs);
        case 'batch':
          return await _handleBatch(subArgs);
        case 'render':
          return await _handleRender();
        case 'merge-audit':
          return await _handleMergeAudit(subArgs);
        default:
          stderr.writeln('Error: Unknown command "$command".');
          _printUsage();
          return 1;
      }
    } catch (e) {
      stderr.writeln('Error running sidequest command "$command": $e');
      return 1;
    }
  }

  Future<int> _handleStatus() async {
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
      final vcs = activeQuest.vcs!;
      final branch = vcs.branch ?? 'N/A';
      final files = vcs.modifiedFiles.isEmpty
          ? 'none'
          : vcs.modifiedFiles.join(', ');
      stdout.writeln(
        '   VCS: ${vcs.stage.badge} | Branch: $branch | Modified: $files',
      );
    }

    final blockers = <String>[];
    for (final sq in activeQuest.subQuests) {
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

    if (activeQuest.subQuests.isNotEmpty) {
      stdout.writeln('   Sub-Quests & Steps:');
      for (final sq in activeQuest.subQuests) {
        final doneStr = sq.status == TaskStatus.completed
            ? '✔ (Done)'
            : '⏳ (In Progress)';
        stdout.writeln('     🛡️  Sub-Quest ${sq.id}: "${sq.title}" $doneStr');
        for (final item in sq.items) {
          final itemDone = item.status == TaskStatus.completed ? '✔' : ' ';
          final icon = item.type == TaskType.blocker ? '👾' : '👣';
          final order = item.completionOrder != null
              ? (item.completionOrder == data.lastCompletionOrder
                    ? '[#${item.completionOrder} ⭐]'
                    : '[#${item.completionOrder}]')
              : '';
          final orderStr = order.isNotEmpty ? '$order ' : '';
          stdout.writeln(
            '        [$itemDone] $orderStr$icon ${item.id}: "${item.title}"',
          );
        }
      }
    }

    final allSideQuests = [...data.globalSideQuests, ...activeQuest.sideQuests];
    if (allSideQuests.isNotEmpty) {
      stdout.writeln('   🌿 Side Quests:');
      for (final sq in allSideQuests) {
        final statusIcon = switch (sq.status) {
          SideQuestStatus.completed => '✔ Completed',
          SideQuestStatus.parked => '🎒 Parked',
          SideQuestStatus.active => '⚡ Active',
        };
        final note = sq.note != null ? ' (${sq.note})' : '';
        stdout.writeln('     * [$statusIcon] ${sq.id}: "${sq.title}"$note');
      }
    }

    return 0;
  }

  Future<int> _handleDispatchAdd(List<String> args) async {
    if (args.isEmpty) {
      return await _handleSideQuest(['add']);
    }
    final target = args[0];
    final rest = args.sublist(1);

    switch (target) {
      case 'quest':
        return await _handleQuest(['add', ...rest]);
      case 'subquest':
        return await _handleSubQuest(['add', ...rest]);
      case 'step':
        return await _handleStep(['add', ...rest]);
      case 'blocker':
        return await _handleBlocker(['add', ...rest]);
      case 'sidequest':
        return await _handleSideQuest(['add', ...rest]);
      default:
        // Default treat "add <title>" as adding a sidequest
        return await _handleSideQuest(['add', ...args]);
    }
  }

  Future<int> _handleInit(List<String> args) async {
    final title = args.isNotEmpty ? args.join(' ') : 'Main Quest 1';
    final data = SidequestData.initial(firstQuestTitle: title);
    await store.save(data);
    stdout.writeln('✔ Initialized sidequest.json & rendered sidequest.md');
    return 0;
  }

  Future<int> _handleQuest(List<String> args) async {
    if (args.isEmpty) {
      stderr.writeln('Usage: quest <add|activate|pause> [args]');
      return 1;
    }
    final action = args[0];
    final data = await _requireData();

    switch (action) {
      case 'add':
        final title = args.length > 1
            ? args.sublist(1).join(' ')
            : 'New Main Quest';
        final nextQuestNumber =
            data.quests.map((q) => int.tryParse(q.id) ?? 0).fold(0, max) + 1;
        final newId = '$nextQuestNumber';
        data.quests.add(
          MainQuest(
            id: newId,
            title: title,
            status: QuestStatus.active,
            vcs: const VcsState(stage: VcsStage.dirty),
          ),
        );
        await store.save(data);
        stdout.writeln('✔ Added Main Quest $newId: "$title"');
        return 0;
      case 'activate':
        final id = args.length > 1 ? args[1] : '1';
        final quest = _findQuest(data, id);
        if (quest == null) return 1;
        quest.status = QuestStatus.active;
        await store.save(data);
        stdout.writeln('✔ Activated Main Quest $id');
        return 0;
      case 'pause':
        final parser = ArgParser()..addOption('reason');
        final results = parser.parse(args.sublist(1));
        final id = results.rest.isNotEmpty ? results.rest[0] : '1';
        final quest = _findQuest(data, id);
        if (quest == null) return 1;
        quest.status = QuestStatus.paused;
        if (results['reason'] != null) {
          quest.statusNote = results['reason'] as String;
        }
        await store.save(data);
        stdout.writeln('✔ Paused Main Quest $id');
        return 0;
      default:
        stderr.writeln('Error: Unknown quest action "$action"');
        return 1;
    }
  }

  int _nextSuffixNumber(Iterable<String> ids) =>
      ids.map((id) => int.tryParse(id.split('.').last) ?? 0).fold(0, max) + 1;

  Future<int> _handleTaskItem({
    required List<String> args,
    required TaskType type,
    required String commandName,
    required String label,
    required TaskStatus defaultStatus,
  }) async {
    final effectiveArgs = args.isNotEmpty && args[0] == 'add'
        ? args.sublist(1)
        : args;

    if (effectiveArgs.length < 2) {
      stderr.writeln('Usage: $commandName [add] <subquest-id> <title>');
      return 1;
    }
    final subId = effectiveArgs[0];
    final title = effectiveArgs.sublist(1).join(' ');
    final data = await _requireData();
    final sub = _findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber = _nextSuffixNumber(sub.items.map((item) => item.id));
    final itemId = '$subId.$nextItemNumber';
    sub.items.add(
      TaskItem(id: itemId, type: type, title: title, status: defaultStatus),
    );
    await store.save(data);
    stdout.writeln('✔ Added $label $itemId: "$title"');
    return 0;
  }

  Future<int> _handleSubQuest(List<String> args) async {
    final effectiveArgs = args.isNotEmpty && args[0] == 'add'
        ? args.sublist(1)
        : args;

    if (effectiveArgs.length < 2) {
      stderr.writeln('Usage: subquest [add] <quest-id> <title>');
      return 1;
    }
    final questId = effectiveArgs[0];
    final title = effectiveArgs.sublist(1).join(' ');
    final data = await _requireData();
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

  Future<int> _handleStep(List<String> args) => _handleTaskItem(
    args: args,
    type: TaskType.step,
    commandName: 'step',
    label: 'Step',
    defaultStatus: TaskStatus.pending,
  );

  Future<int> _handleBlocker(List<String> args) => _handleTaskItem(
    args: args,
    type: TaskType.blocker,
    commandName: 'blocker',
    label: 'Blocker',
    defaultStatus: TaskStatus.inProgress,
  );

  Future<int> _handleSideQuest(List<String> args) async {
    final effectiveArgs = args.isNotEmpty && args[0] == 'add'
        ? args.sublist(1)
        : args;

    final parser = ArgParser()
      ..addOption('quest')
      ..addFlag('global', defaultsTo: false)
      ..addFlag('parked', defaultsTo: false)
      ..addOption('note');

    final results = parser.parse(effectiveArgs);
    final title = results.rest.isNotEmpty
        ? results.rest.join(' ')
        : 'New Side Quest';
    final isParked = results['parked'] as bool;
    final status = isParked ? SideQuestStatus.parked : SideQuestStatus.active;
    final note = results['note'] as String?;

    final data = await _requireData();
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

  List<String> _extractIds(List<String> args) => args
      .expand((arg) => arg.split(','))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<int> _handleComplete(List<String> args) async {
    final ids = _extractIds(args);
    if (ids.isEmpty) {
      stderr.writeln('Usage: complete <id> [id2] [id3]...');
      return 1;
    }
    final data = await _requireData();
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

  _ItemCompleteResult _completeSingleItem(
    SidequestData data,
    String id,
    int nextOrder,
  ) {
    for (final q in data.quests) {
      if (q.id == id) {
        if (q.status == QuestStatus.completed) {
          return _ItemCompleteResult.alreadyCompleted;
        }
        q.status = QuestStatus.completed;
        return _ItemCompleteResult.completedNoOrder;
      }
      for (final sq in q.subQuests) {
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
      }
      for (final sq in q.sideQuests) {
        if (sq.id == id) {
          if (sq.status == SideQuestStatus.completed) {
            return _ItemCompleteResult.alreadyCompleted;
          }
          sq.status = SideQuestStatus.completed;
          sq.completionOrder = nextOrder;
          return _ItemCompleteResult.completedWithOrder;
        }
      }
    }

    for (final sq in data.globalSideQuests) {
      if (sq.id == id) {
        if (sq.status == SideQuestStatus.completed) {
          return _ItemCompleteResult.alreadyCompleted;
        }
        sq.status = SideQuestStatus.completed;
        sq.completionOrder = nextOrder;
        return _ItemCompleteResult.completedWithOrder;
      }
    }

    return _ItemCompleteResult.notFound;
  }

  Future<int> _handleReopen(List<String> args) async {
    final ids = _extractIds(args);
    if (ids.isEmpty) {
      stderr.writeln('Usage: reopen <id> [id2]...');
      return 1;
    }
    final data = await _requireData();
    final reopenedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      bool found = false;
      for (final q in data.quests) {
        if (q.id == id) {
          q.status = QuestStatus.active;
          found = true;
        }
        for (final sq in q.subQuests) {
          if (sq.id == id) {
            sq.status = TaskStatus.inProgress;
            sq.completionOrder = null;
            found = true;
          }
          for (final item in sq.items) {
            if (item.id == id) {
              item.status = TaskStatus.pending;
              item.completionOrder = null;
              found = true;
            }
          }
        }
        for (final sq in q.sideQuests) {
          if (sq.id == id) {
            sq.status = SideQuestStatus.active;
            sq.completionOrder = null;
            found = true;
          }
        }
      }

      for (final sq in data.globalSideQuests) {
        if (sq.id == id) {
          sq.status = SideQuestStatus.active;
          sq.completionOrder = null;
          found = true;
        }
      }

      if (found) {
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

  Future<int> _handleRemove(List<String> args) async {
    final ids = _extractIds(args);
    if (ids.isEmpty) {
      stderr.writeln('Usage: remove <id> [id2]...');
      return 1;
    }
    final data = await _requireData();
    final removedIds = <String>[];
    final notFoundIds = <String>[];

    for (final id in ids) {
      bool found = false;
      if (data.quests.any((q) => q.id == id)) {
        data.quests.removeWhere((q) => q.id == id);
        found = true;
      }

      for (final q in data.quests) {
        if (q.subQuests.any((sq) => sq.id == id)) found = true;
        q.subQuests.removeWhere((sq) => sq.id == id);
        for (final sq in q.subQuests) {
          if (sq.items.any((item) => item.id == id)) found = true;
          sq.items.removeWhere((item) => item.id == id);
        }
        if (q.sideQuests.any((sq) => sq.id == id)) found = true;
        q.sideQuests.removeWhere((sq) => sq.id == id);
      }

      if (data.globalSideQuests.any((sq) => sq.id == id)) {
        data.globalSideQuests.removeWhere((sq) => sq.id == id);
        found = true;
      }

      if (found) {
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

  Future<int> _handleVcs(List<String> args) async {
    final parser = ArgParser()
      ..addOption('stage', defaultsTo: 'dirty')
      ..addOption('branch')
      ..addOption('files')
      ..addOption('details');

    final results = parser.parse(args);
    final qId = results.rest.isNotEmpty ? results.rest[0] : '1';
    final data = await _requireData();
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

  Future<int> _handleBatch(List<String> args) async {
    if (args.isEmpty) {
      stderr.writeln('Usage: batch <json-string>');
      return 1;
    }
    final decoded = jsonDecode(args[0]);
    final data = await _requireData();

    if (decoded is List) {
      for (final op in decoded) {
        if (op is Map<String, dynamic>) {
          _applyBatchOp(data, op);
        }
      }
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['operations'] is List) {
        for (final op in decoded['operations'] as List) {
          if (op is Map<String, dynamic>) {
            _applyBatchOp(data, op);
          }
        }
      } else {
        // Legacy batchMap format
        if (decoded['complete'] is List) {
          for (final id in decoded['complete'] as List) {
            final nextOrder = data.lastCompletionOrder + 1;
            final result = _completeSingleItem(data, id.toString(), nextOrder);
            if (result == _ItemCompleteResult.completedWithOrder) {
              data.lastCompletionOrder = nextOrder;
            }
          }
        }

        if (decoded['addSubQuest'] is Map) {
          final map = decoded['addSubQuest'] as Map<String, dynamic>;
          final qId = map['quest'] as String? ?? '1';
          final quest = _findQuest(data, qId);
          if (quest != null) {
            final nextSubNumber = _nextSuffixNumber(
              quest.subQuests.map((sq) => sq.id),
            );
            final subId = '$qId.$nextSubNumber';
            quest.subQuests.add(
              SubQuest(
                id: subId,
                title: map['title'] as String? ?? 'New SubQuest',
                status: TaskStatus.inProgress,
              ),
            );
          }
        }

        if (decoded['vcs'] is Map) {
          final map = decoded['vcs'] as Map<String, dynamic>;
          final qId = map['quest'] as String? ?? '1';
          final quest = _findQuest(data, qId);
          if (quest != null) {
            final files =
                (map['files'] as List<dynamic>?)?.cast<String>() ?? const [];
            quest.vcs = VcsState(
              stage: VcsStage.fromJson(map['stage'] as String? ?? 'dirty'),
              branch: map['branch'] as String?,
              modifiedFiles: files,
              details: map['details'] as String?,
            );
          }
        }
      }
    }

    await store.save(data);
    stdout.writeln('✔ Executed batch operations');
    return 0;
  }

  void _applyBatchOp(SidequestData data, Map<String, dynamic> op) {
    final type = (op['type'] as String? ?? '').toLowerCase();

    switch (type) {
      case 'quest_add':
      case 'add_quest':
      case 'quest':
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
        break;
      case 'complete':
      case 'done':
      case 'finish':
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
        break;
      case 'subquest_add':
      case 'add_subquest':
      case 'subquest':
        final qId = op['questId']?.toString() ?? op['quest']?.toString() ?? '1';
        final title =
            op['title']?.toString() ??
            op['description']?.toString() ??
            'SubQuest';
        final quest = data.quests.where((q) => q.id == qId).firstOrNull;
        if (quest != null) {
          final nextSubNumber = _nextSuffixNumber(
            quest.subQuests.map((sq) => sq.id),
          );
          final subId = '$qId.$nextSubNumber';
          quest.subQuests.add(
            SubQuest(id: subId, title: title, status: TaskStatus.inProgress),
          );
        }
        break;
      case 'step_add':
      case 'add_step':
      case 'step':
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
        break;
      case 'blocker_add':
      case 'add_blocker':
      case 'blocker':
        final subId =
            op['subquestId']?.toString() ?? op['subquest']?.toString() ?? '1.1';
        final title =
            op['title']?.toString() ??
            op['description']?.toString() ??
            'Blocker';
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
        break;
      case 'sidequest_add':
      case 'add_sidequest':
      case 'sidequest':
        final title =
            op['title']?.toString() ??
            op['description']?.toString() ??
            'Side Quest';
        final isGlobal =
            op['global'] == true ||
            (op['quest'] == null && data.quests.isEmpty);
        final isParked = op['parked'] == true;
        final status = isParked
            ? SideQuestStatus.parked
            : SideQuestStatus.active;
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
        break;
      case 'vcs':
        final qId = op['quest']?.toString() ?? '1';
        final quest = data.quests.where((q) => q.id == qId).firstOrNull;
        if (quest != null) {
          final files =
              (op['files'] as List<dynamic>?)?.cast<String>() ?? const [];
          quest.vcs = VcsState(
            stage: VcsStage.fromJson(op['stage']?.toString() ?? 'dirty'),
            branch: op['branch']?.toString(),
            modifiedFiles: files,
            details: op['details']?.toString(),
          );
        }
        break;
    }
  }

  Future<int> _handleRender() async {
    final data = await store.load();
    if (data == null) {
      stderr.writeln('Error: sidequest.json not found in ${store.directory}');
      return 1;
    }
    await store.save(data);
    stdout.writeln('✔ Rendered sidequest.md');
    return 0;
  }

  Future<int> _handleMergeAudit(List<String> args) async {
    final parser = ArgParser()..addOption('input');
    final results = parser.parse(args);
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

  Future<SidequestData> _requireData() async {
    var data = await store.load();
    if (data == null) {
      data = SidequestData.initial(firstQuestTitle: 'Main Quest 1');
      await store.save(data);
    }
    return data;
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

  void _printUsage() {
    stdout.writeln('''
sidequest CLI - Deterministic session map manager

Usage:
  sidequest [command] [args] [--dir=path]

Global Options:
  --dir=<path>            Path to session artifact directory containing sidequest.json

Inspection:
  status, show, summary   Print compact 10-line session overview (default if state exists)

Mutations:
  init [title]            Initialize sidequest session map (default: "Main Quest 1")
  quest add <title>       Add a new main quest
  subquest add <qId> <t>  Add a sub-quest under main quest <qId>
  step add <subId> <t>    Add a planned step under sub-quest <subId>
  blocker add <subId> <t> Add an unplanned blocker under sub-quest <subId>
  sidequest add <t>       Add a side quest (--quest=<qId>, --global, --parked, --note=<n>)
  complete <id...>        Mark one or more items completed (alias: done, finish, resolve)
  reopen <id...>          Reopen one or more completed items
  remove <id...>          Remove one or more items (alias: delete, rm)
  vcs <qId>               Update VCS state (--stage=dirty|local_commit|uploaded|merged|clean)
  batch <json>            Execute multiple mutations in a single call
  render                  Re-render sidequest.md from sidequest.json
  merge-audit --input=<f> Merge audited delta JSON into session map
  help, --help, -h        Show this help message''');
  }
}
