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

> [!NOTE]
>
> **Personal Environment Router**: This skill is optimized for `@kevmoo`'s local
> development environment and assumes specialized skills are checked out under
> `~/github/kevmoo/` and `~/github/skills/`. Other users should clone the
> required repositories or adapt the catalog paths in
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
  - _Action_: Verify the target `SKILL.md` exists in `~/github/` (or output the
    [Missing Checkout Safety Net](#2-missing-checkout-safety-net)), call
    `view_file` to hydrate its instructions, and execute the refactoring.
- **Tier 2: Uncertain / Close Match (Medium Confidence)**
  - A skill seems close or relevant, but there is ambiguity.
  - _Action_: Stop and ask for confirmation before hydrating: _"I think you
    might mean **`<skill-name>`** ([SKILL.md](file:///path/to/SKILL.md)). Would
    you like me to load and run this workflow?"_
- **Tier 3: No Clear Match or Bare Invocation (Low Confidence / Empty Input)**
  - No skill matches the prompt, or `/dart-cleanup` was invoked with no args.
  - _Action_: Render the categorized [Skill Catalog](#-skill-catalog) with
    clickable `file://` links so the user can choose.

### 2. Missing Checkout Safety Net

If a target `SKILL.md` is selected but missing from the local filesystem,
output:

> ⚠️ **Missing local checkout**: Target skill `<skill-name>` was not found at
> `~/github/...`. Please ensure `https://github.com/<org>/<repo>` is cloned into
> `~/github/`.

### 3. Coding Standards, Public API & Config Guardrails

Consult [`references/patterns.md`](references/patterns.md) for full
architectural boundary rules and modern Dart 3+ code examples:

1. **Architecture, Boundary & Testing Guardrails
   ([`references/patterns.md`](references/patterns.md))**:
   - **Deep Public Boundary & `api_summary`**: Export only top-level
     orchestrators, immutable config objects, and result records in
     `lib/<pkg>.dart`. Verify zero unintended public API diffs after refactors
     via `dart run api_summary@^1.1.0 --check`.
   - **Pure Internal Decomposition (`cognitive_complexity <= 15`)**: Decompose
     only functions above `15` (production) or `40` (`_test.dart`) into
     file-private pure functions (`_computeX(input) -> output`, `<= 4` params,
     zero out-params). Avoid shallow single-caller pass-through helpers.
   - **Load-Bearing Library Boundaries (`part` vs. `lib/src/`)**: Use standalone
     `lib/src/` libraries when `0` `_private` accesses or class-modifier
     boundaries (`sealed`, `final`, `interface`, `base`, `._()`) are crossed;
     use `part` / `part of` when types share privileged library access.
   - **Testing (`dart-test-fundamentals`)**: Follow `dart-test-fundamentals` in
     the catalog below for real test doubles and behavioral assertions.
2. **Optional `kscripts` Config Hygiene (`lint-cleanup` & `tighten`)**:
   - When `kscripts` is on `PATH`, run `kscripts lint-cleanup --rewrite` and
     `kscripts tighten` (or `kscripts tighten --workspace`).

---

## 📋 Skill Catalog & Path Priority

<!-- DART_CLEANUP_CATALOG_START -->

<!-- prettier-ignore-start -->

### Required Local Repositories

| Repository | Local Directory | Synced Commit |
| :--- | :--- | :--- |
| [`dart-lang/skills`](https://github.com/dart-lang/skills) | `~/github/skills` | [`bf984f3`](https://github.com/dart-lang/skills/commit/bf984f3ef223dd85e92036f934bbcb6bf301e4ce) |
| [`kevmoo/analytica.dart`](https://github.com/kevmoo/analytica.dart) | `~/github/kevmoo/analytica.dart` | [`5d2e9dd`](https://github.com/kevmoo/analytica.dart/commit/5d2e9dde47c657527ff517b184f29c666b6e50e8) |
| [`kevmoo/dash_skills`](https://github.com/kevmoo/dash_skills) | `~/github/kevmoo/dash_skills` | [`ce6cdbd`](https://github.com/kevmoo/dash_skills/commit/ce6cdbde55300d871c974f70a686d329aafc01af) |
| [`kevmoo/source_gen_test`](https://github.com/kevmoo/source_gen_test) | `~/github/kevmoo/source_gen_test` | [`b42ebf0`](https://github.com/kevmoo/source_gen_test/commit/b42ebf0851a7e0c1ee0fbd2042b28186622edacb) |

### A. Refactoring & Code Quality
* **`dart-build-cli-app`**: CLI entrypoint structure, argument parsing
  (`package:args`), cross-platform scripts, exit codes, and compilation.
  * *Path*: `~/github/skills/skills/dart-build-cli-app/SKILL.md`
* **`dart-cognitive-complexity`**: Analyzes and reduces deeply nested control
  flow in Dart functions using automated AST scoring and refactoring tools.
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
* **`dart-modern-features`**: Records, extension types, class modifiers
  (`interface`, `base`, `final`), null-aware elements (`?e`), dot shorthands,
  and digit separators.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-modern-features/SKILL.md`
* **`dart-multiline-strings`**: Converts consecutive print statements and string
  concatenations into clean triple-quoted multiline strings.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-multiline-strings/SKILL.md`
* **`dart-seal-type-hierarchies`**: Converts closed class hierarchies into
  `sealed` types to enable compiler-verified exhaustive pattern matching.
  * *Path*: `~/github/kevmoo/dash_skills/skills/dart-seal-type-hierarchies/SKILL.md`
* **`dart-use-pattern-matching`**: Applies Dart 3 pattern matching, switch
  expressions, and object/record/MapEntry/list destructuring to unpack fields,
  validate schemas, and simplify control flow.
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
* **`source-gen-test-fuzz`**: Stress-tests Dart `source_gen` `Generator` and
  `GeneratorForAnnotation` code generators across combinatorial AST declaration
  matrices (`cartesianProduct` and `verifyGeneratorBatch`).
  * *Path*: `~/github/kevmoo/source_gen_test/skills/source-gen-test-fuzz/SKILL.md`

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
