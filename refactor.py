import sys
import re

with open('tool/test/sync_status_test.dart', 'r') as f:
    text = f.read()

# Add import if missing
if "import 'test_utils.dart';" not in text:
    text = text.replace("import 'package:test/test.dart';", "import 'package:test/test.dart';\nimport 'test_utils.dart';")

pattern = re.compile(
    r"\s*await runCommand\('git', \['init'\], workingDirectory: tempDir\.path\);.*?"
    r"repo: 'testrepo',\n\s*\);",
    re.DOTALL
)

matches = pattern.finditer(text)
counter = 0

def replacement(match):
    global counter
    counter += 1
    content = match.group(0)
    
    if "firstCommitSha" in content and "secondCommitSha" in content:
        # Check if it has a reset call
        if "reset" in content and "--hard" in content:
            return """
        final setup = await setupTestGitRepo(tempDir, commits: 2);
        final firstCommitSha = setup.commitShas[0];
        final secondCommitSha = setup.commitShas[1];
        
        // Reset local repo back to first commit
        await runCommand('git', [
          'reset',
          '--hard',
          firstCommitSha,
        ], workingDirectory: tempDir.path);
        
        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = setup.context;"""
        else:
            return """
        final setup = await setupTestGitRepo(tempDir, commits: 2);
        final firstCommitSha = setup.commitShas[0];
        final secondCommitSha = setup.commitShas[1];

        final currentBranch = (await runCommand('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], workingDirectory: tempDir.path)).trim();

        final context = setup.context;"""
    else:
        if "final currentBranch = " in content and "final headSha =" not in content:
            return """
        final setup = await setupTestGitRepo(tempDir);
        final currentBranch = setup.branch;
        final context = setup.context;"""
        elif "final headSha =" in content:
            return """
        final setup = await setupTestGitRepo(tempDir);
        final headSha = setup.headSha;
        final currentBranch = setup.branch;
        final context = setup.context;"""
        else:
            return """
        final setup = await setupTestGitRepo(tempDir);
        final context = setup.context;"""

new_text = pattern.sub(replacement, text)

with open('tool/test/sync_status_test.dart', 'w') as f:
    f.write(new_text)

print(f"Replaced {counter} occurrences")
