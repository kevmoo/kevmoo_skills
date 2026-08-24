---
name: author-issue
description: >-
  Author high-signal, anti-slop bug reports, feature requests, and pull request
  or changelist (CL) descriptions for GitHub and Buganizer/Piper. Enforces
  empirical reproduction, literal logs, exact commit/environment targeting,
  repository convention orientation, and strict anti-AI formatting (strips
  emojis, pleasantry preambles, gratuitous horizontal rules, and speculative
  architectural essays). Use when filing, drafting, formatting, or creating an
  issue, bug report, feature request, pull request, or CL description.
---

# Author Issue & Pull Request

Guidelines, protocols, and orientation tools for authoring concise, actionable,
high-signal issue descriptions, bug reports, and pull request / CL descriptions
across GitHub and Buganizer without AI formatting slop.

## Core Philosophy: Empirical Signal over Conversational Slop

Maintainers and engineers suffer from fatigue caused by low-effort, decorative
LLM outputs. A well-authored issue or PR description should take under 15
seconds for an engineer to triage and understand.

Every submission must prioritize **empirical evidence** (minimal reproduction
steps, literal CLI invocations, exact error strings, raw stack traces, test
verification logs, and commit SHAs) over conversational prose, speculative
architecture essays, or decorative formatting.

## The Anti-Slop Filter (Negative Invariants)

When drafting or submitting issues, PRs, or CL descriptions, enforce these
negative constraints:

* **No Decorative Emojis**: Never prefix titles, section headers, or bullet
  points with emojis (`🚀`, `🐛`, `📋`, `💡`, `✨`, `⚠️`, `🔍`).
* **No Gratuitous Dividers**: Do not insert `---` horizontal rules between every
  minor section. Standard Markdown headers (`###`) provide sufficient visual
  hierarchy.
* **No Conversational Fluff or Pleasantries**:
  * Omit opening preambles (*"While analyzing the repository..."*, *"I hope
    this helps improve project quality..."*).
  * Omit closing pleasantries (*"Let me know if you need anything else!"*,
    *"Looking forward to your thoughts!"*).
* **No Speculative Architecture Essays**:
  * In bug reports: Do not write multi-paragraph dissertations hypothesizing
    about theoretical system-wide catastrophes or broad architectural
    overhauls. State the observed defect, isolate the failing component, and
    limit proposed fixes to 1–2 factual sentences pointing to the exact line or
    function (or omit proposed fixes entirely).
  * In PRs: Explain strictly the rationale ("why") and the isolated delta
    ("what changed"). Do not narrate routine tool invocations.
* **No Inline Multiline Shell Escapes**:
  * Never pass multiline Markdown inline via `--body "line 1\nline 2"`, which
    causes literal `\n` escaping bugs in CLI tools.
  * Always write content to a temporary Markdown file and use `--body-file`
    (`gh`) or `--description_file` / stdin (`issues`, `jj describe`).

## Phase 1: Repository Conventions Orientation (Optional Pre-Flight)

Before authoring, orient with the repository's established conventions to adopt
its taxonomy (subsystem prefixes, conventional commit types, issue/PR label
vocabulary, and native templates).

### 1. Automated Orientation via `orient.dart`

Run the bundled orientation script in the target repository or against a remote
GitHub slug:

```bash
# In a local repository checkout:
dart run skills/author-issue/bin/orient.dart

# Against a remote GitHub repository (zero clone required):
dart run skills/author-issue/bin/orient.dart -R invertase/melos
```

* **What it gathers**:
  * Active human maintainers and reviewers (filtering out CI and bot accounts).
  * Common issue title prefixes (e.g. `[analyzer]`, `pkg_name:`, `request:`).
  * Common PR / CL title prefixes (e.g. `feat(scope):`, `fix:`, `refactor:`).
  * Repository label vocabulary and detected issue/PR templates with field schemas.
  * Sample maintainer titles for style calibration.
* **Slop Contagion Guardrail**: Use the gathered orientation *strictly* for
  taxonomy, title prefixes, and label selection. Do NOT adopt decorative slop,
  emojis, or conversational noise found in historical items.

### 2. Manual CLI Fallback

If running without Dart tooling:

```bash
# Discover maintainers, PR prefixes, and labels
gh pr list --state merged --limit 15 --json author,reviews,title,labels

# Discover issue title prefixes and labels
gh issue list --limit 15 --state all --json author,title,labels
```

## Title Conventions & Disambiguation

Use concise, imperative titles (≤70 characters) calibrated to whether you are
filing an issue or creating a pull request / CL:

* **When Authoring an Issue**: Adopt the repository's issue prefix convention
  (e.g., `request: ...`, `[subsystem] ...`, `area/foo: ...`).
* **When Authoring a PR / CL**: Adopt Conventional Commits (`feat(scope): ...`,
  `fix(scope): ...`) unless the repository's PR history explicitly indicates an
  alternative convention.

<!-- mdformat off(prevent table wrapping) -->
| Type | Convention Format | Good Example | Bad Example |
| :--- | :--- | :--- | :--- |
| **Bug** | `[subsystem] Failure on condition` | `[analyzer] Crash with NullPointer when parsing empty config.json` | `Bug in analyzer` or `[CRITICAL] System failure observed` |
| **Bug** | `subsystem: Failure on condition` | `cli: Flag --output fails when target directory does not exist` | `CLI tool is broken` |
| **Feature** | `[subsystem] Imperative capability` | `[auth] Support PKCE flow in OAuth2 authentication client` | `Feature request: make authentication better` |
| **Feature** | `request: Imperative capability` | `request: avoid cascading releases when constraints allow update` | `Feature idea for melos` |
| **PR / CL** | `type(scope): imperative summary` | `feat(sidequest): enforce fully numbered sub-quests and sub-bullets` | `Updates and fixes` |
<!-- mdformat on -->

## Standard Content Templates

### 1. Bug Report Template

```markdown
### Summary
1–2 sentence description of the failure and trigger condition.

### Steps to Reproduce
1. Execute `tool_name --flag value` (or minimal CLI command)
2. Pass input `<repro_input>`

### Observed Behavior
```text
<literal error output, exception message, or raw stack trace>
```

### Expected Behavior
<1–2 sentences describing the expected outcome>

### Environment / Target
- Target Commit / Version: `<commit_hash>` (or `CL <cl_number>`)
- Runtime / Platform: `<e.g. Linux x86_64, Dart 3.8.0, Node 22>`
```

### 2. Feature / Task Template

```markdown
### Context & Problem
1–2 sentences explaining what problem needs to be solved.

### Proposed Solution
Concrete description of the proposed interface, behavior, or flag.

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

### Non-Goals
- What this feature explicitly does NOT cover
```

### 3. Pull Request / CL Description Template

```markdown
### Rationale
1–2 sentences explaining why this change is needed.

### Summary of Changes
- Bulleted description of the concrete code changes
- Touch only what the task requires; no orphaned imports or unrelated diffs

### Verification
- Executed `dart test` (or `blaze-for-agents test //...`) with 100% pass
- Verified edge case `<repro_condition>` passes

Fixes #<issue_number>
```

## Mapping Standard Sections to GitHub YAML Issue Forms

When a repository uses GitHub Issue Forms (`.github/ISSUE_TEMPLATE/*.yml`), the
issue body is rendered as sequential H3 markdown sections matching each form
element's `label:` attribute. Map conceptual anti-slop sections to the form's
specific fields:

<!-- mdformat off(prevent table wrapping) -->
| Conceptual Section | Common YAML Field IDs | Rendered Form Heading |
| :--- | :--- | :--- |
| **Trigger Command** | `command`, `repro_command` | `### Command` |
| **Context & Problem** | `description`, `context`, `problem` | `### Description` or `### Context` |
| **Reasoning / Impact** | `reasoning`, `motivation` | `### Reasoning` |
| **Proposed Solution** | `solution`, `proposal`, `idea` | `### Proposed Solution` |
| **Additional Context** | `additional_context`, `comments` | `### Additional Context` (put Acceptance Criteria here) |
<!-- mdformat on -->

## Platform-Specific Execution

### GitHub (`gh` CLI)

1. **Template Discovery**: Check for existing templates under
   `.github/ISSUE_TEMPLATE/` or `.github/pull_request_template.md`. If present,
   structure fields to match the repository's native schema.
2. **Drafting & Submitting Issues**:
   * Always write the prepared Markdown to a temporary file (e.g. `/tmp/gh_issue.md`).
   * Pass `--body-file` to ensure non-interactive execution:
     ```bash
     gh issue create --title "[subsystem] Title" --body-file /tmp/gh_issue.md
     rm /tmp/gh_issue.md
     ```
3. **Drafting & Submitting Pull Requests**:
   ```bash
   gh pr create --title "feat(scope): title" --body-file /tmp/gh_pr.md
   rm /tmp/gh_pr.md
   ```
4. **Verification**: Confirm body rendered cleanly with real blank lines:
   ```bash
   gh issue view <issue_number> --json body --jq .body
   gh pr view <pr_number> --json body --jq .body
   ```

### Buganizer & Piper (Google3)

1. **Authorization Prerequisite**: Write actions mutate corporate trackers or
   code reviews. Ensure explicit user approval before executing write commands.
2. **Filing Buganizer Issues**:
   ```bash
   /google/bin/releases/issues-cli/issues mutate create \
     --title "[subsystem] Title" \
     --description_file /tmp/bug_desc.md \
     --component_id <id> \
     --priority P2 \
     --type BUG
   rm /tmp/bug_desc.md
   ```
3. **Updating CL Descriptions**:
   ```bash
   cat << 'EOF' | jj describe --stdin
   feat(scope): concise summary

   Why this change is needed and bulleted summary.

   BUG=<id>
   EOF
   ```

## Pre-Submission Verification Checklist

Before submitting any issue, PR, or CL description:

- [ ] Title follows repository convention (`[subsystem]`, `request:`, or `feat(scope):`) and
  is ≤70 chars.
- [ ] Zero decorative emojis on titles, headers, or bullet points.
- [ ] Zero pleasantry intro/outro paragraphs.
- [ ] Zero gratuitous `---` divider clutter.
- [ ] Steps to reproduce (for bugs) or verification tests (for PRs) are minimal,
  concrete, and copy-pasteable.
- [ ] Raw error logs and test outputs are literal and code-fenced.
- [ ] Multiline body was passed via `--body-file`, `--description_file`, or
  heredoc stdin (no literal `\n` escaping).
