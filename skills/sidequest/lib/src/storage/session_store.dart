import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../emitter/markdown_emitter.dart';
import '../models/sidequest_data.dart';

class SessionStore {
  final String directory;

  SessionStore({
    String? directory,
    Map<String, String>? environment,
    String? currentDirectory,
  }) : directory = resolveDirectory(
         directory,
         environment: environment,
         currentDirectory: currentDirectory,
       );

  static String resolveDirectory(
    String? explicit, {
    Map<String, String>? environment,
    String? currentDirectory,
  }) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final env = environment ?? Platform.environment;
    final cwd = currentDirectory ?? Directory.current.path;

    final directEnvVars = [
      'JETSKI_ARTIFACT_DIR',
      'CLAUDE_ARTIFACT_DIR',
      'GEMINI_ARTIFACT_DIR',
      'SIDEQUEST_DIR',
    ];
    for (final key in directEnvVars) {
      final val = env[key];
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }

    final convId = env['ANTIGRAVITY_CONVERSATION_ID'];
    if (convId != null && convId.trim().isNotEmpty) {
      final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
      if (home.isNotEmpty) {
        return p.join(home, '.gemini', 'jetski', 'brain', convId.trim());
      }
    }

    final dotSidequest = p.join(cwd, '.sidequest');
    if (Directory(dotSidequest).existsSync() ||
        File(p.join(dotSidequest, 'sidequest.json')).existsSync()) {
      return dotSidequest;
    }

    if (File(p.join(cwd, 'sidequest.json')).existsSync()) {
      return cwd;
    }

    return cwd;
  }

  File get jsonFile => File(p.join(directory, 'sidequest.json'));
  File get mdFile => File(p.join(directory, 'sidequest.md'));

  Future<SidequestData?> load() async {
    final file = jsonFile;
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    return SidequestData.fromJson(jsonMap);
  }

  Future<void> save(SidequestData data) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = jsonFile;
    final tmpFile = File(p.join(directory, 'sidequest.json.tmp'));
    final bakFile = File(p.join(directory, 'sidequest.json.bak'));

    final jsonContent = data.toJsonString(pretty: true);

    // Write temp file first
    await tmpFile.writeAsString(jsonContent, flush: true);

    // Backup existing if present
    if (await file.exists()) {
      await file.copy(bakFile.path);
    }

    // Atomic rename (on Windows, delete target first as rename does not overwrite)
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);

    // Emit Markdown
    final markdown = MarkdownEmitter.emit(data);
    await mdFile.writeAsString(markdown, flush: true);
  }
}
