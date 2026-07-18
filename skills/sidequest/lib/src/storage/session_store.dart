import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../emitter/markdown_emitter.dart';
import '../models/sidequest_data.dart';

class SessionStore {
  final String directory;

  SessionStore({String? directory}) : directory = resolveDirectory(directory);

  static String resolveDirectory(String? explicit) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }
    final envVars = [
      'JETSKI_ARTIFACT_DIR',
      'GEMINI_ARTIFACT_DIR',
      'CLAUDE_ARTIFACT_DIR',
    ];
    for (final key in envVars) {
      final val = Platform.environment[key];
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return '.';
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
