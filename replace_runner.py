import sys
import re

with open('skills/sidequest/lib/src/cli/command_runner.dart', 'r') as f:
    text = f.read()

# Replace the first block
global_pattern = re.compile(
    r"\s*final nextGlobalNumber =\s*data\.globalSideQuests\s*\.map\(\s*\(sq\) =>\s*int\.tryParse\(\s*sq\.id\.startsWith\('G'\) \? sq\.id\.substring\(1\) : sq\.id,\s*\) \?\?\s*0,\s*\)\s*\.fold\(0, max\) \+\s*1;\s*final id = 'G\$nextGlobalNumber';",
    re.DOTALL
)

side_pattern = re.compile(
    r"\s*final nextSideNumber =\s*quest\.sideQuests\s*\.map\(\s*\(sq\) =>\s*int\.tryParse\(\s*sq\.id\.startsWith\('S'\) \? sq\.id\.substring\(1\) : sq\.id,\s*\) \?\?\s*0,\s*\)\s*\.fold\(0, max\) \+\s*1;\s*final id = 'S\$nextSideNumber';",
    re.DOTALL
)

text = global_pattern.sub("\n      final id = data.generateNextGlobalSideQuestId();", text)
text = side_pattern.sub("\n      final id = data.generateNextSideQuestId(quest);", text)

with open('skills/sidequest/lib/src/cli/command_runner.dart', 'w') as f:
    f.write(text)
