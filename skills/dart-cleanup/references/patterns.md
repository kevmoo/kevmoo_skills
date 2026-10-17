# Dart Refactoring, Architecture & Language Modernization Patterns

Reference patterns, architectural boundary guardrails, and modern Dart 3+
language examples used by [`SKILL.md`](../SKILL.md).

---

## 1. Architecture, Boundary & Decomposition Guardrails

<!-- BEGIN SPOT: dart-complexity-and-helpers -->

- **Public Package / Subsystem Boundary (`lib/<pkg>.dart` & `api.txt`)**: Must
  be **Deep**. Export only top-level orchestrators, immutable configuration
  value objects, and result records. Hide AST walkers, SQL builders, and parser
  helpers inside `lib/src/` (never re-exported in `lib/<pkg>.dart`). Use
  explicit `export 'src/...' show ...;` **only in public `lib/<pkg>.dart`
  entrypoints**; when splitting an internal `lib/src/` file, update internal
  `import` sites directly rather than leaving `export ... show` bridge shims
  inside `lib/src/` files (which obscure symbol provenance and risk circular
  imports).
- **Public API Surface Verification (`dart run api_summary@^1.1.0`)**: After any
  file split or refactoring in a Dart package (Dart 3.12+ remote package
  runner—zero `pubspec.yaml` edits or global install required):
  - If `api.txt` is tracked: run `dart run api_summary@^1.1.0 --check` and
    require exit code `0`.
  - If `api.txt` is not tracked: capture
    `dart run api_summary@^1.1.0 -o /tmp/api_before.txt` before refactoring and
    `diff -u /tmp/api_before.txt /tmp/api_after.txt` after, requiring zero diff
    unless a public API change was requested.
- **Internal Decomposition & Shallow-Helper Guardrail (`lib/src/`)**: **Stop
  rule:** only declarations above `cognitive_complexity` 15 (production) or 40
  (`_test.dart`) are work items; stop once the max is `<= 15` (Target Zone
  `8–15`, not `0`). When decomposing, forbid stateful `_Populator` / `_Runner`
  helper classes that mutate caller maps/sets in-place; require **file-private
  pure functions (`_computeX(input) -> output`)** with zero out-parameters and
  `<= 4` parameters (`<= 3` preferred, `sliceScoreAtRoot >= 3`). Flag
  single-caller (`FanIn == 1`, `TestFanIn == 0`) pass-through helpers
  (`cognitive_complexity:shallow`: high-arity `>= 5` parameters, micro-helpers
  `< 5` body lines and `CC <= 1`, `SignatureLines >= BodyLines`, or
  `CROSS_FILE_SINGLE_CALLER`): re-inline a `SAFE_INLINE` helper when
  `CallerCCAfter <= 15` and it is a pass-through with no same-shape siblings and
  no meaningful domain contract; when `CallerCCAfter > 15` and `HelperCC <= 4`
  (`FLATTEN_AND_INLINE`), flatten the caller in place instead of
  bucket-brigading local variables across helper signatures. Benchmark hot
  per-element loops before splitting them; prefer a per-declaration
  `// cognitive_complexity:ignore` with a reason comment. Details: the
  `dart-cognitive-complexity` skill.

<!-- END SPOT: dart-complexity-and-helpers -->

<!-- BEGIN SPOT: dart-load-bearing-boundaries -->

- **Load-Bearing Library Boundary Rule (`part` / `part of` vs. Separate
  Libraries)**:
  - **Core Principle**: Prefer the boundary the language compiler enforces
    (library privacy + class modifiers) over one an annotation suggests
    (`@internal`, which is only an analyzer lint and still leaks into `api.txt`
    when attached to a member of an exported `PublicClass`).
  - **Tier 1 — Standalone `lib/src/` Library (Default When Boundary Is Not
    Load-Bearing)**: Extract declarations into a separate library under
    `lib/src/` with explicit `import` / `show` **only** when the cut requires
    **zero** visibility widening (`0` cross-cut `_private` member accesses) and
    crosses **zero** library-scoped class modifier boundaries (`sealed`,
    `final`, `interface`, `base`, or private generative constructors `._()`).
  - **Tier 2 — `part` / `part of` (Preferred When the Library Boundary Is
    Load-Bearing)**: Whenever multiple types require privileged library-level
    access to each other—such as subtyping a `sealed`, `final`, `interface`, or
    `base` class/mixin, calling a private constructor `._()` for subtype
    capability, or accessing `_private` members on a public or shared
    class—**keep them in the same library using `part` / `part of`**. Never
    force tightly privileged types into a single giant file just to avoid
    `part`, and never widen `PublicClass._member` to `@internal` just to split
    libraries.

<!-- END SPOT: dart-load-bearing-boundaries -->

---

## 2. Modern Dart 3+ Language Patterns & Code Examples

### A. Exhaustive `sealed` Hierarchies & Switch Expressions

Replace type-test chains (`if (node is ...)`) with `sealed` hierarchies and
exhaustive switch expressions:

```dart
sealed class CheckOutcome {
  const CheckOutcome();
}

final class CheckPassed extends CheckOutcome {
  final Duration elapsed;
  const CheckPassed(this.elapsed);
}

final class CheckFailed extends CheckOutcome {
  final String message;
  final int exitCode;
  const CheckFailed(this.message, {this.exitCode = 1});
}

String formatOutcome(CheckOutcome outcome) => switch (outcome) {
  CheckPassed(:final elapsed) => 'PASS (${elapsed.inMilliseconds}ms)',
  CheckFailed(:final message, :final exitCode) => 'FAIL [$exitCode]: $message',
};
```

### B. Records & Pattern Destructuring

Use records for lightweight multi-value returns from pure helper functions
instead of ad-hoc wrapper classes or out-parameters:

```dart
(List<String> validIds, List<String> missingIds) partitionIds(
  Iterable<String> requested,
  Set<String> known,
) {
  final valid = <String>[];
  final missing = <String>[];
  for (final id in requested) {
    (known.contains(id) ? valid : missing).add(id);
  }
  return (valid, missing);
}

void report(Iterable<String> ids, Set<String> known) {
  final (valid, missing) = partitionIds(ids, known);
  if (missing.isNotEmpty) {
    throw ArgumentError('Unknown IDs: ${missing.join(', ')} (valid: $valid)');
  }
}
```

### C. JSON & Map Schema Validation via Pattern Matching

Prefer switch/if-case map patterns over manual `containsKey` + cast chains:

```dart
(String owner, int prNumber) parsePullRequestEvent(Map<String, Object?> json) {
  if (json case {
    'repository': {'owner': {'login': final String owner}},
    'number': final int prNumber,
  }) {
    return (owner, prNumber);
  }
  throw const FormatException('Invalid pull_request payload schema.');
}
```

### D. Class Modifiers, Extension Types & Null-Aware Elements

Use `final class` for leaf implementation classes, `extension type` for
zero-cost typed wrappers, and null-aware collection elements (`?element`):

```dart
extension type const GitSha(String value) {
  String get short => value.length > 7 ? value.substring(0, 7) : value;
}

List<String> buildGitArgs({
  required GitSha base,
  String? pathFilter,
  bool statOnly = false,
}) => [
  'diff',
  if (statOnly) '--stat',
  base.value,
  ?pathFilter,
];
```
