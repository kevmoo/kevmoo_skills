import 'package:meta/meta.dart';
import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';
import 'dart:io';
import 'dart:math';

@internal
enum ItemCompleteResult {
  completedWithOrder,
  completedNoOrder,
  alreadyCompleted,
  notFound,
}

@internal
void printVcsStatus(VcsState vcs) {
  final branch = vcs.branch ?? 'N/A';
  final files = vcs.modifiedFiles.isEmpty
      ? 'none'
      : vcs.modifiedFiles.join(', ');
  stdout.writeln(
    '   VCS: ${vcs.stage.badge} | Branch: $branch | Modified: $files',
  );
}

@internal
void printBlockers(List<SubQuest> subQuests) {
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

@internal
void printSubQuests(List<SubQuest> subQuests, int lastCompletionOrder) {
  if (subQuests.isEmpty) return;

  stdout.writeln('   Sub-Quests & Steps:');
  for (final sq in subQuests) {
    final doneStr = switch (sq.status) {
      TaskStatus.completed => '✔ (Done)',
      TaskStatus.inProgress => '⏳ (In Progress)',
      TaskStatus.pending => '🗓️ (Pending)',
      TaskStatus.parked => '🎒 (Parked)',
    };
    stdout.writeln('     🛡️  Sub-Quest ${sq.id}: "${sq.title}" $doneStr');
    for (final item in sq.items) {
      _printTaskItem(item, lastCompletionOrder);
    }
  }
}

void _printTaskItem(TaskItem item, int lastCompletionOrder) {
  final itemDone = switch (item.status) {
    TaskStatus.completed => '✔',
    TaskStatus.inProgress => '▶',
    TaskStatus.parked => '🎒',
    TaskStatus.pending => ' ',
  };
  final icon = item.type == TaskType.blocker ? '👾' : '👣';
  final order = item.completionOrder != null
      ? (item.completionOrder == lastCompletionOrder
            ? '[#${item.completionOrder} ⭐]'
            : '[#${item.completionOrder}]')
      : '';
  final orderStr = order.isNotEmpty ? '$order ' : '';
  final statusSuffix = switch (item.status) {
    TaskStatus.inProgress => ' (IN PROGRESS)',
    TaskStatus.parked => ' (PARKED)',
    TaskStatus.pending || TaskStatus.completed => '',
  };
  stdout.writeln(
    '        [$itemDone] $orderStr$icon ${item.id}: "${item.title}"$statusSuffix',
  );
}

@internal
void printSideQuests(List<SideQuest> sideQuests) {
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

@internal
List<String> extractIds(List<String> args) => args
    .expand((arg) => arg.split(','))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

@internal
ItemCompleteResult completeSingleItem(
  SidequestData data,
  String id,
  int nextOrder,
) {
  for (final q in data.quests) {
    final qResult = _completeQuest(q, id, nextOrder);
    if (qResult != ItemCompleteResult.notFound) return qResult;
  }

  for (final sq in data.globalSideQuests) {
    final sqResult = _completeSideQuest(sq, id, nextOrder);
    if (sqResult != ItemCompleteResult.notFound) return sqResult;
  }

  return ItemCompleteResult.notFound;
}

ItemCompleteResult _completeQuest(MainQuest q, String id, int nextOrder) {
  if (q.id == id) {
    if (q.status == QuestStatus.completed) {
      return ItemCompleteResult.alreadyCompleted;
    }
    q.status = QuestStatus.completed;
    return ItemCompleteResult.completedNoOrder;
  }

  for (final sq in q.subQuests) {
    final sqResult = _completeSubQuest(sq, id, nextOrder);
    if (sqResult != ItemCompleteResult.notFound) return sqResult;
  }

  for (final sq in q.sideQuests) {
    final sqResult = _completeSideQuest(sq, id, nextOrder);
    if (sqResult != ItemCompleteResult.notFound) return sqResult;
  }

  return ItemCompleteResult.notFound;
}

ItemCompleteResult _completeSubQuest(SubQuest sq, String id, int nextOrder) {
  if (sq.id == id) {
    if (sq.status == TaskStatus.completed) {
      return ItemCompleteResult.alreadyCompleted;
    }
    sq.status = TaskStatus.completed;
    sq.completionOrder = nextOrder;
    return ItemCompleteResult.completedWithOrder;
  }

  for (final item in sq.items) {
    if (item.id == id) {
      if (item.status == TaskStatus.completed) {
        return ItemCompleteResult.alreadyCompleted;
      }
      item.status = TaskStatus.completed;
      item.completionOrder = nextOrder;
      return ItemCompleteResult.completedWithOrder;
    }
  }

  return ItemCompleteResult.notFound;
}

ItemCompleteResult _completeSideQuest(SideQuest sq, String id, int nextOrder) {
  if (sq.id != id) return ItemCompleteResult.notFound;
  if (sq.status == SideQuestStatus.completed) {
    return ItemCompleteResult.alreadyCompleted;
  }
  sq.status = SideQuestStatus.completed;
  sq.completionOrder = nextOrder;
  return ItemCompleteResult.completedWithOrder;
}

@internal
void syncParentOnChildStatusChange(
  SidequestData data,
  MainQuest quest,
  SubQuest sub, {
  required TaskStatus childStatus,
}) {
  if (childStatus == TaskStatus.inProgress) {
    if (quest.status == QuestStatus.completed) {
      quest.status = QuestStatus.active;
    }
    if (sub.status != TaskStatus.inProgress) {
      final hadOrder = sub.completionOrder != null;
      sub.status = TaskStatus.inProgress;
      sub.completionOrder = null;
      if (hadOrder) recalculateMaxCompletionOrder(data);
    }
    return;
  }

  if (childStatus != TaskStatus.completed &&
      sub.status == TaskStatus.completed) {
    if (quest.status == QuestStatus.completed) {
      quest.status = QuestStatus.active;
    }
    sub.completionOrder = null;
    sub.status = sub.items.any((i) => i.status == TaskStatus.inProgress)
        ? TaskStatus.inProgress
        : TaskStatus.pending;
    recalculateMaxCompletionOrder(data);
  }
}

@internal
bool startSingleItem(SidequestData data, String id) {
  for (final q in data.quests) {
    if (_startQuest(data, q, id)) return true;
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

bool _startQuest(SidequestData data, MainQuest q, String id) {
  if (q.id == id) {
    q.status = QuestStatus.active;
    return true;
  }
  for (final sq in q.subQuests) {
    if (_startSubQuest(data, q, sq, id)) return true;
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

bool _startSubQuest(SidequestData data, MainQuest q, SubQuest sq, String id) {
  if (sq.id == id) {
    if (q.status == QuestStatus.completed) {
      q.status = QuestStatus.active;
    }
    sq.status = TaskStatus.inProgress;
    sq.completionOrder = null;
    return true;
  }
  for (final item in sq.items) {
    if (item.id == id) {
      item.status = TaskStatus.inProgress;
      item.completionOrder = null;
      syncParentOnChildStatusChange(
        data,
        q,
        sq,
        childStatus: TaskStatus.inProgress,
      );
      return true;
    }
  }
  return false;
}

bool reopenSingleItem(SidequestData data, String id) {
  for (final q in data.quests) {
    if (_reopenQuest(data, q, id)) return true;
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

bool _reopenQuest(SidequestData data, MainQuest q, String id) {
  if (q.id == id) {
    q.status = QuestStatus.active;
    return true;
  }
  for (final sq in q.subQuests) {
    if (_reopenSubQuest(data, q, sq, id)) return true;
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

bool _reopenSubQuest(SidequestData data, MainQuest q, SubQuest sq, String id) {
  if (sq.id == id) {
    if (q.status == QuestStatus.completed) {
      q.status = QuestStatus.active;
    }
    sq.status = TaskStatus.pending;
    sq.completionOrder = null;
    for (final item in sq.items) {
      if (item.status == TaskStatus.inProgress) {
        item.status = TaskStatus.pending;
      }
    }
    return true;
  }
  for (final item in sq.items) {
    if (item.id == id) {
      item.status = TaskStatus.pending;
      item.completionOrder = null;
      syncParentOnChildStatusChange(
        data,
        q,
        sq,
        childStatus: TaskStatus.pending,
      );
      return true;
    }
  }
  return false;
}

bool removeSingleItem(SidequestData data, String id) {
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

@internal
(int applied, int total) executeBatchPayload(
  SidequestData data,
  Object? decoded,
) {
  if (decoded is List) {
    return (applyBatchList(data, decoded), decoded.length);
  }
  if (decoded is Map<String, dynamic>) {
    final total = _countBatchMapOperations(decoded);
    return (applyBatchMap(data, decoded), total);
  }
  throw FormatException(
    'Batch payload must be a JSON array or object, got ${decoded.runtimeType}',
  );
}

int _countBatchMapOperations(Map<String, dynamic> decoded) {
  if (decoded['operations'] case final List<dynamic> ops) {
    return ops.length;
  }
  final mapOps = [
    decoded['addSubQuest'],
    decoded['start'],
    decoded['complete'],
    decoded['vcs'],
  ].whereType<Object>().length;
  return max(mapOps, 1);
}

int applyBatchList(SidequestData data, List<dynamic> list) {
  int count = 0;
  for (final op in list) {
    if (op is Map<String, dynamic>) {
      _applyBatchOp(data, op);
      count++;
    } else {
      throw StateError('Invalid operation format: expected object.');
    }
  }
  return count;
}

int applyBatchMap(SidequestData data, Map<String, dynamic> map) {
  if (map['operations'] is List) {
    return applyBatchList(data, map['operations'] as List);
  }
  return _applyLegacyBatchMap(data, map);
}

void _applyCompletionResult(
  SidequestData data,
  String id,
  ItemCompleteResult result,
  int nextOrder,
) {
  if (result == ItemCompleteResult.completedWithOrder) {
    data.lastCompletionOrder = nextOrder;
  } else if (result == ItemCompleteResult.notFound) {
    throw StateError('Item "$id" not found for completion.');
  }
}

int _applyLegacyBatchMap(SidequestData data, Map<String, dynamic> map) {
  int count = 0;
  if (map['addSubQuest'] case final Map<String, dynamic> sqMap) {
    _applyBatchSubQuestAdd(data, sqMap, defaultTitle: 'New SubQuest');
    count++;
  }

  if (map['start'] case final List<dynamic> startIds) {
    for (final rawId in startIds) {
      final id = rawId.toString();
      if (!startSingleItem(data, id)) {
        throw StateError('Item "$id" not found for start.');
      }
      count++;
    }
    recalculateMaxCompletionOrder(data);
  }

  if (map['complete'] case final List<dynamic> completeIds) {
    for (final rawId in completeIds) {
      final id = rawId.toString();
      final nextOrder = data.lastCompletionOrder + 1;
      final result = completeSingleItem(data, id, nextOrder);
      _applyCompletionResult(data, id, result, nextOrder);
      count++;
    }
  }

  if (map['vcs'] case final Map<String, dynamic> vcsMap) {
    _applyBatchVcs(data, vcsMap);
    count++;
  }
  return count;
}

const _kType = 'type';
const _kOp = 'op';
const _kQuest = 'quest';
const _kQuestId = 'questId';
const _kQuestIdSnake = 'quest_id';
const _kSubquest = 'subquest';
const _kSubquestId = 'subquestId';
const _kSubquestIdSnake = 'subquest_id';
const _kTitle = 'title';
const _kDescription = 'description';
const _kStart = 'start';
const _kStatus = 'status';
const _kGlobal = 'global';
const _kParked = 'parked';
const _kNote = 'note';
const _kId = 'id';
const _kIds = 'ids';
const _kVcs = 'vcs';
const _kStage = 'stage';
const _kBranch = 'branch';
const _kFiles = 'files';
const _kDetails = 'details';

const _legacyAliasKeys = {_kDescription, _kQuestIdSnake, _kSubquestIdSnake};

@internal
enum BatchOp {
  questAdd('quest_add', {_kTitle, _kDescription, _kVcs}),
  subquestAdd('subquest_add', {
    _kQuest,
    _kQuestId,
    _kQuestIdSnake,
    _kTitle,
    _kDescription,
    _kStart,
    _kStatus,
  }),
  stepAdd('step_add', {
    _kSubquest,
    _kSubquestId,
    _kSubquestIdSnake,
    _kTitle,
    _kDescription,
    _kStart,
    _kStatus,
  }),
  blockerAdd('blocker_add', {
    _kSubquest,
    _kSubquestId,
    _kSubquestIdSnake,
    _kTitle,
    _kDescription,
    _kStart,
    _kStatus,
  }),
  sidequestAdd('sidequest_add', {
    _kQuest,
    _kQuestId,
    _kQuestIdSnake,
    _kTitle,
    _kDescription,
    _kGlobal,
    _kParked,
    _kNote,
  }),
  start('start', {_kId, _kIds}),
  complete('complete', {_kId, _kIds}),
  reopen('reopen', {_kId, _kIds}),
  vcs('vcs', {
    _kQuest,
    _kQuestId,
    _kQuestIdSnake,
    _kStage,
    _kBranch,
    _kFiles,
    _kDetails,
  });

  const BatchOp(this.typeName, this.allowedKeys);

  final String typeName;
  final Set<String> allowedKeys;

  Iterable<String> get documentedKeys =>
      allowedKeys.where((k) => !_legacyAliasKeys.contains(k));

  static BatchOp fromTypeName(String rawType) => BatchOp.values.firstWhere(
    (e) => e.typeName == rawType,
    orElse: () => throw StateError('Unknown operation type: "$rawType"'),
  );

  void validateKeys(Map<String, dynamic> op) {
    final unknown = op.keys
        .where((k) => k != _kType && k != _kOp && !allowedKeys.contains(k))
        .toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown key(s) ${unknown.map((k) => '"$k"').join(', ')} '
        'for "$typeName" (allowed: ${documentedKeys.join(', ')}).',
      );
    }
  }

  static String formatUsageFooter() {
    final buffer = StringBuffer('\nSupported operation types in JSON array:\n');
    for (final op in BatchOp.values) {
      final keys = op.documentedKeys.join(', ');
      buffer.writeln('  • ${op.typeName.padRight(13)} : keys: $keys');
    }
    return buffer.toString().trimRight();
  }
}

void _applyBatchOp(SidequestData data, Map<String, dynamic> op) {
  final type = (op[_kType]?.toString() ?? op[_kOp]?.toString() ?? '')
      .toLowerCase();
  final batchOp = BatchOp.fromTypeName(type);
  batchOp.validateKeys(op);

  final handler = _batchOpHandlers[batchOp]!;
  handler(data, op);
}

const _batchOpHandlers =
    <BatchOp, void Function(SidequestData, Map<String, dynamic>)>{
      BatchOp.questAdd: _applyBatchQuestAdd,
      BatchOp.start: _applyBatchStart,
      BatchOp.complete: _applyBatchComplete,
      BatchOp.reopen: _applyBatchReopen,
      BatchOp.subquestAdd: _applyBatchSubQuestAdd,
      BatchOp.stepAdd: _applyBatchStepAdd,
      BatchOp.blockerAdd: _applyBatchBlockerAdd,
      BatchOp.sidequestAdd: _applyBatchSideQuestAdd,
      BatchOp.vcs: _applyBatchVcs,
    };

String? _extractQuestId(Map<String, dynamic> op, {String? defaultId = '1'}) =>
    op[_kQuest]?.toString() ??
    op[_kQuestIdSnake]?.toString() ??
    op[_kQuestId]?.toString() ??
    defaultId;

MainQuest _requireQuest(SidequestData data, String qId) {
  final quest = findQuest(data, qId, silent: true);
  if (quest == null) {
    throw StateError('Main Quest "$qId" not found.');
  }
  return quest;
}

void _applyBatchQuestAdd(SidequestData data, Map<String, dynamic> op) {
  final title =
      op[_kTitle]?.toString() ??
      op[_kDescription]?.toString() ??
      'New Main Quest';
  final nextQuestNumber =
      data.quests.map((q) => int.tryParse(q.id) ?? 0).fold(0, max) + 1;
  data.quests.add(
    MainQuest(
      id: '$nextQuestNumber',
      title: title,
      status: QuestStatus.active,
      vcs: op[_kVcs] != null
          ? VcsState.fromJson(op[_kVcs] as Map<String, dynamic>)
          : null,
    ),
  );
}

List<String> _extractBatchIds(
  Map<String, dynamic> op, {
  required String action,
}) {
  final rawIds = op[_kIds] ?? op[_kId];
  final idList = rawIds is List
      ? rawIds.map((e) => e.toString().trim()).toList()
      : [rawIds?.toString().trim() ?? ''];
  final validIds = idList.where((s) => s.isNotEmpty).toList();
  if (validIds.isEmpty) {
    throw StateError('No IDs specified for $action operation.');
  }
  return validIds;
}

void _applyBatchStart(SidequestData data, Map<String, dynamic> op) {
  final validIds = _extractBatchIds(op, action: 'start');
  for (final id in validIds) {
    if (!startSingleItem(data, id)) {
      throw StateError('Item "$id" not found for start.');
    }
  }
  recalculateMaxCompletionOrder(data);
}

void _applyBatchReopen(SidequestData data, Map<String, dynamic> op) {
  final validIds = _extractBatchIds(op, action: 'reopen');
  for (final id in validIds) {
    if (!reopenSingleItem(data, id)) {
      throw StateError('Item "$id" not found for reopen.');
    }
  }
  recalculateMaxCompletionOrder(data);
}

void _applyBatchComplete(SidequestData data, Map<String, dynamic> op) {
  final validIds = _extractBatchIds(op, action: 'complete');
  for (final id in validIds) {
    final nextOrder = data.lastCompletionOrder + 1;
    final result = completeSingleItem(data, id, nextOrder);
    _applyCompletionResult(data, id, result, nextOrder);
  }
}

TaskStatus _resolveBatchTaskStatus(
  Map<String, dynamic> op, {
  required TaskStatus defaultStatus,
}) {
  if (op[_kStart] == true) {
    return TaskStatus.inProgress;
  }
  final rawStatus = op[_kStatus]?.toString();
  if (rawStatus != null && rawStatus.trim().isNotEmpty) {
    return TaskStatus.fromJson(rawStatus.trim());
  }
  return defaultStatus;
}

void _applyBatchSubQuestAdd(
  SidequestData data,
  Map<String, dynamic> op, {
  String defaultTitle = 'SubQuest',
}) {
  final qId = _extractQuestId(op)!;
  final title =
      op[_kTitle]?.toString() ?? op[_kDescription]?.toString() ?? defaultTitle;
  final quest = _requireQuest(data, qId);
  final nextSubNumber = nextSuffixNumber(quest.subQuests.map((sq) => sq.id));
  final subId = '$qId.$nextSubNumber';
  final status = _resolveBatchTaskStatus(op, defaultStatus: TaskStatus.pending);
  if (quest.status == QuestStatus.completed && status != TaskStatus.completed) {
    quest.status = QuestStatus.active;
  }
  quest.subQuests.add(SubQuest(id: subId, title: title, status: status));
}

void _applyBatchStepAdd(SidequestData data, Map<String, dynamic> op) {
  _applyBatchTaskItemAdd(
    data,
    op,
    type: TaskType.step,
    defaultTitle: 'Step',
    status: _resolveBatchTaskStatus(op, defaultStatus: TaskStatus.pending),
  );
}

void _applyBatchBlockerAdd(SidequestData data, Map<String, dynamic> op) {
  _applyBatchTaskItemAdd(
    data,
    op,
    type: TaskType.blocker,
    defaultTitle: 'Blocker',
    status: _resolveBatchTaskStatus(op, defaultStatus: TaskStatus.inProgress),
  );
}

void _applyBatchTaskItemAdd(
  SidequestData data,
  Map<String, dynamic> op, {
  required TaskType type,
  required String defaultTitle,
  required TaskStatus status,
}) {
  final subId =
      op[_kSubquestId]?.toString() ??
      op[_kSubquestIdSnake]?.toString() ??
      op[_kSubquest]?.toString() ??
      '1.1';
  final title =
      op[_kTitle]?.toString() ?? op[_kDescription]?.toString() ?? defaultTitle;
  final found = findQuestAndSubQuest(data, subId, silent: true);
  if (found == null) {
    throw StateError('Sub-Quest "$subId" not found.');
  }
  final (quest, sub) = found;
  final nextNumber = nextSuffixNumber(sub.items.map((i) => i.id));
  sub.items.add(
    TaskItem(
      id: '$subId.$nextNumber',
      type: type,
      title: title,
      status: status,
    ),
  );
  syncParentOnChildStatusChange(data, quest, sub, childStatus: status);
}

@internal
String addGlobalSideQuest(
  SidequestData data, {
  required String title,
  required SideQuestStatus status,
  String? note,
}) {
  final id = data.generateNextGlobalSideQuestId();
  data.globalSideQuests.add(
    SideQuest(id: id, title: title, status: status, note: note),
  );
  return id;
}

@internal
String addQuestSideQuest(
  SidequestData data,
  MainQuest quest, {
  required String title,
  required SideQuestStatus status,
  String? note,
}) {
  final id = data.generateNextSideQuestId(quest);
  quest.sideQuests.add(
    SideQuest(id: id, title: title, status: status, note: note),
  );
  return id;
}

void _applyBatchSideQuestAdd(SidequestData data, Map<String, dynamic> op) {
  final title =
      op[_kTitle]?.toString() ?? op[_kDescription]?.toString() ?? 'Side Quest';
  final qId = _extractQuestId(op, defaultId: null);
  final isGlobal = op[_kGlobal] == true || (qId == null && data.quests.isEmpty);
  final isParked = op[_kParked] == true;
  final status = isParked ? SideQuestStatus.parked : SideQuestStatus.active;
  final note = op[_kNote]?.toString();

  if (isGlobal || qId == null) {
    addGlobalSideQuest(data, title: title, status: status, note: note);
  } else {
    final quest = _requireQuest(data, qId);
    addQuestSideQuest(data, quest, title: title, status: status, note: note);
  }
}

void _applyBatchVcs(SidequestData data, Map<String, dynamic> op) {
  final qId = _extractQuestId(op)!;
  final quest = _requireQuest(data, qId);
  final files = (op[_kFiles] as List<dynamic>?)?.cast<String>() ?? const [];
  quest.vcs = VcsState(
    stage: VcsStage.fromJson(op[_kStage]?.toString() ?? 'dirty'),
    branch: op[_kBranch]?.toString(),
    modifiedFiles: files,
    details: op[_kDetails]?.toString(),
  );
}

MainQuest? findQuest(SidequestData data, String id, {bool silent = false}) {
  final q = data.quests.where((e) => e.id == id).firstOrNull;
  if (!silent && q == null)
    stderr.writeln('Error: Main Quest "$id" not found.');
  return q;
}

@internal
(MainQuest, SubQuest)? findQuestAndSubQuest(
  SidequestData data,
  String subId, {
  bool silent = false,
}) {
  for (final q in data.quests) {
    for (final sq in q.subQuests) {
      if (sq.id == subId) return (q, sq);
    }
  }
  if (!silent) stderr.writeln('Error: Sub-Quest "$subId" not found.');
  return null;
}

@internal
SubQuest? findSubQuest(
  SidequestData data,
  String subId, {
  bool silent = false,
}) => findQuestAndSubQuest(data, subId, silent: silent)?.$2;

@internal
int nextSuffixNumber(Iterable<String> ids) =>
    ids.map((id) => int.tryParse(id.split('.').last) ?? 0).fold(0, max) + 1;

@internal
void recalculateMaxCompletionOrder(SidequestData data) {
  int maxOrder = 0;
  void updateMax(int? order) {
    if (order != null) maxOrder = max(maxOrder, order);
  }

  for (final q in data.quests) {
    for (final sq in q.subQuests) {
      updateMax(sq.completionOrder);
      for (final item in sq.items) {
        updateMax(item.completionOrder);
      }
    }
    for (final sq in q.sideQuests) {
      updateMax(sq.completionOrder);
    }
  }
  for (final sq in data.globalSideQuests) {
    updateMax(sq.completionOrder);
  }
  data.lastCompletionOrder = maxOrder;
}
