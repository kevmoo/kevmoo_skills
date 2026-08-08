---
name: dart-cleanup
description: >-
  Orchestrates specialized Dart refactoring, code quality, testing, and modern language features on demand. Use when cleaning up, modernizing, refactoring, or optimizing Dart code. Don't use for non-Dart projects or general codebase search.
---

# 🎯 Dart Cleanup & Refactoring Router

Orchestrates specialized Dart workflows from local GitHub checkouts without pre-loading heavy individual skills into static prompt memory.

---

## 🛠️ Operating Protocol

### 1. Intent Evaluation & Confidence Matching (Strict Single-Skill Target)

When invoked with text (e.g. `/dart-cleanup convert expect matchers to checks`), evaluate the input against the [Skill Catalog](#-skill-catalog) using this 3-tier confidence decision tree:

* **Tier 1: Unambiguous Clear Match (High Confidence / 90%+ sure)**
  * Exactly 1 skill in the catalog clearly maps to the requested transformation.
  * *Action*:
    1. Check for the target `SKILL.md` at its candidate path in `~/github/`.
    2. If missing, output the [Missing Checkout Safety Net](#missing-checkout-safety-net).
    3. If present, call `view_file` on the target `SKILL.md`, hydrate its untruncated instructions into active context, and execute the refactoring immediately.
* **Tier 2: Uncertain / Close Match (Medium Confidence)**
  * A skill seems close or relevant, but there is ambiguity.
  * *Action*: Stop and ask the user for confirmation before hydrating:
    > *"I think you might mean **`<skill-name>`** ([SKILL.md](file:///path/to/SKILL.md)). Would you like me to load and run this workflow?"*
* **Tier 3: No Clear Match or Bare Invocation (Low Confidence / Empty Input)**
  * No skill matches the prompt, or `/dart-cleanup` was invoked with no arguments.
  * *Action*: Output:
    > *"I couldn't find an unambiguous skill match for your request. Here is the catalog of available specialized Dart skills:"*
    Render the categorized [Skill Catalog](#-skill-catalog) with clickable `file://` links so the user can choose.

### 2. Missing Checkout Safety Net
If a target `SKILL.md` is selected but missing from the local filesystem, output:
> ⚠️ **Missing local checkout**: Target skill `<skill-name>` was not found at `~/github/...`. Please ensure `https://github.com/<org>/<repo>` is cloned into `~/github/`.

---

## 📋 Skill Catalog & Path Priority

### A. Refactoring & Code Quality
* **`dart-cognitive-complexity`**: Reduces cognitive complexity, nested loops, and deep conditionals via pattern matching & guard clauses.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/cognitive_complexity.dart/skills/dart-cognitive-complexity/SKILL.md)
* **`encapsulated-method-object`**: Refactors scope-heavy functions, bloated closures, and shared local state into encapsulated helper objects.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/kevmoo_skills/skills/encapsulated-method-object/SKILL.md)
* **`dart-build-cli-app`**: CLI entrypoint structure, argument parsing, cross-platform scripts, exit codes.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/.agents/skills/dart-build-cli-app/SKILL.md)

### B. Language Modernization & Formatting
* **`dart-best-practices`**: Effective Dart guidelines, class design, null safety, and general style.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-best-practices/SKILL.md)
* **`dart-modern-features`**: Records, pattern matching, switch expressions, extension types, class modifiers.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-modern-features/SKILL.md)
* **`dart-multiline-strings`**: Converts consecutive print statements & string concatenations into triple-quoted strings.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-multiline-strings/SKILL.md)
* **`dart-long-lines`**: Formats code to adhere to the 80-column line limit (`lines_longer_than_80_chars`).
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-long-lines/SKILL.md)

### C. Testing & Assertions
* **`dart-migrate-to-checks-package`**: Converts legacy `expect(a, equals(b))` matchers to modern `package:checks` syntax (`check(a).equals(b)`).
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/.agents/skills/dart-migrate-to-checks-package/SKILL.md)
* **`dart-use-pattern-matching`**: Refactors complex conditionals and destructuring to idiomatic Dart 3 pattern matching.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/.agents/skills/dart-use-pattern-matching/SKILL.md)
* **`dart-test-fundamentals`**: Core `package:test` practices, grouping, `setUp`/`tearDown` lifecycles, and `dart_test.yaml`.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-test-fundamentals/SKILL.md)
* **`dart-matcher-best-practices`**: Best practices for legacy `package:matcher` assertions.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/github/kevmoo/dash_skills/skills/dart-matcher-best-practices/SKILL.md)
* **`dart-collect-coverage`**: Collecting coverage using `package:coverage` and creating LCOV reports.
  * *Path*: [SKILL.md](file:///usr/local/google/home/kevmoo/.agents/skills/dart-collect-coverage/SKILL.md)

