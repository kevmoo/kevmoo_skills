---
name: cold-read
description: >-
  Reads a draft issue, pull request, bug report, commit message, or review
  comment as a busy, fresh-context reader and reports whether that reader can
  make their next decision from the first few lines. Use when invoking
  /cold-read, before posting any agent-written artifact to a human audience, or
  when measuring how quickly past artifacts let a triager, code owner, or
  reviewer decide. Don't use for reviewing code diffs (use pr-review), triaging
  existing review comments (use pr-triage), or copy-editing prose style.
key_features:
  - Fresh-context reader simulation (triager, owner, reviewer)
  - Decision line and words-above-fold measurement
  - Known-to-reader and cut-list detection
  - Machine-readable JSON verdict for gating and batch baselines
---

# Cold Read (`/cold-read`)

A cold read answers one question about a draft: can the intended reader make
their next decision from the first N lines, and what would they cut?

The reader runs in a fresh context. It must not see the conversation that
produced the draft. That conversation is exactly what leaks into agent-written
artifacts as process narration and as background the reader already has.

## Invocation

```text
/cold-read <path> [--role triager|owner|reviewer] [--n 3]
```

- `path`: the draft file, in the form a human will see it. Strip draft-only
  preview lines first; a leading `# <Proposed Title>` line stays and counts as
  line 1.
- `--role`: who reads it. Default `triager`. Use `owner` when the likely reader
  wrote or maintains the code under discussion (small repositories, your own
  packages). Use `reviewer` for pull request bodies.
- `--n`: lines the reader gets before it must decide. Default 3.

## Steps

1. **Resolve the role.** Without `--role`, infer it: `owner` when recent commits
   on the paths the draft references come from one or two active maintainers;
   otherwise `triager`. Pull request bodies default to `reviewer`.
2. **Spawn a fresh-context, read-only reader.** Give it exactly three things:
   the contents of [references/persona.md](references/persona.md), the role and
   N, and the draft file path. Nothing else from the current conversation.
3. **Require the JSON shape** in
   [references/schema.json](references/schema.json). Re-run once if the reply is
   prose. Recompute `verdict` from `decision_line` and N yourself; the model's
   `decision_line` is the signal, its `verdict` is a convenience.
4. **Act on the verdict.**
   - `decide_in_n`: proceed.
   - `decide_later` or `cannot_decide`: move the sentence that carries the
     decision to the first body line, apply `cut_list` (keeping any sections
     required by the repository's PR template), add any `missing` facts, then
     re-run once.
5. **Report one line in chat**: verdict, decision line, words above the fold,
   and the number of cut lines. Do not restate the draft.

## Model choice

A fast model (`flash`) is sufficient for single-draft gating once
[references/persona.md](references/persona.md) anchors `decision_line` to the
first line of the block; both `flash` and the default model score the regression
fixtures identically. For batch baselines over multi-section artifacts, prefer
the default model when quota allows: in a 10-artifact calibration sample,
`flash` placed `decision_line` earlier on 2 of 10 drafts.

## Batch mode

For baselines over many past artifacts, run one reader per artifact in parallel,
each in its own fresh context, and tabulate `verdict`, `decision_line`,
`words_above_fold`, the `known_to_reader` count, and `missing`. Never give one
reader two artifacts; the second read is primed by the first.

## What the reader is for

The reader enforces the five outbound authoring principles and targets three
failure modes of agent-written text:

<!-- BEGIN SPOT: workflow-outbound-five-principles -->

1. **Lead with the decision.** Line 1 states the defect, ask, or change.
   Discovery history and process narrative go last or in a collapsed block.
2. **Budget words by reader count.** Title: hundreds of readers, search key +
   decision signal, `<= 70` chars. First 3 lines: tens, enough to triage or
   review. Body: one reader, repro + evidence + permalinks.
3. **Report the delta, not the tour.** Open with what is wrong or what changes.
   The owner already knows how their code works today, so a "currently, X does
   Y" opener is cut; a visitor gets one orienting line + permalink.
4. **Fill a slot only if it changes a decision.** Delete empty template
   sections, headers over single paragraphs, and parenthetical asides. One
   audience and one owner per artifact.
5. **Anchor, verify, then cold-read.** In issues/bugs, every claim carries a
   permalink and repro/verification steps. In PRs and code reviews, never
   narrate the diff file-by-file or recite routine CI checks (`dart analyze`/
   `dart test`)—state only the intent/why, non-obvious callouts or breaking
   changes, `Fixes #N`, and non-CI verification (e.g. benchmarks or manual UI
   checks). Traces go in `<details>` or issue attachments. Run `/cold-read` on
   the publish form and fix anything the reader cannot decide from the first 3
   lines.

<!-- END SPOT: workflow-outbound-five-principles -->

- **Discovery narration**: leading with what the agent found, in the order it
  found it.
- **Background the reader already has**: a tour of the reader's own code,
  including a "currently, X does Y" opener.
- **Template slots filled for completeness** rather than for a decision.

It does not judge style, tone, or grammar.
