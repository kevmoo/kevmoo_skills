---
name: dart-toolkit
description: Orchestrates specialized Dart refactoring, code quality, testing, and modern language features on demand. Use when cleaning up, modernizing, refactoring, or optimizing Dart code.
---

# 🎯 Dart Toolkit & Refactoring Router

Orchestrates specialized Dart workflows from local GitHub checkouts without pre-loading heavy individual skills into static prompt memory.

---

## 🛠️ Operating Protocol

### 1. Invocation with Arguments (`/dart-toolkit <args...>` or prompt context)
When invoked with specific text (e.g. `convert expect matchers to checks`, `reduce cognitive complexity`, `convert prints to multiline strings`):

1. **Evaluate Intent**: Match the requested transformation against the [Skill Catalog](#-skill-catalog) below.
2. **Locate Target Skill**: Check for the target `SKILL.md` at its candidate local path.
3. **Missing Checkout Safety Net**: If the file does not exist at `~/github/`, stop and output:
   > ⚠️ **Missing local checkout**: Target skill `<skill-name>` was not found at `~/github/...`. Please ensure `https://github.com/<org>/<repo>` is cloned into `~/github/`.
4. **Hydration & Execution**: If present, call `view_file` on the target `SKILL.md`, hydrate its untruncated instructions into active context, and execute the refactoring.

### 2. Bare Invocation (`/dart-toolkit`)
When invoked with no arguments, display the categorized menu below so the user can choose or inspect individual skills.

---

## 📋 Skill Catalog & Path Priority

### A. Refactoring & Code Quality
* **`dart-cognitive-complexity`**: Reduces cognitive complexity, nested loops, and deep conditionals via pattern matching & guard clauses.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/cognitive_complexity.dart/skills/dart-cognitive-complexity/SKILL.md`
  * *Fallback*: `file:///usr/local/google/home/kevmoo/.agents/skills/dart-cognitive-complexity/SKILL.md`
* **`encapsulated-method-object`**: Refactors scope-heavy functions, bloated closures, and shared local state into encapsulated helper objects.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/kevmoo_skills/skills/encapsulated-method-object/SKILL.md`
* **`dart-build-cli-app`**: CLI entrypoint structure, argument parsing, cross-platform scripts, exit codes.
  * *Path*: `file:///usr/local/google/home/kevmoo/.agents/skills/dart-build-cli-app/SKILL.md`

### B. Language Modernization & Formatting
* **`dart-best-practices`**: Effective Dart guidelines, class design, null safety, and general style.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-best-practices/SKILL.md`
* **`dart-modern-features`**: Records, pattern matching, switch expressions, extension types, class modifiers.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-modern-features/SKILL.md`
* **`dart-multiline-strings`**: Converts consecutive print statements & string concatenations into triple-quoted strings.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-multiline-strings/SKILL.md`
* **`dart-long-lines`**: Formats code to adhere to the 80-column line limit (`lines_longer_than_80_chars`).
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-long-lines/SKILL.md`

### C. Testing & Assertions
* **`dart-migrate-to-checks-package`**: Converts legacy `expect(a, equals(b))` matchers to modern `package:checks` syntax (`check(a).equals(b)`).
  * *Path*: `file:///usr/local/google/home/kevmoo/.agents/skills/dart-migrate-to-checks-package/SKILL.md`
* **`dart-use-pattern-matching`**: Refactors complex conditionals and destructuring to idiomatic Dart 3 pattern matching.
  * *Path*: `file:///usr/local/google/home/kevmoo/.agents/skills/dart-use-pattern-matching/SKILL.md`
* **`dart-test-fundamentals`**: Core `package:test` practices, grouping, `setUp`/`tearDown` lifecycles, and `dart_test.yaml`.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-test-fundamentals/SKILL.md`
* **`dart-matcher-best-practices`**: Best practices for legacy `package:matcher` assertions.
  * *Path*: `file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-matcher-best-practices/SKILL.md`
* **`dart-collect-coverage`**: Collecting coverage using `package:coverage` and creating LCOV reports.
  * *Path*: `file:///usr/local/google/home/kevmoo/.agents/skills/dart-collect-coverage/SKILL.md`
