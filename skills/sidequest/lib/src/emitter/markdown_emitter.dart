import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';

class MarkdownEmitter {
  static String emit(SidequestData data) {
    final buffer = StringBuffer();
    buffer.writeln('# 🧭 Conversation Map & Sidequests\n');

    // Render Global Side Quests if any
    if (data.globalSideQuests.isNotEmpty) {
      buffer.writeln('## 🌿 Global Side Quests');
      for (final sq in data.globalSideQuests) {
        _renderSideQuest(buffer, sq, data.lastCompletionOrder);
      }
      buffer.writeln('\n---');
    }

    for (var i = 0; i < data.quests.length; i++) {
      final quest = data.quests[i];
      _renderMainQuest(buffer, quest, data.lastCompletionOrder);
      if (i < data.quests.length - 1) {
        buffer.writeln('\n---');
      }
    }

    return buffer.toString().trimRight() + '\n';
  }

  static void _renderMainQuest(
    StringBuffer buffer,
    MainQuest quest,
    int lastCompletionOrder,
  ) {
    final statusHeader = switch (quest.status) {
      QuestStatus.completed => '🏆 [COMPLETED]',
      QuestStatus.active => '⚔️ [ACTIVE HEAD]',
      QuestStatus.paused => '⏸️ [PAUSED]',
    };

    buffer.writeln('## $statusHeader Main Quest ${quest.id}: ${quest.title}');

    if (quest.vcs != null) {
      buffer.writeln(_formatVcs(quest.vcs!));
    }

    if (quest.statusNote != null && quest.statusNote!.trim().isNotEmpty) {
      buffer.writeln('* **Status:** ${quest.statusNote}');
    }

    for (final sq in quest.subQuests) {
      _renderSubQuest(buffer, sq, lastCompletionOrder);
    }

    if (quest.sideQuests.isNotEmpty) {
      buffer.writeln(
        '\n### 🌿 Active & Parked Side Quests (For Main Quest ${quest.id})',
      );
      for (final sq in quest.sideQuests) {
        _renderSideQuest(buffer, sq, lastCompletionOrder);
      }
    }
  }

  static void _renderSubQuest(
    StringBuffer buffer,
    SubQuest sq,
    int lastCompletionOrder,
  ) {
    final isDone = sq.status == TaskStatus.completed;
    final checkbox = isDone ? '[x]' : '[ ]';
    final tag = _orderTag(sq.completionOrder, lastCompletionOrder);
    final inProgressTag = (!isDone && sq.status == TaskStatus.inProgress)
        ? ' *(IN PROGRESS)*'
        : '';
    final doneTag = isDone ? ' -> *Done*' : '';

    buffer.writeln(
      '* $checkbox $tag🛡️ **Sub-Quest ${sq.id}:** ${sq.title}$inProgressTag$doneTag',
    );

    for (final item in sq.items) {
      _renderTaskItem(buffer, item, lastCompletionOrder);
    }
  }

  static void _renderTaskItem(
    StringBuffer buffer,
    TaskItem item,
    int lastCompletionOrder,
  ) {
    final isDone = item.status == TaskStatus.completed;
    final checkbox = isDone ? '[x]' : '[ ]';
    final tag = _orderTag(item.completionOrder, lastCompletionOrder);

    if (item.type == TaskType.blocker) {
      if (isDone) {
        buffer.writeln(
          '  * $checkbox $tag💀 ~~*Blocker ${item.id}:* ${item.title}~~ -> *Resolved*',
        );
      } else {
        buffer.writeln('  * $checkbox 👾 *Blocker ${item.id}:* ${item.title}');
      }
    } else {
      // Step
      if (isDone) {
        buffer.writeln(
          '  * $checkbox $tag👣 ~~*Step ${item.id}:* ${item.title}~~ -> *Done*',
        );
      } else {
        buffer.writeln('  * $checkbox 👣 *Step ${item.id}:* ${item.title}');
      }
    }
  }

  static void _renderSideQuest(
    StringBuffer buffer,
    SideQuest sq,
    int lastCompletionOrder,
  ) {
    final isDone = sq.status == SideQuestStatus.completed;
    final checkbox = isDone ? '[x]' : '[ ]';
    final tag = _orderTag(sq.completionOrder, lastCompletionOrder);

    if (isDone) {
      buffer.writeln(
        '* $checkbox $tag**[Completed Side-Quest ${sq.id}]** ${sq.title} -> *Done*',
      );
    } else if (sq.status == SideQuestStatus.parked) {
      final noteStr = sq.note != null ? ' -> *${sq.note}*' : '';
      buffer.writeln(
        '* [ ] **🎒 [Parked Side-Quest ${sq.id} / Tracked for Later]** ${sq.title}$noteStr',
      );
    } else {
      buffer.writeln('* [ ] **[Active Side-Quest ${sq.id}]** ${sq.title}');
      if (sq.vcs != null) {
        buffer.writeln('  * 📝 *VCS:* ${_formatVcsInline(sq.vcs!)}');
      }
    }
  }

  static String _orderTag(int? order, int lastOrder) {
    if (order == null || order <= 0) return '';
    if (order == lastOrder) {
      return '[#$order ⭐] ';
    }
    return '[#$order] ';
  }

  static String _formatVcs(VcsState vcs) {
    final stageStr = switch (vcs.stage) {
      VcsStage.dirty => '`📝 Dirty`',
      VcsStage.localCommit => '`📦 Local Commit`',
      VcsStage.uploaded => '`🚀 Uploaded`',
      VcsStage.merged => '`🎉 Merged / Submitted`',
      VcsStage.clean => '`🧹 Clean`',
    };

    final parts = <String>[stageStr];
    if (vcs.branch != null) parts.add('Branch: `${vcs.branch}`');
    if (vcs.modifiedFiles.isNotEmpty) {
      parts.add('Modified: `${vcs.modifiedFiles.join(', ')}`');
    }
    if (vcs.details != null) parts.add(vcs.details!);

    return '> **VCS State:** ${parts.join(' | ')}';
  }

  static String _formatVcsInline(VcsState vcs) {
    if (vcs.modifiedFiles.isNotEmpty) {
      return '`${vcs.modifiedFiles.join(', ')}` (Uncommitted)';
    }
    if (vcs.details != null) return vcs.details!;
    return vcs.stage.toJson();
  }
}
