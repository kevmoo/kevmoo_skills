---
name: deslop-duplication-audit
description: >-
  Detects, audits, and safely remediates code duplication across open-source and
  external repositories using the standalone Deslop CLI tool and empirical test
  gating. Use when asked to run Deslop, clean up duplicate code, analyze
  copy-paste blocks, evaluate code redundancy, or audit structural code health
  across repositories under ~/github. Don't use for Google3 CitC codebases (use
  copy-paste-detection instead), simple syntax lints, or non-Git checkouts.
key_features:
  - Read-only Deslop CLI structural scanning
  - Git worktree isolation via new-worktree
  - Actionable vs Necessary architectural verification gates
  - Empirical baseline and post-refactor test suite validation
---

# Deslop Duplication Audit Protocol

This skill provides an empirical, architecturally disciplined workflow for identifying and refactoring duplicated code using Deslop (a tree-sitter structural duplicate code detection engine).

## 1. Toolchain & Execution Setup
- **Deslop Binary Location:** Use the standalone native executable deployed in
  userspace at `~/.local/bin/deslop` (or via
  `~/.local/share/mise/shims/deslop`). It is installed and tracked via `mise`
  (`github:Nimblesite/deslop@latest`) and can be executed via
  `mise exec -- deslop` (or `~/.local/bin/deslop`). Never download or build
  Rust toolchains from source.
- **Dart Tooling & Sandbox Rules:** When executing Dart CLI tooling (`dart test`,
  `dart analyze`, `pub get`) across repositories under `~/github/` (excluding
  `~/github/dart-sdk`), always invoke Dart via `~/github/flutter/bin/dart` (or
  prepend `~/github/flutter/bin:$HOME/.local/bin` to `PATH`). Never invoke the
  system `/usr/bin/dart` (Google3 edge build). In restricted sandbox
  environments, if pub pre-compilation fails with atomic rename exceptions
  (`PathNotFoundException`, `errno = 2`), pass `--no-precompile` (e.g.
  `dart test --no-precompile`).

## 2. Phase 1: Read-Only Discovery Scans
When asked to scan single or multiple repositories for duplication, execute
Deslop in strictly read-only mode so target Git working trees remain untouched
(zero `.deslop/` cache directory bloat or dirty git status). Output reports
should target the active conversation's scratch directory
(`<appDataDir>/brain/<conversation-id>/scratch/`):

```bash
mkdir -p <scratch-dir>/deslop_reports/<repo-name>
deslop <path-to-target-directory> \
  --output <scratch-dir>/deslop_reports/<repo-name>/report \
  --no-incremental \
  --no-fail-over \
  --log-to-console \
  --log-level warn
```

- Read the generated summary at
  `<scratch-dir>/deslop_reports/<repo-name>/report.txt` or parse
  `<scratch-dir>/deslop_reports/<repo-name>/report.json` using `jq` to rank top
  offending clusters.
- If scanning multiple repositories across a portfolio (e.g.
  `~/github/kevmoo/`), deploy parallel investigative subagents
  (`invoke_subagent`) to execute read-only scans concurrently and consolidate
  the reporting matrix in chat.

## 3. Phase 2: Worktree Isolation (`new-worktree`)
When instructed to evaluate fixes or apply refactorings, never modify primary repository trunk branches directly.
1. Consult and follow the **`new-worktree` skill** (`~/.agents/skills/new-worktree/SKILL.md`).
2. Inside the target repository root under `~/github/`, fetch origin and create an isolated sibling worktree branched from the latest public base revision:
   ```bash
   git fetch origin
   git worktree add -b refactor-deslop "/absolute/path/to/_<repo_name>-refactor-deslop" origin/main
   ```
   *(Substitute `origin/master` or `origin/HEAD` when applicable).*
3. Perform all inspection, compilation, editing, and test verification inside the new sibling directory (`~/_<repo_name>-refactor-deslop`).

## 4. Phase 3: The "Actionable vs. Necessary" Architectural Gate
**Do NOT treat every duplicate finding as a bug or mandatory refactoring target.** Deslop compares tree-sitter AST shapes, which can flag legitimate structural patterns. Before making any code edits, evaluate each candidate cluster against these criteria:

### ✅ Actionable Duplication (Refactor & Extract)
- **Copy-pasted helpers or decoders:** Identical algorithms, database record parsers, or conversion utilities scattered across multiple classes or files.
- **Redundant runtime iteration:** Repeating identical loops or path assertions sequentially when earlier statements already guarantee the constraint.
- **Repetitive CLI orchestration:** Copy-pasted external process invocations (`gh pr view`, subprocess execution) or JSON decoding blocks where schema updates would risk drift.
- **Code generator scaffolding:** Repetitive string builders or verbose AST instantiation that can be cleanly condensed into top-level parameterized emitters without altering generated output.

### 🛑 Necessary Duplication (Reject Refactoring & Preserve)
- **Type-unsafe polymorphic AST targets:** When similar-looking classes (such as analyzer AST statements like `BreakStatement` and `ContinueStatement`) do not share a common type interface defining the target property. Attempting to unify their callbacks via `dynamic` or casting sacrifices compile-time type safety for minimal line reduction.
- **Performance-critical specialized solver loops:** Symmetric horizontal vs. vertical grid traversals in algorithms (such as A* search solvers) where combining orthogonal strides into a single abstraction would require allocating closures or virtual interfaces inside tight execution loops.
- **Speculative wrapping of standalone entry points:** Abstracting trivial 4-to-6 line `try/catch` fallback formatting across unrelated standalone command-line binary entry points (`bin/<script>.dart`). This degrades code scannability for zero architectural benefit.

When a flagged cluster falls under *Necessary Duplication*, explicitly record an **Actionability Verdict of "Rejected"**, state the technical type/performance rationale in your report, and leave the code completely untouched.

## 5. Phase 4: Empirical Test Verification & Staging
For every actionable refactoring candidate, enforce strict empirical verification:
1. **Verify Baseline:** Execute dependencies and tests prior to modification (`dart pub get && dart test`). If tests fail on unmodified code, stop and report the broken baseline immediately.
2. **Surgical Modification:** Make targeted edits using file editing tools (`replace_file_content`). Touch only what the deduplication requires; do not reformat or re-architect adjacent code.
3. **Verify Post-Refactor Health:** Re-run static analysis (`dart analyze --fatal-infos`) and unit tests (`dart test`). Confirm **zero errors, zero warnings/infos, and 100% test pass rate** with zero regressions.
4. **Local Staging:** Stage verified diffs locally inside the worktree (`git add .`).
5. **Report & Await Instructions:** Present a high-density, bulleted summary directly in chat containing:
   - Clickable file link to the sibling worktree (without wrapping in backticks).
   - Actionability Verdict and technical rationale for each inspected cluster.
   - Exact test suite pass confirmations (before and after).
   - Net lines of code delta and summary of staged diffs (`git diff --cached --stat`).
   - Yield the floor cleanly without committing, pushing, or submitting Pull Requests until the user authorizes version control execution.
