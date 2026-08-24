---
name: author-issue
description: >-
  Author high-signal, anti-slop bug reports and feature issues for GitHub and
  Buganizer. Enforces empirical reproduction, literal logs, exact
  commit/environment targeting, and strict anti-AI formatting (strips emojis,
  pleasantry preambles, gratuitous horizontal rules, and speculative
  architectural essays). Use when filing, drafting, formatting, or creating an
  issue, bug report, or feature request.
---

# Author Issue

Guidelines and protocols for authoring concise, actionable, high-signal issue
descriptions and bug reports across GitHub and Buganizer without AI formatting
slop.

## Core Philosophy: Empirical Signal over Conversational Slop

Maintainers and engineers suffer from fatigue caused by low-effort, decorative
LLM outputs. A well-authored issue should take under 15 seconds for an engineer
to triage and reproduce.

Every issue must prioritize **empirical evidence** (minimal reproduction steps,
literal CLI invocations, exact error strings, raw stack traces, and commit SHAs)
over conversational prose, speculative architecture essays, or decorative
formatting.

## The Anti-Slop Filter (Negative Invariants)

When drafting or submitting issues, enforce these negative constraints:

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
  * Do not write multi-paragraph dissertations hypothesizing about theoretical
    system-wide catastrophes or broad architectural overhauls.
  * State the observed defect, isolate the failing component, and limit
    proposed fixes to 1–2 factual sentences pointing to the exact line or
    function (or omit proposed fixes entirely).
* **No Inline Multiline Shell Escapes**:
  * Never pass multiline Markdown inline via `--body "line 1\nline 2"`, which
    causes literal `\n` escaping bugs in CLI tools.
  * Always write content to a temporary Markdown file and use `--body-file`
    (`gh`) or `--description_file` (`issues`).

## Title Conventions

Use concise, imperative titles formatted as:
`[subsystem] Specific failure on condition`

<!-- mdformat off(prevent table wrapping) -->
| Type | Good Example | Bad Example |
| :--- | :--- | :--- |
| **Bug** | `[analyzer] Crash with NullPointer when parsing empty config.json` | `Bug in analyzer` or `[CRITICAL ISSUE] Crash occurred` |
| **Bug** | `[cli] Flag --output fails when target directory does not exist` | `CLI tool is broken` |
| **Feature** | `[auth] Support PKCE flow in OAuth2 authentication client` | `Feature request: make authentication better` |
<!-- mdformat on -->

## Standard Issue Templates

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

## Platform-Specific Execution

### GitHub (`gh` CLI)

1. **Template Discovery**: Check for existing templates under
   `.github/ISSUE_TEMPLATE/` (`.yml` forms or `.md` templates). If present,
   structure the issue fields to match the repository's native schema rather
   than forcing a generic template.
2. **Drafting & Submitting**:
   * Write the drafted Markdown to a temporary file (e.g. `/tmp/gh_issue.md`).
   * Submit via `--body-file`:
     ```bash
     gh issue create --title "[subsystem] Title" --body-file /tmp/gh_issue.md
     ```
   * Clean up the temporary file immediately after submission.
3. **Verification**: Verify the body rendered cleanly with real blank lines:
   ```bash
   gh issue view <issue_number> --json body --jq .body
   ```

### Buganizer (`issues` CLI in Google3)

1. **Authorization Prerequisite**: Write actions in Buganizer mutate corporate
   trackers. Ensure the user has explicitly requested creating the issue before
   executing write commands.
2. **Component Lookup**: Find the relevant component ID:
   ```bash
   /google/bin/releases/issues-cli/issues readonly search-components "<query>"
   ```
3. **Drafting & Submitting**:
   * Write description to a temporary file (e.g. `/tmp/bug_desc.md`).
   * Create the issue via `--description_file`:
     ```bash
     /google/bin/releases/issues-cli/issues mutate create \
       --title "[subsystem] Title" \
       --description_file /tmp/bug_desc.md \
       --component_id <id> \
       --priority P2 \
       --type BUG
     ```
   * Clean up `/tmp/bug_desc.md`.

## Pre-Submission Verification Checklist

Before submitting any issue, run through this mental checklist:

- [ ] Title has a subsystem prefix and concise failure statement.
- [ ] Zero decorative emojis on titles, headers, or bullet points.
- [ ] Zero pleasantry intro/outro paragraphs.
- [ ] Zero gratuitous `---` divider clutter.
- [ ] Steps to reproduce are minimal, concrete, and copy-pasteable.
- [ ] Raw error logs and stack traces are literal and code-fenced.
- [ ] Multiline body was passed via `--body-file` or `--description_file`.
