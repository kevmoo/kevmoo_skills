import '../models/enums.dart';
import '../models/sidequest_data.dart';
import '../models/vcs_state.dart';

class MarkdownEmitter {
  static String emit(SidequestData data) {
    final buffer = StringBuffer();
    buffer.writeln('# 🧭 Conversation Map & Sidequests\n');

    _renderCautionHeader(buffer, data);

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

  static void _renderCautionHeader(StringBuffer buffer, SidequestData data) {
    final dirtyLines = <String>[
      for (final sq in data.globalSideQuests)
        ?_dirtySideQuestLine(sq, isGlobal: true),
      for (final quest in data.quests) ..._dirtyQuestLines(quest),
    ];

    if (dirtyLines.isEmpty) return;
    buffer.writeln('> [!CAUTION]');
    buffer.writeln('> **Uncommitted & Unpushed Changes:**');
    for (final line in dirtyLines) {
      buffer.writeln('> * $line');
    }
    buffer.writeln();
  }

  static Iterable<String> _dirtyQuestLines(MainQuest quest) sync* {
    if (quest.status == QuestStatus.completed) return;
    final vcs = quest.vcs;
    if (vcs != null && _isVcsDirty(vcs)) {
      yield _formatDirtyLine('Main Quest ${quest.id}', vcs);
    }
    for (final sq in quest.sideQuests) {
      final line = _dirtySideQuestLine(sq, isGlobal: false);
      if (line != null) yield line;
    }
  }

  static String? _dirtySideQuestLine(SideQuest sq, {required bool isGlobal}) {
    if (sq.status == SideQuestStatus.completed) return null;
    final vcs = sq.vcs;
    if (vcs == null || !_isVcsDirty(vcs)) return null;
    final scope = isGlobal ? 'Global Side-Quest' : 'Side-Quest';
    final statusLabel = switch ((sq.status, isGlobal)) {
      (SideQuestStatus.active, true) => scope,
      (SideQuestStatus.active, false) => 'Active $scope',
      (SideQuestStatus.parked, _) => 'Parked $scope',
      (SideQuestStatus.completed, _) => 'Completed $scope',
    };
    return _formatDirtyLine('$statusLabel ${sq.id}', vcs);
  }

  static bool _isVcsDirty(VcsState vcs) => vcs.stage.isCaution;

  static String _formatDirtyLine(String label, VcsState vcs) {
    final branch = vcs.branch?.trim();
    final hasBranch = branch != null && branch.isNotEmpty;
    final branchPart = hasBranch ? ' (`$branch`)' : '';
    final prefix = '**$label$branchPart:**';
    if (vcs.modifiedFiles.isNotEmpty) {
      const maxFiles = 5;
      final truncated = vcs.modifiedFiles.take(maxFiles);
      final files = truncated.map((f) => '`$f`').join(', ');
      final extra = vcs.modifiedFiles.length > maxFiles
          ? ' (+${vcs.modifiedFiles.length - maxFiles} more)'
          : '';
      return '$prefix $files$extra';
    }
    final details = vcs.details?.trim();
    if (details != null && details.isNotEmpty) {
      return '$prefix $details';
    }
    if (vcs.stage == VcsStage.localCommit) {
      return '$prefix Unpushed local commit';
    }
    return '$prefix Uncommitted changes';
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
    final isBlocker = item.type == TaskType.blocker;
    final label = isBlocker ? 'Blocker' : 'Step';
    final icon = switch ((isBlocker, isDone)) {
      (true, true) => '💀',
      (true, false) => '👾',
      (false, _) => '👣',
    };

    if (isDone) {
      final doneLabel = isBlocker ? 'Resolved' : 'Done';
      buffer.writeln(
        '  * $checkbox $tag$icon ~~*$label ${item.id}:* ${item.title}~~ -> *$doneLabel*',
      );
    } else {
      buffer.writeln('  * $checkbox $icon *$label ${item.id}:* ${item.title}');
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
    final parts = <String>[vcs.stage.badge];
    final branch = vcs.branch?.trim();
    if (branch != null && branch.isNotEmpty) {
      parts.add('Branch: `$branch`');
    }
    if (vcs.modifiedFiles.isNotEmpty) {
      parts.add('Modified: `${vcs.modifiedFiles.join(', ')}`');
    }
    final details = vcs.details?.trim();
    if (details != null && details.isNotEmpty) {
      parts.add(details);
    }

    return '> **VCS State:** ${parts.join(' | ')}';
  }

  static String _formatVcsInline(VcsState vcs) {
    if (vcs.modifiedFiles.isNotEmpty) {
      final suffix = vcs.stage == VcsStage.localCommit
          ? ' (Local Commit)'
          : ' (Uncommitted)';
      return '`${vcs.modifiedFiles.join(', ')}`$suffix';
    }
    final details = vcs.details?.trim();
    if (details != null && details.isNotEmpty) {
      return details;
    }
    return vcs.stage.badge;
  }
}
