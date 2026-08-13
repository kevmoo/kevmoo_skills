---
name: deslop-duplication-audit
description: >-
  Detects, audits, and safely remediates code duplication across repositories
  using the standalone Deslop CLI tool and empirical test gating. Use when asked
  to run Deslop, clean up duplicate code, analyze copy-paste blocks, evaluate
  code redundancy, or audit structural code health across local Git
  repositories. Don't use for non-Git checkouts or simple single-file syntax
  lints.
key_features:
  - Read-only Deslop CLI structural scanning
  - User confirmation gate & isolation options
  - Actionable vs Necessary architectural verification gates
  - Empirical baseline and post-refactor test suite validation
---

# Deslop Duplication Audit Protocol

This skill provides an empirical, architecturally disciplined workflow for
identifying and refactoring duplicated code using Deslop (a tree-sitter
structural duplicate code detection engine).

## 1. Toolchain & Execution Setup

- **Locating or Installing Deslop:**
  - Verify if `deslop` is available on `$PATH` (`which deslop`).
  - **Default**: Install via Cargo:
    `cargo binstall deslop || cargo install deslop`
  - **Fallback (mise / binary releases)**: Run
    `mise use -g github:Nimblesite/deslop@latest` (or `mise exec -- deslop`), or
    download the pre-compiled platform binary from
    [Nimblesite/Deslop Releases](https://github.com/Nimblesite/Deslop/releases/latest).
- **Environment & Tooling Verification:**
  - Ensure the repository's native toolchains (e.g. `dart`, `flutter`, `cargo`,
    `npm`, `go`, `pytest`) are accessible on `$PATH`.
  - _Sandbox note for Dart repositories_: In restricted container or sandbox
    environments where `.dart_tool` pre-compilation encounters atomic rename
    exceptions (`PathNotFoundException`, `errno = 2`), pass `--no-precompile`
    (e.g., `dart test --no-precompile`).

## 2. Phase 1: Read-Only Discovery Scans

When asked to scan single or multiple repositories for duplication, execute
Deslop in strictly read-only mode so target Git working trees remain untouched
(zero `.deslop/` cache directory bloat or dirty git status). Output reports
should target a dedicated scratch or temporary directory:

```bash
mkdir -p {scratch_dir}/deslop_reports/{repo_name}
deslop {target_dir} \
  --output {scratch_dir}/deslop_reports/{repo_name}/report \
  --no-incremental \
  --no-fail-over \
  --log-to-console \
  --log-level warn
```

- Read the generated summary at
  `{scratch_dir}/deslop_reports/{repo_name}/report.txt` or parse
  `{scratch_dir}/deslop_reports/{repo_name}/report.json` using `jq` to rank top
  offending clusters.
- If scanning multiple repositories across a workspace or portfolio, deploy
  parallel investigative subagents (`invoke_subagent`) to execute read-only
  scans concurrently and consolidate the reporting matrix in chat.

## 3. Phase 2: Discovery Presentation & User Alignment (Hard Stop)

After completing the discovery scan, present a high-density summary of the
findings directly to the user (top duplicate clusters, candidate files, and
potential savings).

**Do not start editing files or refactoring code immediately.** Enforce an
interactive confirmation gate:

1. **Confirm Intent**: Inquire whether the user wants to proceed with
   remediating any of the flagged duplication clusters.
2. **Inquire Where to Apply Changes**: Inquire how the user prefers to apply the
   refactoring:
   - **Current Working Copy / Branch**: Apply changes directly in the active
     branch (e.g. `main`, `master`, or current working branch).
   - **Feature Branch**: Create a dedicated working branch (e.g.
     `git switch -c refactor/dedup-{topic}`).
   - **Git Worktree**: Create an isolated worktree if preferred for parallel
     development (e.g. via `git worktree add` or the `new-worktree` skill if
     available).
3. **Hard Stop Gate**: Pause and await explicit user confirmation and location
   direction before creating branches, worktrees, or making code modifications.

## 4. Phase 3: The "Actionable vs. Necessary" Architectural Gate

**Do not treat every duplicate finding as a bug or mandatory refactoring
target.** Deslop compares tree-sitter AST shapes, which can flag legitimate
structural patterns. Before making any code edits, evaluate each candidate
cluster against these criteria:

### ✅ Actionable Duplication (Refactor & Extract)

- **Copy-pasted helpers or decoders:** Identical algorithms, database record
  parsers, or conversion utilities scattered across multiple classes or files.
- **Shared contract declarations:** Common `typedef` contracts, data models, or
  record shapes duplicated across platform stubs (extract to a shared neutral
  library/module and import where needed).
- **Redundant runtime iteration:** Repeating identical loops or path assertions
  sequentially when earlier statements already guarantee the constraint.
- **Repetitive CLI orchestration:** Copy-pasted external process invocations or
  JSON decoding blocks where schema updates would risk drift.
- **Code generator scaffolding:** Repetitive string builders or verbose AST
  instantiations that can be cleanly condensed into top-level parameterized
  emitters without altering generated output.

### 🛑 Necessary Duplication (Reject Refactoring & Preserve)

- **Type-unsafe polymorphic AST targets:** When similar-looking classes (such as
  AST statement variants) do not share a common type interface defining the
  target property. Attempting to unify their callbacks via `dynamic` or casting
  sacrifices compile-time type safety for minimal line reduction.
- **Performance-critical specialized solver loops:** Symmetric horizontal vs.
  vertical grid traversals in algorithms (such as search solvers) where
  combining orthogonal strides into a single abstraction would require
  allocating closures or virtual interfaces inside tight execution loops.
- **Speculative wrapping of standalone entry points:** Abstracting trivial
  4-to-6 line `try/catch` fallback formatting across unrelated standalone
  command-line binary entry points (`bin/<script>`). This degrades code
  scannability for zero architectural benefit.

When a flagged cluster falls under _Necessary Duplication_, explicitly record an
**Actionability Verdict of "Rejected"**, state the technical type/performance
rationale in your report, and leave the code completely untouched.

## 5. Phase 4: Empirical Test Verification & Staging

For every actionable refactoring candidate, enforce strict empirical
verification:

1. **Verify Baseline:** Execute dependencies and tests prior to modification
   using the project's native build tool (e.g. `dart pub get && dart test`,
   `cargo test`, `npm test`, `go test ./...`, `pytest`). If tests fail on
   unmodified code, stop and report the broken baseline immediately.
2. **Surgical Modification:** Make targeted edits using file editing tools.
   Touch only what the deduplication requires; do not reformat or re-architect
   adjacent code.
3. **Verify Post-Refactor Health:** Re-run the repository's static analyzer
   (e.g. `dart analyze --fatal-infos`, `cargo clippy`, `npm run lint`) and unit
   tests. Confirm **zero errors, zero warnings/infos, and 100% test pass rate**
   with zero regressions.
4. **Local Staging:** Stage verified diffs locally (`git add .`).
5. **Report & Await Instructions:** Present a high-density, bulleted summary
   directly in chat containing:
   - Target branch or worktree location.
   - Actionability Verdict and technical rationale for each inspected cluster.
   - Exact test suite pass confirmations (before and after).
   - Net lines of code delta and summary of staged diffs
     (`git diff --cached --stat`).
   - Yield the floor cleanly without committing, pushing, or submitting Pull
     Requests until the user authorizes version control execution.
6. **Teardown & Cleanup:** If changes are aborted or rejected:
   - For worktrees:
     `git worktree remove --force "{worktree_path}" && git branch -D {branch_name}`.
   - For temporary branches: `git switch - && git branch -D {branch_name}`.
