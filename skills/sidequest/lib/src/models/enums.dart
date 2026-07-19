enum QuestStatus {
  active,
  completed,
  paused;

  String toJson() => name;

  static QuestStatus fromJson(String value) => QuestStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => QuestStatus.active,
  );
}

enum TaskStatus {
  pending,
  inProgress,
  completed,
  parked;

  String toJson() {
    switch (this) {
      case TaskStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }

  static TaskStatus fromJson(String value) {
    if (value == 'in_progress') return TaskStatus.inProgress;
    return TaskStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskStatus.pending,
    );
  }
}

enum SideQuestStatus {
  active,
  parked,
  completed;

  String toJson() => name;

  static SideQuestStatus fromJson(String value) => SideQuestStatus.values
      .firstWhere((e) => e.name == value, orElse: () => SideQuestStatus.active);
}

enum VcsStage {
  dirty('📝', 'Dirty', isCaution: true),
  localCommit('📦', 'Local Commit', isCaution: true),
  uploaded('🚀', 'Uploaded'),
  merged('🎉', 'Merged / Submitted'),
  clean('🧹', 'Clean');

  const VcsStage(this.emoji, this.label, {this.isCaution = false});

  final String emoji;
  final String label;
  final bool isCaution;

  String get badge => '`$emoji $label`';

  String toJson() {
    switch (this) {
      case VcsStage.localCommit:
        return 'local_commit';
      default:
        return name;
    }
  }

  static VcsStage fromJson(String value) {
    if (value == 'local_commit') return VcsStage.localCommit;
    return VcsStage.values.firstWhere(
      (e) => e.name == value,
      orElse: () => VcsStage.clean,
    );
  }
}

enum TaskType {
  step,
  blocker;

  String toJson() => name;

  static TaskType fromJson(String value) => TaskType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => TaskType.step,
  );
}
