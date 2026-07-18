import 'enums.dart';

class VcsState {
  final VcsStage stage;
  final String? branch;
  final List<String> modifiedFiles;
  final String? details;
  final String? revision;

  const VcsState({
    required this.stage,
    this.branch,
    this.modifiedFiles = const [],
    this.details,
    this.revision,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage.toJson(),
    if (branch != null) 'branch': branch,
    if (modifiedFiles.isNotEmpty) 'modifiedFiles': modifiedFiles,
    if (details != null) 'details': details,
    if (revision != null) 'revision': revision,
  };

  factory VcsState.fromJson(Map<String, dynamic> json) {
    return VcsState(
      stage: VcsStage.fromJson(json['stage'] as String? ?? 'clean'),
      branch: json['branch'] as String?,
      modifiedFiles:
          (json['modifiedFiles'] as List<dynamic>?)?.cast<String>() ?? const [],
      details: json['details'] as String?,
      revision: json['revision'] as String?,
    );
  }
}
