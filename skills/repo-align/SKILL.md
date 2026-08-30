---
name: repo-align
description: >-
  Audits and synchronizes personal GitHub repositories under github.com/kevmoo for alignment across analysis_options.yaml, CI workflows (lower_bound, complexity, autosubmit, dependabot), and GitHub branch rulesets.
author: kevmoo
target_environment: personal
compatibility: "Requires local checkouts in ~/github/kevmoo and scripts.dart"
---

# 📐 Personal GitHub Repositories Alignment (`repo-align`)

Audits and synchronizes personal GitHub repositories under [github.com/kevmoo](https://github.com/kevmoo) against canonical Dart and GitHub Actions standards.

---

## 🎯 Primary Purpose

Eliminates configuration drift across personal Dart repositories by enforcing:
1. **`analysis_options.yaml`**: Strict mode (`strict-casts`, `strict-inference`, `strict-raw-types`) and standard linter rules via `package:dart_flutter_team_lints`.
2. **CI Actions & Workflows**:
   - `lower_bound.yml`: Verifies lower-bound SDK dependency constraints via `dart pub downgrade && dart test`.
   - `complexity.yml`: Verifies Cognitive Complexity gating via `kevmoo/analytica.dart/packages/cognitive_complexity@main`.
   - `autosubmit.yml`: Automated PR merging on `autosubmit` label.
   - `dependabot.yml`: Weekly Actions and Pub dependency tracking.
3. **GitHub Rulesets & Branch Protection**:
   - Ensures `allow_auto_merge: true` on GitHub.
   - Enforces default branch protection rulesets on `~DEFAULT_BRANCH` with required status checks matching CI check names.

---

## 🛠️ CLI Usage (`scripts.dart`)

The alignment tool is built into `scripts.dart` (`bin/repo_align.dart` / executable `repo-align`):

### 1. Audit & Drift Report (Read-Only)

```bash
# Scan all ~/github/kevmoo checkouts and print markdown summary table
dart run bin/repo_align.dart check

# Output granular JSON data
dart run bin/repo_align.dart check --json

# Target a specific repository
dart run bin/repo_align.dart check --repo stats
```

### 2. Synchronize / Remediate Repositories

```bash
# Preview changes across all repositories (dry-run)
dart run bin/repo_align.dart fix --dry-run

# Fix only CI workflows on a specific repository
dart run bin/repo_align.dart fix --repo stats --ci

# Apply all fixes across all non-legacy repositories
dart run bin/repo_align.dart fix
```

---

## 📋 Remediation & Worktree PR Workflow

When remediating drift on an external repository:

1. **Worktree Isolation**: Create a dedicated sibling worktree via `new-worktree`:
   ```bash
   /new-worktree in ~/github/kevmoo/<repo> branch align-ci
   ```
2. **Apply Changes**: Run `repo-align fix --repo <repo>` or update targeted files.
3. **Verify Locally**:
   ```bash
   dart analyze --fatal-infos
   dart test
   dart pub downgrade && dart test
   ```
4. **Stage, Commit & Open PR**:
   - Commit with descriptive subject (e.g. `chore: align analysis options and add lower_bound and complexity CI`).
   - Push to feature branch and open PR with `autosubmit` label:
     ```bash
     git push origin <branch>
     gh pr create --title "chore: align CI workflows and analysis options" --body "..." --label autosubmit
     ```
5. **Verify CI**: Confirm all required checks go green and `autosubmit` completes squash merge.
