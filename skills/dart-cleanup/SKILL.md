---
name: dart-cleanup
description: >-
  Orchestrates specialized Dart refactoring, code quality, testing, and modern
  language features on demand. Use when cleaning up, modernizing, refactoring,
  or optimizing Dart code. Don't use for non-Dart projects or general codebase
  search.
author: kevmoo
target_environment: personal
compatibility: "Requires local checkouts in ~/github/kevmoo and ~/github/skills"
---

# 🎯 Dart Cleanup & Refactoring Router

> [!NOTE] **Personal Environment Router**: This skill is optimized for
> `@kevmoo`'s local development environment and assumes specialized skills are
> checked out under `~/github/kevmoo/` and `~/github/skills/`. Other users
> should clone the required repositories or adapt the catalog paths in
> [Skill Catalog](#-skill-catalog) to match their local layout.

Orchestrates specialized Dart workflows from local GitHub checkouts without
pre-loading heavy individual skills into static prompt memory.

---

## 🛠️ Operating Protocol

### 1. Intent Evaluation & Confidence Matching (Strict Single-Skill Target)

When invoked with text (e.g. `/dart-cleanup convert expect matchers to checks`),
evaluate the input against the [Skill Catalog](#-skill-catalog) using this
3-tier confidence decision tree:

- **Tier 1: Unambiguous Clear Match (High Confidence / 90%+ sure)**
  - Exactly 1 skill in the catalog clearly maps to the requested transformation.
  - _Action_:
    1. Check for the target `SKILL.md` at its candidate path in `~/github/`.
    2. If missing, output the
       [Missing Checkout Safety Net](#missing-checkout-safety-net).
    3. If present, call `view_file` on the target `SKILL.md`, hydrate its
       untruncated instructions into active context, and execute the refactoring
       immediately.
- **Tier 2: Uncertain / Close Match (Medium Confidence)**
  - A skill seems close or relevant, but there is ambiguity.
  - _Action_: Stop and ask the user for confirmation before hydrating:
    > _"I think you might mean **`<skill-name>`**"_
    > _([SKILL.md](file:///path/to/SKILL.md)). Would you like me to load and_
    > _run this workflow?"_
- **Tier 3: No Clear Match or Bare Invocation (Low Confidence / Empty Input)**
  - No skill matches the prompt, or `/dart-cleanup` was invoked with no
    arguments.
  - _Action_: Output:
    > _"I couldn't find an unambiguous skill match for your request. Here is_
    > _the catalog of available specialized Dart skills:"_ Render the
    > categorized [Skill Catalog](#-skill-catalog) with clickable `file://`
    > links so the user can choose.

### 2. Missing Checkout Safety Net

If a target `SKILL.md` is selected but missing from the local filesystem,
output:

> ⚠️ **Missing local checkout**: Target skill `<skill-name>` was not found at
> `~/github/...`. Please ensure `https://github.com/<org>/<repo>` is cloned into
> `~/github/`.

---

## 📋 Skill Catalog & Path Priority

<!-- DART_CLEANUP_CATALOG_START -->

<!-- prettier-ignore-start -->

### Required Local Repositories

<!-- mdformat off(prevent table wrapping) -->
| Repository | Local Directory | Synced Commit |
| :--- | :--- | :--- |
| [`dart-lang/skills`](https://github.com/dart-lang/skills) | `~/github/skills` | [`26b2dcc`](https://github.com/dart-lang/skills/commit/26b2dcc5654cbbc3b2ec56ea94719469bc8bae9e) |
| [`kevmoo/analytica.dart`](https://github.com/kevmoo/analytica.dart) | `~/github/kevmoo/analytica.dart` | [`0114d16`](https://github.com/kevmoo/analytica.dart/commit/0114d16b76df87f7bea27f9b11888518fb787357) |
| [`kevmoo/dash_skills`](https://github.com/kevmoo/dash_skills) | `~/github/kevmoo/dash_skills` | [`6c39005`](https://github.com/kevmoo/dash_skills/commit/6c3900555225a113d4dbd89b4cda4b41c72130ae) |
<!-- mdformat on -->

### A. Refactoring & Code Quality
* **`dart-build-cli-app`**: CLI entrypoint structure, argument parsing
  (`package:args`), cross-platform scripts, exit codes, and compilation.
  * *Path*: `~/github/skills/skills/dart-build-cli-app/SKILL.md`
* **`dart-cognitive-complexity`**: Reduces cognitive complexity, nested loops,
  and deep conditionals via pattern matching & guard clauses. Includes a gated
  Tier 3 method-object reference for extreme cases.
  * *Path*: `~/github/kevmoo/analytica.dart/skills/dart-cognitive-complexity/SKILL.md`
* **`dart-dedupe`**: Detects, audits, and safely remediates structural code
  duplication across Dart and Flutter repositories using the standalone Dedupe
  engine (`pkg:dedupe`) and empirical test gating.
  * *Path*: `~/github/kevmoo/analytica.dart/skills/dart-dedupe/SKILL.md`
* **`dart-fix-runtime-errors`**: Resolves runtime errors, inspects active stack
  traces via `get_runtime_errors` and LSP, and verifies with hot reload.
  * *Path*: `~/github/skills/skills/dart-fix-runtime-errors/SKILL.md`
* **`dart-run-static-analysis`**: Executes `dart analyze` to catch issues and
  `dart fix --apply` to automatically resolve mechanical lint warnings.
  * *Path*: `~/github/skills/skills/dart-run-static-analysis/SKILL.md`
* **`dart-undead`**: Audits, triages, and safely remediates unreachable and dead
  declarations in Dart and Flutter codebases using deterministic reachability
  analysis (`pkg:undead`).
  * *Path*: `~/github/kevmoo/analytica.dart/skills/dart-undead/SKILL.md`
* **`dart-use-path-package`**: Cross-platform file and directory path
  manipulation, segment splitting, and extension extraction using `package:path`
  and `package:file`.
  * *Path*: `~/github/skills/skills/dart-use-path-package/SKILL.md`
* **`profile-dart-code`**: Profiles Dart CLI applications using the VM Service
  protocol to capture CPU samples and pinpoint performance bottlenecks.
  * *Path*: `~/github/kevmoo/dash_skills/skills/profile-dart-code/SKILL.md`

### B. Language Modernization & Syntax
* **`dart-best-practices`**: Effective Dart guidelines, class design, null
  safety, and idiomatic style conventions.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-best-practices/SKILL.md`
* **`dart-long-lines`**: Formats and refactors code to adhere to the 80-column
  line limit (`lines_longer_than_80_chars`).
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-long-lines/SKILL.md`
* **`dart-modern-features`**: Records, pattern matching, switch expressions,
  extension types, and class modifiers (`interface`, `base`, `sealed`, `final`).
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-modern-features/SKILL.md`
* **`dart-multiline-strings`**: Converts consecutive print statements and string
  concatenations into clean triple-quoted multiline strings.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-multiline-strings/SKILL.md`
* **`dart-use-pattern-matching`**: Applies Dart 3 pattern matching, switch
  expressions, and destructuring to validate schemas and simplify control flow.
  * *Path*: `~/github/skills/skills/dart-use-pattern-matching/SKILL.md`
* **`dart-use-primary-constructors`**: Adopts primary constructor syntax,
  empty-body semicolon syntax, in-body initializers, and concise forms.
  * *Path*: `~/github/skills/skills/dart-use-primary-constructors/SKILL.md`

### C. Testing & Assertions
* **`dart-add-unit-test`**: Writes and organizes unit tests for functions,
  methods, and classes using `package:test` with clean structure.
  * *Path*: `~/github/skills/skills/dart-add-unit-test/SKILL.md`
* **`dart-collect-coverage`**: Collects test coverage using `package:coverage`
  and generates LCOV reports.
  * *Path*: `~/github/skills/skills/dart-collect-coverage/SKILL.md`
* **`dart-generate-test-mocks`**: Defines and generates mock objects for
  external dependencies using `package:mockito` and `build_runner`.
  * *Path*: `~/github/skills/skills/dart-generate-test-mocks/SKILL.md`
* **`dart-matcher-best-practices`**: Best practices, custom matchers, and async
  matcher patterns for legacy `package:matcher` assertions.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-matcher-best-practices/SKILL.md`
* **`dart-migrate-to-checks-package`**: Migrates legacy `expect(a, equals(b))`
  matchers from `package:matcher` to fluent `package:checks` syntax.
  * *Path*: `~/github/skills/skills/dart-migrate-to-checks-package/SKILL.md`
* **`dart-test-coverage`**: Inspects, analyzes, and improves test coverage
  across a Dart package, locating missed lines.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-test-coverage/SKILL.md`
* **`dart-test-fundamentals`**: Core `package:test` practices, test grouping,
  `setUp`/`tearDown` lifecycles, and `dart_test.yaml` configuration.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-test-fundamentals/SKILL.md`

### D. Documentation, Packaging & Native Interop
* **`dart-doc-validation`**: Validates doc comments using `dart doc` to catch
  broken or unresolved references and macros.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-doc-validation/SKILL.md`
* **`dart-package-maintenance`**: Best practices for package maintenance,
  versioning, changelog curation, and publishing workflows.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-package-maintenance/SKILL.md`
* **`dart-resolve-package-conflicts`**: Resolves package dependency version
  conflicts when `pub get` fails due to incompatible constraints.
  * *Path*: `~/github/skills/skills/dart-resolve-package-conflicts/SKILL.md`
* **`dart-setup-ffi-assets`**: Compiles and packages C/C++ native assets using
  Dart's Native Assets hook system (`hook/build.dart` and `hook/link.dart`).
  * *Path*: `~/github/skills/skills/dart-setup-ffi-assets/SKILL.md`
* **`dart-use-doc-examples`**: Injects external code examples into Dartdoc via
  `{@example}` directives and filters with `#region` tags.
  * *Path*: `~/github/skills/skills/dart-use-doc-examples/SKILL.md`
* **`dart-use-ffigen`**: Automatically generates C/Objective-C/Swift FFI
  bindings using `package:ffigen` instead of hand-crafting `dart:ffi`.
  * *Path*: `~/github/skills/skills/dart-use-ffigen/SKILL.md`
* **`dart-write-documentation`**: Effective Dart `///` doc comment conventions,
  API documentation rules, and reference linking.
  * *Path*: `~/github/skills/skills/dart-write-documentation/SKILL.md`

<!-- prettier-ignore-end -->

<!-- DART_CLEANUP_CATALOG_END -->
