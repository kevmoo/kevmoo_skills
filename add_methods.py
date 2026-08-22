with open('skills/sidequest/lib/src/models/sidequest_data.dart', 'r') as f:
    text = f.read()

text = text.replace("import 'dart:convert';", "import 'dart:convert';\nimport 'dart:math';")

method_code = """
  String generateNextGlobalSideQuestId() {
    final nextNumber = globalSideQuests
        .map((sq) => int.tryParse(sq.id.startsWith('G') ? sq.id.substring(1) : sq.id) ?? 0)
        .fold(0, max) + 1;
    return 'G$nextNumber';
  }

  String generateNextSideQuestId(MainQuest quest) {
    final nextNumber = quest.sideQuests
        .map((sq) => int.tryParse(sq.id.startsWith('S') ? sq.id.substring(1) : sq.id) ?? 0)
        .fold(0, max) + 1;
    return 'S$nextNumber';
  }
"""

text = text.replace("    return pretty\n        ? const JsonEncoder.withIndent('  ').convert(toJson())\n        : jsonEncode(toJson());\n  }\n}", 
"    return pretty\n        ? const JsonEncoder.withIndent('  ').convert(toJson())\n        : jsonEncode(toJson());\n  }\n" + method_code + "}")

with open('skills/sidequest/lib/src/models/sidequest_data.dart', 'w') as f:
    f.write(text)
