import 'dart:convert';
import 'enums.dart';
import 'vcs_state.dart';

class Watermark {
  final int stepIndex;
  final String timestamp;
  final String? messageId;

  const Watermark({
    required this.stepIndex,
    required this.timestamp,
    this.messageId,
  });

  Map<String, dynamic> toJson() => {
    'stepIndex': stepIndex,
    'timestamp': timestamp,
    if (messageId != null) 'messageId': messageId,
  };

  factory Watermark.fromJson(Map<String, dynamic> json) {
    return Watermark(
      stepIndex: json['stepIndex'] as int? ?? 0,
      timestamp:
          json['timestamp'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      messageId: json['messageId'] as String?,
    );
  }
}

class TaskItem {
  final String id;
  final TaskType type;
  final String title;
  TaskStatus status;
  int? completionOrder;
  String? note;

  TaskItem({
    required this.id,
    required this.type,
    required this.title,
    this.status = TaskStatus.pending,
    this.completionOrder,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'title': title,
    'status': status.toJson(),
    if (completionOrder != null) 'completionOrder': completionOrder,
    if (note != null) 'note': note,
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] as String,
      type: TaskType.fromJson(json['type'] as String? ?? 'step'),
      title: json['title'] as String,
      status: TaskStatus.fromJson(json['status'] as String? ?? 'pending'),
      completionOrder: json['completionOrder'] as int?,
      note: json['note'] as String?,
    );
  }
}

class SubQuest {
  final String id;
  final String title;
  TaskStatus status;
  int? completionOrder;
  List<TaskItem> items;

  SubQuest({
    required this.id,
    required this.title,
    this.status = TaskStatus.inProgress,
    this.completionOrder,
    List<TaskItem>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.toJson(),
    if (completionOrder != null) 'completionOrder': completionOrder,
    if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
  };

  factory SubQuest.fromJson(Map<String, dynamic> json) {
    return SubQuest(
      id: json['id'] as String,
      title: json['title'] as String,
      status: TaskStatus.fromJson(json['status'] as String? ?? 'in_progress'),
      completionOrder: json['completionOrder'] as int?,
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SideQuest {
  final String id;
  final String title;
  SideQuestStatus status;
  VcsState? vcs;
  String? note;
  int? completionOrder;

  SideQuest({
    required this.id,
    required this.title,
    this.status = SideQuestStatus.active,
    this.vcs,
    this.note,
    this.completionOrder,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.toJson(),
    if (vcs != null) 'vcs': vcs!.toJson(),
    if (note != null) 'note': note,
    if (completionOrder != null) 'completionOrder': completionOrder,
  };

  factory SideQuest.fromJson(Map<String, dynamic> json) {
    return SideQuest(
      id: json['id'] as String,
      title: json['title'] as String,
      status: SideQuestStatus.fromJson(json['status'] as String? ?? 'active'),
      vcs: json['vcs'] != null
          ? VcsState.fromJson(json['vcs'] as Map<String, dynamic>)
          : null,
      note: json['note'] as String?,
      completionOrder: json['completionOrder'] as int?,
    );
  }
}

class MainQuest {
  final String id;
  final String title;
  QuestStatus status;
  String? statusNote;
  VcsState? vcs;
  List<SubQuest> subQuests;
  List<SideQuest> sideQuests;

  MainQuest({
    required this.id,
    required this.title,
    this.status = QuestStatus.active,
    this.statusNote,
    this.vcs,
    List<SubQuest>? subQuests,
    List<SideQuest>? sideQuests,
  }) : subQuests = subQuests ?? [],
       sideQuests = sideQuests ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.toJson(),
    if (statusNote != null) 'statusNote': statusNote,
    if (vcs != null) 'vcs': vcs!.toJson(),
    if (subQuests.isNotEmpty)
      'subQuests': subQuests.map((e) => e.toJson()).toList(),
    if (sideQuests.isNotEmpty)
      'sideQuests': sideQuests.map((e) => e.toJson()).toList(),
  };

  factory MainQuest.fromJson(Map<String, dynamic> json) {
    return MainQuest(
      id: json['id'] as String,
      title: json['title'] as String,
      status: QuestStatus.fromJson(json['status'] as String? ?? 'active'),
      statusNote: json['statusNote'] as String?,
      vcs: json['vcs'] != null
          ? VcsState.fromJson(json['vcs'] as Map<String, dynamic>)
          : null,
      subQuests:
          (json['subQuests'] as List<dynamic>?)
              ?.map((e) => SubQuest.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sideQuests:
          (json['sideQuests'] as List<dynamic>?)
              ?.map((e) => SideQuest.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SidequestData {
  final int version;
  Watermark? watermark;
  int lastCompletionOrder;
  List<SideQuest> globalSideQuests;
  List<MainQuest> quests;

  SidequestData({
    this.version = 1,
    this.watermark,
    this.lastCompletionOrder = 0,
    List<SideQuest>? globalSideQuests,
    List<MainQuest>? quests,
  }) : globalSideQuests = globalSideQuests ?? [],
       quests = quests ?? [];

  factory SidequestData.initial({required String firstQuestTitle}) {
    return SidequestData(
      version: 1,
      watermark: Watermark(
        stepIndex: 0,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
      lastCompletionOrder: 0,
      quests: [
        MainQuest(
          id: '1',
          title: firstQuestTitle,
          status: QuestStatus.active,
          vcs: const VcsState(stage: VcsStage.dirty),
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    if (watermark != null) 'watermark': watermark!.toJson(),
    'lastCompletionOrder': lastCompletionOrder,
    if (globalSideQuests.isNotEmpty)
      'globalSideQuests': globalSideQuests.map((e) => e.toJson()).toList(),
    'quests': quests.map((e) => e.toJson()).toList(),
  };

  factory SidequestData.fromJson(Map<String, dynamic> json) {
    return SidequestData(
      version: json['version'] as int? ?? 1,
      watermark: json['watermark'] != null
          ? Watermark.fromJson(json['watermark'] as Map<String, dynamic>)
          : null,
      lastCompletionOrder: json['lastCompletionOrder'] as int? ?? 0,
      globalSideQuests:
          (json['globalSideQuests'] as List<dynamic>?)
              ?.map((e) => SideQuest.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      quests:
          (json['quests'] as List<dynamic>?)
              ?.map((e) => MainQuest.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String toJsonString({bool pretty = true}) {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(toJson())
        : jsonEncode(toJson());
  }
}
