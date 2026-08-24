---
name: github-landed-pr-cleanup
description: |-
  Automates post-landing cleanup for GitHub PRs across non-owned repositories:
  queries merged PRs, prunes local Git worktrees/branches, syncs default trunk
  branches to origin/HEAD, discovers owning Jetski sessions, and updates PM-OS tasks.
key_features:
  - Landed PR query & filtering
  - Local worktree & branch pruning
  - Jetski session discovery
  - PM-OS task status syncing
---

## When to use this skill

- Use this skill when asked to "clean up landed PRs", "audit merged PRs in the last 24h/week", "sync repos and delete worktrees for merged PRs", or when invoked via `/pr-cleanup`.
- This skill automatically locates all recently merged PRs authored by the user in external/non-owned repositories, discovers their local repository paths and sibling worktrees, safely prunes stale worktrees and merged feature branches, synchronizes `main` against `origin`, attributes the PR to original Jetski conversations, and identifies PM-OS task handles.

## How to use this skill (The Workflow)

1. **Dry-Run Preview**:
   Run the `cleanup.dart` helper script to discover merged PRs and preview candidate cleanup operations:
   ```bash
   dart run <path-to-skill>/bin/cleanup.dart --since 24h
   ```
   *(Options: `--since 24h`, `--since 48h`, `--since 7d`, `--author <username>`, `--include-owned`)*.

2. **Execute Local Cleanup**:
   Run with `--apply` to prune matching sibling worktrees (`_[repo]-[branch]`), delete local merged feature branches, and fast-forward trunk branches (`main`) against `origin`:
   ```bash
   dart run <path-to-skill>/bin/cleanup.dart --since 24h --apply
   ```

3. **Check and Update PM-OS Tasks**:
   - For any PM-OS task handles (`#XXXX` / `#XXXXX`) detected in the PR body or linked Jetski sessions:
     - Check task details:
       ```bash
       experimental/users/kevmoo/pm_os/pm-status shorthand --handle="<handle>" --enrich
       ```
     - If the task was specifically tracking PR landing, close it:
       ```bash
       experimental/users/kevmoo/pm_os/pm-work complete <project> "<handle>"
       ```
     - If the task remains open for follow-up work, log a progress update:
       ```bash
       experimental/users/kevmoo/pm_os/pm-status apply-changes --plan=<path_to_plan.json>
       ```

4. **Generate Summary Report Artifact**:
   - Save the markdown output into an artifact `pr_cleanup_report.md` in the brain artifact directory.
   - Present a concise executive table with clickable links to PRs, local paths, Jetski conversations, and PM-OS tasks.

## Script Options Reference

- `--since <duration>`: Time window to search (e.g. `24h`, `48h`, `7d`). Default: `24h`.
- `--author <username>`: GitHub username to filter by. Default: `kevmoo`.
- `--include-owned`: Also inspect repositories owned by the user (default: only non-owned repos).
- `--apply`: Execute Git worktree pruning, branch deletion, and remote sync (default: dry run).
- `--format <markdown|json>`: Output format. Default: `markdown`.
- `--github-dir <path>`: Base directory for repositories. Default: `~/github`.
- `--brain-dir <path>`: Jetski brain directory. Default: `~/.gemini/jetski/brain`.
- `--skip-sync`: Skip fast-forwarding default branches against `origin`.
- `--skip-worktrees`: Skip pruning matching sibling worktrees.
