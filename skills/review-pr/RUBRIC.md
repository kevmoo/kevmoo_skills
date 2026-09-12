# Review Rubric: 13 Angles & The Inquisitor Doctrine

The model-agnostic code review evaluation rubric. Evaluates changes through 13 analytical lenses and filters candidate findings through the adversarial Inquisitor doctrine to eliminate reviewer theater and LLM noise.

---

## 🏛️ Part 1: The 13 Analytical Angles

Every pull request diff must be evaluated across these 13 distinct lenses:

### 1. Line Scan
Audit local line-level syntax, types, and logic:
* Nullability mismatches, unsafe bang operators (`!`), unhandled `null` branches.
* Off-by-one errors in slice ranges, array indexes, or loop termination bounds.
* Dynamic type casts (`as Foo`) that can throw at runtime without prior type checks (`is Foo`).
* Boolean operator precedence and accidental assignment in conditional expressions.

### 2. Removed Behavior
Audit what was deleted:
* What invariants, error branches, or validations were removed?
* Does deleted code silently break assumptions in un-modified caller files?
* Were cleanup steps (e.g. closing streams, timers, file handles) accidentally dropped?
* Were fallback branches removed prematurely before downstream consumers migrated?

### 3. Cross-File Tracer
Trace dependencies beyond the diff hunks:
* Did an interface, signature, or exported type change without updating all call sites?
* Do package exports (`index.dart`, `__init__.py`, `mod.rs`) properly re-export new APIs?
* Do mock implementations in test fixtures still mirror the updated production contract?

### 4. Language Pitfalls
Check language-specific traps and footguns:
* **Dart / Flutter**:
  * Unawaited futures causing race conditions or floating exceptions.
  * Mutating collections during iteration; missing `toList()` when transforming lazy iterables.
  * Stream subscriptions without cancellation in `dispose()`.
  * Passing non-constant expressions into `const` constructors or using mutable objects as default arguments.
* **Go**:
  * Goroutine leaks; channels with unbuffered writers that block indefinitely.
  * Mutating loop variables across goroutines; missing `context.Context` deadline propagation.
* **Python**:
  * Mutable default arguments (`def foo(bar=[])`).
  * Unbounded global dicts causing memory leaks; catch-all `except:` swallowing `KeyboardInterrupt` or `SystemExit`.

### 5. Invariants & Wrappers
Inspect abstraction boundaries and invariants:
* Are domain invariants enforced in public constructors or factory methods?
* Does a wrapper type leak its underlying implementation primitives to callers?
* Are state transitions atomic, or can the object be left in an inconsistent intermediate state upon failure?

### 6. Testing Skeptic
Scrutinize test quality, not just line coverage:
* Are tests asserting actual behavior, or are they assertion-free "smoke tests" that only verify non-crashing execution?
* Do tests exercise negative paths, timeout behavior, and invalid inputs, or only the happy path?
* Are mocks over-specified (testing the mock instead of real behavior)?
* Does every bug fix include a deterministic regression test reproducing the original issue?

### 7. Error Handling
Inspect exception and error paths:
* Are exceptions swallowed silently or caught without logging/rethrowing?
* Do functions return ambiguous `null` or `-1` instead of throwing typed, informative error classes?
* Is error context preserved when wrapping/re-throwing exceptions?

### 8. Reuse
Check for wheel reinvention:
* Does the diff introduce helper functions, math algorithms, or string parsers that already exist in the standard library, core SDK, or existing project dependencies (e.g. `package:collection`, `package:path`, `lodash`, `guava`)?
* Is duplicate helper logic introduced across sibling modules instead of consolidating into a common internal utility?

### 9. Simplification
The subtractive lens (eliminate over-engineering):
* Is this more complex than the problem requires?
* Does the change add premature abstractions, single-caller interfaces, or speculative configuration knobs that nothing uses?
* Can nested conditional branches be flattened with early-return guard clauses or switch expressions?

### 10. Efficiency
Audit performance in hot paths:
* Are expensive operations (JSON parsing, regex compilation, reflection, filesystem I/O) executed inside tight loops?
* Are collections repeatedly resized or allocated unnecessarily?
* Are lookups performed via $O(N)$ linear scans when a `Set` or `Map` lookup would be $O(1)$?

### 11. Altitude
Step back and evaluate high-level architectural coherence:
* Does this feature or logic belong in this package/layer, or does it violate separation of concerns?
* Does the change solve the actual user problem, or does it apply a superficial band-aid to a deeper structural flaw?

### 12. Readability & Conventions
Verify developer ergonomics and repository norms:
* Are public APIs and exported symbols documented with clear, grammatically sound docstrings?
* Do variable and function names convey intent rather than implementation mechanics?
* Does the code follow repository style guidelines and pass formatters (`dart format`, `gofmt`, `black`)?

### 13. Cyclomatic Complexity
Evaluate nesting and cognitive strain:
* Are functions excessively long (>50 lines) or deeply indented (>3 levels)?
* Does the function carry high Cognitive Complexity (nested loops, branching ternary operators, nested lambdas)?
* Can complex logic be decomposed into pure, testable sub-functions?

---

## ⚖️ Part 2: The Inquisitor Doctrine ("Presumption of Theater")

**Every candidate review finding is reviewer theater and pedantic noise until proven otherwise.**

LLM reviewers suffer from severe incentive bias: they invent imaginary hazards to prove they performed work. The Inquisitor acts as an adversarial filter. A finding MUST demonstrate concrete, mechanical proof of runtime defect or measurable maintenance harm, or face summary dismissal.

### The Five Inquisitorial Filters

Filter every candidate finding against these five pathologies:

1. **Imaginary Architecture & Unverified Assumptions**:
   * *Trap*: The reviewer assumes an execution model, threading model, or API contract absent from the codebase.
   * *Rule*: If the reviewer cannot cite an exact call site or contractual specification proving the assumption, **DISMISS** as `[DISMISSED: INVENTED_ARCHITECTURE]`.

2. **Synchronous Hand-Wringing & Defensive Paranoia**:
   * *Trap*: Demanding thread locks, async mutexes, or memory barriers in single-threaded, synchronous execution paths.
   * *Rule*: If the scenario requires impossible execution interleavings or paranoid double-checks, **DISMISS** as `[DISMISSED: PARANOIA]`.

3. **Pedantic Escalation**:
   * *Trap*: Elevating minor stylistic preferences, harmless setup repetition, or test fixture boilerplate to "architectural flaws".
   * *Rule*: If the code causes zero measurable harm to maintainability or runtime safety, **DISMISS** as `[DISMISSED: PEDANTIC_ESCALATION]`.

4. **Harmless Idempotence & Belt-and-Suspenders**:
   * *Trap*: Complaining about defensive null-checks, idempotent resets, or explicit cleanups because "the framework already handles it".
   * *Rule*: If the pattern is harmless defensive programming that does not harm readability or performance, **DISMISS** as `[DISMISSED: HARMLESS]`.

5. **Hallucinated Dependencies & APIs**:
   * *Trap*: Suggesting the author use third-party libraries, non-existent SDK methods, or unverified packages.
   * *Rule*: If the proposed replacement symbol or dependency cannot be verified to exist in the repository's active dependencies or language SDK, **DISMISS** as `[DISMISSED: HALLUCINATED_API]`.

---

## 🎯 Part 3: Severity Verdicts

Only findings that survive the Inquisitor filters are reported. Assign exactly one severity:

* **🚨 `[BLOCKING]`**: Must be addressed before merge. Correctness bugs, data loss, race conditions, broken tests, security vulnerabilities, or public API breaks.
* **💡 `[SUGGESTION]`**: Highly recommended improvements. Measurable performance wins, significant simplification, eliminating wheel reinvention, or missing edge-case test coverage.
* **🧹 `[HYGIENE_NIT]`**: Minor polish (dead imports, typos, docstring drift). Keep only if accompanied by confirmed defects or high signal. If the PR has zero blocking defects and zero suggestions, suppress cosmetic nits to deliver a clean approval.
