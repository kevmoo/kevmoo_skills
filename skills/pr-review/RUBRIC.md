# Review Rubric: 13 Angles & The Inquisitor Doctrine

The model-agnostic code review evaluation rubric. Evaluates changes through 13
analytical lenses and filters candidate findings through the adversarial
Inquisitor doctrine to eliminate reviewer theater and LLM noise.

---

## 🏛️ Part 1: The 13 Analytical Angles

Every pull request diff must be evaluated across these 13 distinct lenses:

### 1. Line Scan

Audit local line-level syntax, types, and logic:

- Nullability mismatches, unsafe bang operators (`!`), unhandled `null`
  branches.
- Off-by-one errors in slice ranges, array indexes, or loop termination bounds.
- Dynamic type casts (`as Foo`) that can throw at runtime without prior type
  checks (`is Foo`).
- Boolean operator precedence and accidental assignment in conditional
  expressions.

### 2. Removed Behavior

Audit what was deleted:

- What invariants, error branches, or validations were removed?
- Does deleted code silently break assumptions in un-modified caller files?
- Were cleanup steps (e.g. closing streams, timers, file handles) accidentally
  dropped?
- Were fallback branches removed prematurely before downstream consumers
  migrated?

### 3. Cross-File Tracer

Trace dependencies beyond the diff hunks:

- Did an interface, signature, or exported type change without updating all call
  sites?
- Do package entrypoints (`index.ts`, `__init__.py`, `mod.rs`) avoid leaking
  internal module symbols, and for Dart packages, do exports and multi-file
  refactors comply with the boundary rules in Angle 9
  (`dart-complexity-and-helpers`)?
- Do mock implementations in test fixtures still mirror the updated production
  contract?

### 4. Language Pitfalls

Check language-specific traps and footguns:

- **Dart / Flutter**:
  - Unawaited futures causing race conditions or floating exceptions.
  - Mutating collections during iteration; missing `toList()` when transforming
    lazy iterables.
  - Stream subscriptions without cancellation in `dispose()`.
  - Passing non-constant expressions into `const` constructors or using mutable
    objects as default arguments.
- **Go**:
  - Goroutine leaks; channels with unbuffered writers that block indefinitely.
  - Mutating loop variables across goroutines; missing `context.Context`
    deadline propagation.
- **Python**:
  - Mutable default arguments (`def foo(bar=[])`).
  - Unbounded global dicts causing memory leaks; catch-all `except:` swallowing
    `KeyboardInterrupt` or `SystemExit`.

### 5. Invariants & Wrappers

Inspect abstraction boundaries and invariants:

- Are domain invariants enforced in public constructors or factory methods?
- Does a wrapper type leak its underlying implementation primitives to callers?
- Are state transitions atomic, or can the object be left in an inconsistent
  intermediate state upon failure?

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

### 6. Error Handling

Inspect exception and error paths:

- Are exceptions swallowed silently or caught without logging/rethrowing?
- Do functions return ambiguous `null` or `-1` instead of throwing typed,
  informative error classes?
- Is error context preserved when wrapping/re-throwing exceptions?

### 7. Testing (Seam Discipline, Behavioral Assertions & Real Test Doubles)

Scrutinize test quality, seam discipline, and assertion substance (`FU2`). Flag
**newly added or literal-updated change-detector and tautological tests** in the
diff as **`[BLOCKING]`** (`CHANGES_REQUESTED`), and pre-existing untouched ones
as `[SUGGESTION]`:

<!-- BEGIN SPOT: dart-test-hermeticity -->

- **Test Seam Discipline (Package Integration vs. `lib/src/` Unit Tests)**:
  - **Package-Level & Integration Tests**: Import `package:<pkg>/<pkg>.dart`
    (the public entrypoint seam) and keep `lib/<pkg>.dart` exports strictly
    scoped to public consumers.
  - **Subsystem Unit Tests (`lib/src/`)**: Import internal **deep modules**
    (`package:<pkg>/src/<subsystem>.dart`)—such as unexported parsers, state
    machines, data models, or algorithms with simple interfaces and rich
    internal behavior—to unit-test edge cases directly; test thin single-caller
    helpers through their owning module's entrypoint.
- **Real Implementations & First-Party Fakes ("Tests That Can Fail")**: Exercise
  real dependencies and first-party fakes so tests fail when production
  contracts break—use `package:test_descriptor` (`d.sandbox`, `d.dir`, `d.file`)
  or `Directory.systemTemp.createTempSync()` (always registered with
  `addTearDown(() => tempDir.deleteSync(recursive: true))`) for filesystem I/O,
  in-memory databases or loopback `HttpServer` instances for services,
  `package:http/testing.dart` (`MockClient`) for HTTP, hand-written fakes/stubs
  for custom interfaces, and `@TestOn('browser')` for DOM and JS/Wasm interop.
- **Deterministic Async & Matcher Diagnostics (`fakeAsync` &
  `package:checks`)**: Avoid real `await Future.delayed(...)` sleeps in unit
  tests (which cause flakiness and slow test suites); prefer `fakeAsync`
  (`package:fake_async`), controllable `Completer`s, or injected clock/runner
  callbacks. Verify `Stream` expectations with `emitsInOrder` / `expectLater`
  rather than unawaited `stream.listen(expectAsync1(...))` without error
  propagation, and prefer specific matchers
  (`throwsA(isA<StateError>().having((e) => e.message, 'message', contains('...')))`,
  `completion(...)`, `unorderedEquals(...)`) over `expect(x == y, isTrue)` or
  manual `try { ...; fail('...'); } catch (e) {}` blocks.

<!-- END SPOT: dart-test-hermeticity -->

<!-- BEGIN SPOT: dart-test-no-change-detectors -->

- **Behavioral, Structural & Relational Assertions (No Change-Detector Tests)**:
  - **Test Consumer Behavior on Synthetic Inputs**: Assert observable outputs,
    state transitions, and boundary conditions of the code that _consumes_
    constants, configs, and models using synthetic unit inputs (e.g., passing
    280 vs. 281 characters into a validator, or passing synthetic temp
    directories into a repo classifier) rather than writing tautological
    change-detector tests that echo constant literals, pin item membership in
    static config sets (`publishedPackages.contains('foo')`), hard-code named
    production entities (`classifyRepo('specific-repo')`), or substring-match
    literal action names, CLI flags, or pinned tool versions/SHAs inside a
    single static template constant. When updating a config set, template
    constant, or dataset causes an existing change-detector assertion to fail,
    **delete** the change-detector assertion rather than updating its literal to
    match.
  - **Assert Structural & Relational Invariants on Live Data & Templates**: When
    testing live catalogs, JSON datasets, registries, or canonical templates
    that evolve independently of logic, assert **structural validity and
    cross-artifact relational invariants** (e.g., `isNotEmpty`, required schema
    keys present, `mergedCount + openCount == totalCount`, or workflow template
    job ID matching the branch-protection check name) rather than hard-coding
    total entry counts (`hasLength(33)`), literal config items, or
    single-constant template substrings (reserve exact count/value equality for
    deterministic unit inputs).
- **Direct Execution & Rendering Verification**: Verify runtime behavior,
  control flow, and UI/CLI output by invoking functions, running CLI commands,
  or rendering components directly. Use raw file-text reads
  (`readAsStringSync()`) specifically for static documentation drift
  (`README.md` `--help` blocks), build/package metadata sync (`BUILD`,
  `pubspec.yaml`), and code-generator input/output fixtures.

<!-- END SPOT: dart-test-no-change-detectors -->

- Do tests exercise negative paths, timeout behavior, and invalid inputs, or
  only the happy path?
- Does every bug fix include a deterministic regression test reproducing the
  original issue?

### 8. Reuse

Check for wheel reinvention:

- Does the diff introduce helper functions, math algorithms, or string parsers
  that already exist in the standard library, core SDK, or existing project
  dependencies (e.g. `package:collection`, `package:path`, `lodash`, `guava`)?
- Is duplicate helper logic introduced across sibling modules instead of
  consolidating into a common internal utility?

### 9. Simplification

The subtractive lens (eliminate over-engineering):

- Is this more complex than the problem requires?
- Can nested conditional branches be flattened with early-return guard clauses
  or switch expressions?

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

### 10. Efficiency

Audit performance in hot paths:

- Are expensive operations (JSON parsing, regex compilation, reflection,
  filesystem I/O) executed inside tight loops?
- Are collections repeatedly resized or allocated unnecessarily?
- Are lookups performed via $O(N)$ linear scans when a `Set` or `Map` lookup
  would be $O(1)$?

### 11. Altitude

Step back and evaluate high-level architectural coherence:

- Does this feature or logic belong in this package/layer, or does it violate
  separation of concerns?
- Does the change solve the actual user problem, or does it apply a superficial
  band-aid to a deeper structural flaw?

### 12. Readability & Conventions

Verify developer ergonomics and repository norms:

- Are public APIs and exported symbols documented with clear, grammatically
  sound docstrings?
- Do variable and function names convey intent rather than implementation
  mechanics?
- Does the code follow repository style guidelines and pass formatters
  (`dart format`, `gofmt`, `black`)?

### 13. Cyclomatic Complexity

Evaluate nesting and cognitive strain:

- Are functions excessively long (>50 lines) or deeply indented (>3 levels)?
- For Dart code, enforce the cognitive complexity thresholds, decomposition
  criteria, and shallow-helper rules in Angle 9 (`dart-complexity-and-helpers`).

---

## ⚖️ Part 2: The Inquisitor Doctrine ("Presumption of Theater")

**Every candidate review finding is reviewer theater and pedantic noise until
proven otherwise.**

LLM reviewers suffer from severe incentive bias: they invent imaginary hazards
to prove they performed work. The Inquisitor acts as an adversarial filter. A
finding MUST demonstrate concrete, mechanical proof of runtime defect or
measurable maintenance harm, or face summary dismissal.

### The Five Inquisitorial Filters

Filter every candidate finding against these five pathologies:

1. **Imaginary Architecture & Unverified Assumptions**:
   - _Trap_: The reviewer assumes an execution model, threading model, or API
     contract absent from the codebase.
   - _Rule_: If the reviewer cannot cite an exact call site or contractual
     specification proving the assumption, **DISMISS** as
     `[DISMISSED: INVENTED_ARCHITECTURE]`.

2. **Synchronous Hand-Wringing & Defensive Paranoia**:
   - _Trap_: Demanding thread locks, async mutexes, or memory barriers in
     single-threaded, synchronous execution paths.
   - _Rule_: If the scenario requires impossible execution interleavings or
     paranoid double-checks, **DISMISS** as `[DISMISSED: PARANOIA]`.

3. **Pedantic Escalation**:
   - _Trap_: Elevating minor stylistic preferences, harmless setup repetition,
     or test fixture boilerplate to "architectural flaws".
   - _Rule_: If the code causes zero measurable harm to maintainability or
     runtime safety, **DISMISS** as `[DISMISSED: PEDANTIC_ESCALATION]`.

4. **Harmless Idempotence & Belt-and-Suspenders**:
   - _Trap_: Complaining about defensive null-checks, idempotent resets, or
     explicit cleanups because "the framework already handles it".
   - _Rule_: If the pattern is harmless defensive programming that does not harm
     readability or performance, **DISMISS** as `[DISMISSED: HARMLESS]`.

5. **Hallucinated Dependencies & APIs**:
   - _Trap_: Suggesting the author use third-party libraries, non-existent SDK
     methods, or unverified packages.
   - _Rule_: If the proposed replacement symbol or dependency cannot be verified
     to exist in the repository's active dependencies or language SDK,
     **DISMISS** as `[DISMISSED: HALLUCINATED_API]`.

<!-- BEGIN SPOT: dart-inquisitor-dismissal-filters -->

- **Dart Inquisitorial Review Dismissal Filters (`[DISMISSED: DART_THEATER]`)**:
  - **Exhaustive `switch` vs. Lookup Map Theater**: Never replace an exhaustive
    Dart 3 `switch` statement or `switch` expression over an `enum` or
    `sealed class` with a `Map<Enum, Handler>` lookup table or polymorphic
    Strategy class (which destroys compile-time exhaustiveness checking and adds
    heap allocation).
  - **Low-Cognitive-Complexity Split Theater**: Never split a Dart function
    whose AST `cognitive_complexity` score is `<= 15` (production) or `<= 40`
    (`_test.dart`) solely because of line count (`~50 lines`) or multi-phase
    procedural structure.
  - **High-Arity / Shallow Helper Extraction Theater**: Never extract a private
    helper that requires `>= 4` parameters (`HIGH_ARITY`), returns a
    record/tuple of mutated local state, or would be flagged by
    `cognitive_complexity:shallow` (`SAFE_INLINE`, `MICRO_HELPER`, `SIG_HEAVY`,
    `LOW_COMPLEXITY_PAYOFF`).
  - **Foreign-Language Idiom & Unverified Linter Duplication**: Never recommend
    `kConstantName` (instead of `lowerCamelCase`), explicit `break;` inside Dart
    3 `switch` cases, `sprintf`/string builders for single-expression string
    interpolation, or manual null checks where null-aware operators (`?.`, `??`,
    `??=`) or pattern matching (`if (x case final y?)`) already apply; do not
    flag unused imports, dead variables, or formatting issues already enforced
    by `dart analyze` and `dart format` unless corroborated by static analysis
    tools (`undead --suggest-private`, `dedupe`, `cognitive_complexity`).

<!-- END SPOT: dart-inquisitor-dismissal-filters -->

---

## 🎯 Part 3: Severity Verdicts

Only findings that survive the Inquisitor filters are reported. Assign exactly
one severity:

- **🚨 `[BLOCKING]`**: Must be addressed before merge. Correctness bugs, data
  loss, race conditions, broken tests, security vulnerabilities, or public API
  breaks.
- **💡 `[SUGGESTION]`**: Highly recommended improvements. Measurable performance
  wins, significant simplification, eliminating wheel reinvention, or missing
  edge-case test coverage.
- **🧹 `[HYGIENE_NIT]`**: Minor polish (dead imports, typos, docstring drift).
  Keep only if accompanied by confirmed defects or high signal. If the PR has
  zero blocking defects and zero suggestions, suppress cosmetic nits to deliver
  a clean approval.

---

## ✂️ Part 4: Outbound Comment Compression ("Internal Proof vs. External Prose")

The forensic detail required to pass **Part 2 (The Inquisitor Doctrine)** is for
the local review report (`Internal Proof (Do Not Post)`), **never** for the
outbound GitHub inline comment (`Outbound Inline Comment`).

When drafting the outbound inline comment for a human PR author:

1. **Hard Length Ceiling (`<= 50 words` / 2–3 sentences of prose)**:
   - Sentence 1: State the concrete failure mode, edge case, or regression on
     the pinned line.
   - Sentence 2 (or a GitHub ` ```suggestion ` block): Show the exact fix or ask
     the direct question.
2. **Zero Call-Stack Narration**:
   - Never narrate the PR author's own diff or call graph back to them (e.g., do
     **not** write _"In `Foo.bar()`, you call `_helper()`, which reads `baz`
     from `State` and passes it to..."_). The author just wrote that code and is
     looking directly at the anchored diff line.
3. **No Rubric Metadata or Emoji Banners**:
   - Strip `[BLOCKING]`, `[SUGGESTION]`, `🚨`, `💡`, and angle numbers from
     comments posted to GitHub.
