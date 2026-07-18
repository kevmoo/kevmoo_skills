import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';
import '../storage/session_store.dart';

class SidequestCliRunner {
  final SessionStore store;

  SidequestCliRunner({required this.store});

  Future<int> run(List<String> args) async {
    if (args.isEmpty) {
      _printUsage();
      return 1;
    }

    final command = args[0];
    final subArgs = args.sublist(1);

    try {
      switch (command) {
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
        case 'complete':
          return await _handleComplete(subArgs);
        case 'reopen':
          return await _handleReopen(subArgs);
        case 'remove':
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

  Future<int> _handleSubQuest(List<String> args) async {
    if (args.length < 3 || args[0] != 'add') {
      stderr.writeln('Usage: subquest add <quest-id> <title>');
      return 1;
    }
    final questId = args[1];
    final title = args.sublist(2).join(' ');
    final data = await _requireData();
    final quest = _findQuest(data, questId);
    if (quest == null) return 1;

    final nextSubNumber =
        quest.subQuests
            .map((sq) => int.tryParse(sq.id.split('.').last) ?? 0)
            .fold(0, max) +
        1;
    final subId = '$questId.$nextSubNumber';
    quest.subQuests.add(
      SubQuest(id: subId, title: title, status: TaskStatus.inProgress),
    );
    await store.save(data);
    stdout.writeln('✔ Added Sub-Quest $subId: "$title"');
    return 0;
  }

  Future<int> _handleStep(List<String> args) async {
    if (args.length < 3 || args[0] != 'add') {
      stderr.writeln('Usage: step add <subquest-id> <title>');
      return 1;
    }
    final subId = args[1];
    final title = args.sublist(2).join(' ');
    final data = await _requireData();
    final sub = _findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber =
        sub.items
            .map((item) => int.tryParse(item.id.split('.').last) ?? 0)
            .fold(0, max) +
        1;
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

  Future<int> _handleBlocker(List<String> args) async {
    if (args.length < 3 || args[0] != 'add') {
      stderr.writeln('Usage: blocker add <subquest-id> <title>');
      return 1;
    }
    final subId = args[1];
    final title = args.sublist(2).join(' ');
    final data = await _requireData();
    final sub = _findSubQuest(data, subId);
    if (sub == null) return 1;

    final nextItemNumber =
        sub.items
            .map((item) => int.tryParse(item.id.split('.').last) ?? 0)
            .fold(0, max) +
        1;
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

  Future<int> _handleSideQuest(List<String> args) async {
    if (args.isEmpty || args[0] != 'add') {
      stderr.writeln(
        'Usage: sidequest add <title> [--quest=id] [--global] [--parked] [--note=...]',
      );
      return 1;
    }
    final parser = ArgParser()
      ..addOption('quest')
      ..addFlag('global', defaultsTo: false)
      ..addFlag('parked', defaultsTo: false)
      ..addOption('note');

    final results = parser.parse(args.sublist(1));
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
      final nextGlobalNumber =
          data.globalSideQuests
              .map(
                (sq) =>
                    int.tryParse(
                      sq.id.startsWith('G') ? sq.id.substring(1) : sq.id,
                    ) ??
                    0,
              )
              .fold(0, max) +
          1;
      final id = 'G$nextGlobalNumber';
      data.globalSideQuests.add(
        SideQuest(id: id, title: title, status: status, note: note),
      );
      await store.save(data);
      stdout.writeln('✔ Added Global Side Quest $id: "$title"');
    } else {
      final qId = results['quest'] as String;
      final quest = _findQuest(data, qId);
      if (quest == null) return 1;
      final nextSideNumber =
          quest.sideQuests
              .map(
                (sq) =>
                    int.tryParse(
                      sq.id.startsWith('S') ? sq.id.substring(1) : sq.id,
                    ) ??
                    0,
              )
              .fold(0, max) +
          1;
      final id = 'S$nextSideNumber';
      quest.sideQuests.add(
        SideQuest(id: id, title: title, status: status, note: note),
      );
      await store.save(data);
      stdout.writeln('✔ Added Side Quest $id (for Quest $qId): "$title"');
    }
    return 0;
  }

  Future<int> _handleComplete(List<String> args) async {
    if (args.isEmpty) {
      stderr.writeln('Usage: complete <id>');
      return 1;
    }
    final id = args[0];
    final data = await _requireData();

    final nextOrder = data.lastCompletionOrder + 1;
    bool found = false;

    for (final q in data.quests) {
      if (q.id == id) {
        if (q.status == QuestStatus.completed) {
          stdout.writeln('✔ Main Quest $id is already completed.');
          return 0;
        }
        q.status = QuestStatus.completed;
        found = true;
        break;
      }
      for (final sq in q.subQuests) {
        if (sq.id == id) {
          if (sq.status == TaskStatus.completed) {
            stdout.writeln('✔ Sub-Quest $id is already completed.');
            return 0;
          }
          sq.status = TaskStatus.completed;
          sq.completionOrder = nextOrder;
          data.lastCompletionOrder = nextOrder;
          found = true;
          break;
        }
        for (final item in sq.items) {
          if (item.id == id) {
            if (item.status == TaskStatus.completed) {
              stdout.writeln('✔ Item $id is already completed.');
              return 0;
            }
            item.status = TaskStatus.completed;
            item.completionOrder = nextOrder;
            data.lastCompletionOrder = nextOrder;
            found = true;
            break;
          }
        }
        if (found) break;
      }
      if (found) break;
      for (final sq in q.sideQuests) {
        if (sq.id == id) {
          if (sq.status == SideQuestStatus.completed) {
            stdout.writeln('✔ Side Quest $id is already completed.');
            return 0;
          }
          sq.status = SideQuestStatus.completed;
          sq.completionOrder = nextOrder;
          data.lastCompletionOrder = nextOrder;
          found = true;
          break;
        }
      }
      if (found) break;
    }

    if (!found) {
      for (final sq in data.globalSideQuests) {
        if (sq.id == id) {
          if (sq.status == SideQuestStatus.completed) {
            stdout.writeln('✔ Global Side Quest $id is already completed.');
            return 0;
          }
          sq.status = SideQuestStatus.completed;
          sq.completionOrder = nextOrder;
          data.lastCompletionOrder = nextOrder;
          found = true;
          break;
        }
      }
    }

    if (!found) {
      stderr.writeln('Error: Item with ID "$id" not found.');
      return 1;
    }

    await store.save(data);
    stdout.writeln('✔ Completed item $id (Order [#$nextOrder ⭐])');
    return 0;
  }

  Future<int> _handleReopen(List<String> args) async {
    if (args.isEmpty) {
      stderr.writeln('Usage: reopen <id>');
      return 1;
    }
    final id = args[0];
    final data = await _requireData();
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

    if (!found) {
      stderr.writeln('Error: Item with ID "$id" not found.');
      return 1;
    }

    _recalculateMaxCompletionOrder(data);
    await store.save(data);
    stdout.writeln('✔ Reopened item $id');
    return 0;
  }

  Future<int> _handleRemove(List<String> args) async {
    if (args.isEmpty) {
      stderr.writeln('Usage: remove <id>');
      return 1;
    }
    final id = args[0];
    final data = await _requireData();

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

    if (!found) {
      stderr.writeln('Error: Item with ID "$id" not found.');
      return 1;
    }

    _recalculateMaxCompletionOrder(data);
    await store.save(data);
    stdout.writeln('✔ Removed item $id');
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
    final batchMap = jsonDecode(args[0]) as Map<String, dynamic>;
    final data = await _requireData();

    if (batchMap['complete'] is List) {
      for (final id in batchMap['complete'] as List) {
        final nextOrder = data.lastCompletionOrder + 1;
        final updated = _setItemStatus(
          data,
          id.toString(),
          TaskStatus.completed,
          nextOrder,
        );
        if (updated) {
          data.lastCompletionOrder = nextOrder;
        }
      }
    }

    if (batchMap['addSubQuest'] is Map) {
      final map = batchMap['addSubQuest'] as Map<String, dynamic>;
      final qId = map['quest'] as String? ?? '1';
      final quest = _findQuest(data, qId);
      if (quest != null) {
        final nextSubNumber =
            quest.subQuests
                .map((sq) => int.tryParse(sq.id.split('.').last) ?? 0)
                .fold(0, max) +
            1;
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

    if (batchMap['vcs'] is Map) {
      final map = batchMap['vcs'] as Map<String, dynamic>;
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

    await store.save(data);
    stdout.writeln('✔ Executed batch operations');
    return 0;
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
    final inputPath = results['input'] as String?;
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

  bool _setItemStatus(
    SidequestData data,
    String id,
    TaskStatus status,
    int order,
  ) {
    for (final q in data.quests) {
      if (q.id == id) {
        q.status = QuestStatus.completed;
        return true;
      }
      for (final sq in q.subQuests) {
        if (sq.id == id) {
          sq.status = status;
          sq.completionOrder = order;
          return true;
        }
        for (final item in sq.items) {
          if (item.id == id) {
            item.status = status;
            item.completionOrder = order;
            return true;
          }
        }
      }
      for (final sq in q.sideQuests) {
        if (sq.id == id) {
          sq.status = SideQuestStatus.completed;
          sq.completionOrder = order;
          return true;
        }
      }
    }
    for (final sq in data.globalSideQuests) {
      if (sq.id == id) {
        sq.status = SideQuestStatus.completed;
        sq.completionOrder = order;
        return true;
      }
    }
    return false;
  }

  void _recalculateMaxCompletionOrder(SidequestData data) {
    int maxOrder = 0;
    for (final q in data.quests) {
      for (final sq in q.subQuests) {
        if (sq.completionOrder != null)
          maxOrder = max(maxOrder, sq.completionOrder!);
        for (final item in sq.items) {
          if (item.completionOrder != null)
            maxOrder = max(maxOrder, item.completionOrder!);
        }
      }
      for (final sq in q.sideQuests) {
        if (sq.completionOrder != null)
          maxOrder = max(maxOrder, sq.completionOrder!);
      }
    }
    for (final sq in data.globalSideQuests) {
      if (sq.completionOrder != null)
        maxOrder = max(maxOrder, sq.completionOrder!);
    }
    data.lastCompletionOrder = maxOrder;
  }

  void _printUsage() {
    stdout.writeln('sidequest CLI - Deterministic session map manager');
    stdout.writeln('Usage: sidequest <command> [args] [--dir=path]');
  }
}
