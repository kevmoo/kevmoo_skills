---
name: quiz-me
description: >-
  Builds a primary-source-grounded prerequisite graph (or linear mastery track)
  of atomic concepts and tests the user across unfamiliar technical domains,
  specifications, or codebases one concept at a time with hard comprehension
  gates, targeted teaching blocks, and fresh transfer questions. Use when
  invoking /quiz-me, "quiz me", verifying that you truly know and have
  internalized a complex domain or architecture from first principles, or
  mapping prerequisite concepts and key mental shifts with active comprehension
  checks. Don't use for single-turn factual lookups (use quick-question),
  unquizzed learning walkthroughs, document/code review, co-editing, or issue
  triage (use slice-and-dice), branching design decision trees (use grilling or
  clarify-confirm-continue), or passive text summarization.
key_features:
  - Hard comprehension gates ("SND + retrieval practice") across a prerequisite DAG or linear checklist
  - Open-ended or inline "Pick + Explain Why" scenario checks with anti-guessing calibration prompts
  - Root-first default with conversational skip-ahead and immediate teaching on "teach me" or any miss
  - Strictly 1 active concept per turn with generous plain-English grading and zero robotic headers
  - Progressive disclosure via references/graph_schemas.md and references/miss-diagnosis-examples.md
---

# Quiz Me (`/quiz-me`)

Help the user verify and internalize a load-bearing, first-principles mental
model of a technical domain, specification, or codebase through **hard
comprehension gates** (`Scenario Check`, `Transfer Question`) paired with
on-demand **Pedagogy** (`Teaching Block`, analogies). Advance **one concept at a
time** so you cannot `"next, next, next"` past a concept without proving (or
explicitly testing out of) the causal `"why"`.

## Relationship to `/slice-and-dice` (`SND` + Hard Comprehension Gates)

Human conversation is linear—you can only cover **1 item per turn**—so
`/slice-and-dice` and `/quiz-me` share the same 1-item-per-turn pacing and
persistent Markdown tracker, differing on **Hard Comprehension Gates**:

| Dimension                                         | `/slice-and-dice` (`SND` — Unquizzed Walkthrough, Review, & Co-Edit)                                          | `/quiz-me` (`SND` + Hard Comprehension Gates)                                                                                        |
| :------------------------------------------------ | :------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------- |
| **User Goal**                                     | Learn/understand without being quizzed, review/critique, or co-edit and lock concrete changes slice-by-slice. | _"I NEED to know this—make sure I've internalized it"_ via active retrieval checks before each node unlocks.                         |
| **1. Sequential / Linear (`A -> B -> C`)**        | Walks top-to-bottom through a narrative RFC, slide deck, or document (`[SND 1/N]` .. `[SND N/N]`).            | Linear mastery track (`[1/N]`) with 1 `Scenario Check` -> `Teaching Block` -> `Transfer Question` per step (`0` convergence nodes).  |
| **2. Thematic Clusters (`{A, B}, {C, D}`)**       | Groups scattered audit findings, issue backlogs, or multi-file changes by theme or blast radius.              | Groups concepts by subsystem (or scopes `> 12` concepts to one foundational cluster first) and verifies mastery 1 concept at a time. |
| **3. Convergent Prerequisite DAG (`A & B -> C`)** | Out of scope for branching decisions (route decision trees to `grilling`).                                    | Live color-coded Mermaid prerequisite graph (`✅ Mastered`, `🎯 Ready Next`, `🔒 Locked`) where mastering `A` and `B` unlocks `C`.   |

## Core Vocabulary & Layers

Keep all user-facing artifacts, Mermaid diagrams, and chat updates in plain
engineering language—never use academic KST/graph jargon
(`"Knowledge Space Theory"`, `"Hasse diagram"`, `"surmise relation"`,
`"Outer Fringe"`, or `$F^+(K)$`) or raw LaTeX math (`$...$`) in prose:

| Layer          | Term & Badge                                    | Rule for the Agent                                                                                                                                                                                                                                                       |
| :------------- | :---------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Structure**  | `Concept` (`N1`, `N2`, ...)                     | **One load-bearing causal mechanism or invariant** anchored to a concise primary `Source` (`path/to/file#L10-L20` or spec section). Never merge distinct mechanisms into a muddy umbrella node.                                                                          |
| **Structure**  | `Prerequisite` (`A -> B`)                       | Draw `A -> B` **only** when `B` cannot be understood or reasoned about without `A`. Omit loose associations and redundant shortcut arrows (`A -> C` when `A -> B -> C` exists).                                                                                          |
| **Structure**  | `Convergence Node`                              | A concept with **`>= 2` direct prerequisites** (`N1 -> N3` and `N2 -> N3`). Mermaid graph mode requires at least one convergence node.                                                                                                                                   |
| **State**      | `✅ Mastered` / `🎯 Ready Next` / `🔒 Locked`   | `✅ Mastered`: verified via causal `"why"` check or user skip-ahead. `🎯 Ready Next`: all direct prerequisites `✅ Mastered` (eligible for the current turn). `🔒 Locked`: waiting on prerequisites (never quiz or lecture early). Flag key shifts with `★`.             |
| **Assessment** | `Scenario Check` / `Transfer Question (N_x-T1)` | **1 concrete causal question** (either open-ended _"what breaks if..."_ or inline `(A)/(B)/(C)` options in plain text **requiring a `"why"` explanation**). `N_x-T1` verifies understanding after a `Teaching Block` by changing the **failure mode**, never just nouns. |
| **Pedagogy**   | `Teaching Block`                                | Focused explanation delivered immediately when the user says `"teach me"` / `"not sure"` or misses a check—citing `Source` mechanics + a 1-sentence structural analogy. Never counts as mastery without a follow-up `N_x-T1`.                                            |

---

## Execution Phases

### Phase 1: Ground in Primary Sources & Run Pre-Flight Gates

1. **Read Primary Sources First**: Inspect the owning codebase files, specs, or
   design docs before drafting concepts. Include a concise **`Source`** column
   in the Concept Index (`path/to/file#L10-L20`, `RFC 9110 §9.3`, or
   `_(First-principles invariant)_`—never append `"— no local file"`).
2. **Model First-Principles Causal Mechanics Only (No Memorization Trivia)**:
   Model _why_ a mechanism exists or _what failure mode_ it prevents. Never
   model or quiz the user on arbitrary naming conventions, formatting strings,
   badge literals, CLI flag names, or internal specification syntax—state
   conventions directly and only quiz on causal system invariants that can be
   reasoned about from first principles.
3. **Run Pre-Flight Topology & Scope Gates**: Map atomic concepts honestly
   without compressing distinct mechanisms to hit an artificial cap:
   - **Convergence Topology Gate (`0` Convergence Nodes or `< 5` Concepts)**: If
     the mapped concepts form a straight sequential chain or flat list with
     **`0` convergence nodes** (or `< 5` items), **halt before creating
     `<topic>_learning_graph.md`**, state clearly why a prerequisite graph adds
     no value for a sequential chain with zero convergence nodes, and offer:
     1. `(Recommended) Run linear/thematic mastery checks in quiz-me` — keep the
        `Scenario Check` -> `Teaching Block` -> `Transfer Question` loop over a
        compact `[1/N]` checklist (with `Source`) without a Mermaid DAG.
     2. `Switch to /slice-and-dice for an unquizzed guided walkthrough` — walk
        through one slice at a time with primary-source explanations and zero
        quizzing.
     3. `Broaden scope into a convergent system graph` — include upstream or
        adjacent subsystems so genuine convergence dependencies emerge.
   - **Upper-Bound Scope Gate (`> 12–15` Atomic Concepts)**: If honest atomic
     mapping yields **`> 15` concepts** (or `> 12` across multiple subsystems),
     **halt before starting calibration**, present a compact bulleted cluster
     breakdown in chat (`1` bullet per cluster with node range, count, and
     1-line scope summary—never pack multi-line `<br>` node lists into wide
     Markdown table cells), and offer:
     1. `(Recommended) Start with a foundational sub-area first ({k} concepts)`
        — master the foundational cluster before expanding downstream.
     2. `Prune to a specific target goal` — keep only the prerequisite chain
        required for the user's concrete task.
     3. `Proceed with all {n} concepts in one graph` — explicit escape hatch.
4. **Save `<topic>_learning_graph.md` (`<= 80` Lines, Spoiler-Free)**: Once a
   convergent graph scope is confirmed, write `<topic>_learning_graph.md` in the
   session artifact directory (or `/tmp/<topic>_learning_graph.md` in standalone
   CLI sessions—never dirty the repository worktree) using the template in
   [references/graph_schemas.md](references/graph_schemas.md):
   - Populate **Part 1** with the live Mermaid diagram (`classDef mastered`,
     `ready`, `locked`), the 1-row-per-node Concept Index table with `Source`,
     and the single active `Scenario Check`.
   - Keep Turn 1 spoiler-free: **never** print `One-Line Definitions` or
     `Common Misconceptions` above unmastered `Scenario Checks`, and **never**
     pre-author multi-line textbook sections for `🔒 Locked` nodes. Append
     **Part 2** notes lazily as concepts unlock.

### Phase 2: Root-First Start, Skip-Ahead, & Anti-Guessing Calibration

1. **Keep Turn 1 Chat `<= 25` Lines**: Link to `<topic>_learning_graph.md`
   (never paste a duplicate Mermaid code block into chat), show a compact
   concept table (collapsing `🔒 Locked` range rows such as `N3–N8`), and start
   at **1 foundational root concept (`N1`)** marked `🎯 Ready Next` (see
   [references/graph_schemas.md](references/graph_schemas.md)).
2. **Invite Conversational Skip-Ahead**: Explicitly tell the user they can say
   _"I already know N1/N2, skip to N3"_ at any time to fast-forward those nodes
   (and their upstream prerequisites) directly to `✅ Mastered`.
3. **Pose 1 Root `Scenario Check` with Anti-Guessing Calibration & Yield**:
   - Frame the check as either an **open-ended causal scenario** (_"What breaks
     if..."_) OR an **inline 2–3 option scenario in plain text** (`(A) ...`,
     `(B) ...`, `(C) ...`, never an `ask_question` modal) **that requires
     explaining WHY**.
   - End every check with a 1-line anti-guessing nudge so lucky guesses don't
     mask gaps:
     > _"Take a stab and explain **why** if you have a solid hunch—or if you'd
     > be guessing, say `'teach me'` / `'not sure'` so we unpack it first."_
   - Stop calling tools and wait for the user's response. Never simulate user
     answers.

### Phase 3: One-Concept-at-a-Time Assessment & Teaching Loop

1. **Strictly 1 Active Concept per Turn**: Probe or teach **1 `🎯 Ready Next`
   concept at a time** (1 scenario question, or 1 short `Teaching Block` + 1
   follow-up transfer check). Never bundle two concepts (`N1` + `N2`) or 4
   sub-questions into a 50-line wall of text.
2. **Generous Plain-English Grading (Require `"Why"` on Inline Options)**:
   - When the user's plain-English intuition captures the core causal invariant
     (e.g., _"it's making a change w/out a difference"_), immediately mark the
     concept `✅ Mastered`, state the causal link that held in 1 sentence (no
     flattery filler like _"Spot on!"_, _"Great!"_, or _"Brilliant!"_), update
     `<topic>_learning_graph.md`, and pose the `Scenario Check` for the next
     `🎯 Ready Next` concept. Never withhold credit for missing buzzwords.
   - If the check included inline `(A)/(B)/(C)` options and the user replies
     with **only** a bare letter (`"B"`) without explaining _why_, do not mark
     `✅ Mastered` yet—confirm whether `"B"` is the right branch and ask a
     1-line _"What's the causal reason B happens here?"_ so a lucky guess never
     fakes comprehension.
3. **Immediate Teaching on `"Teach Me"` / `"Not Sure"` or Any Missed Check**: If
   the user says `"teach me"`, `"not sure"`, or misses a check on _any_ node,
   **teach that concept immediately**—never refuse to explain a question you
   just asked or send the user backward empty-handed. Follow the turn skeleton
   in [references/graph_schemas.md](references/graph_schemas.md):
   - Deliver a focused **`Teaching Block`**: state what held up in the user's
     answer first (without sycophantic adjectives), explain the core mechanism
     anchored in `Source`, and give a 1-sentence structural analogy.
   - Pose **1 fresh `Transfer Question (N_x-T1)`** that **changes the failure
     mode or scenario mechanics** rather than swapping surface nouns (see
     [references/miss-diagnosis-examples.md](references/miss-diagnosis-examples.md)).
4. **Internal 5-Way Miss Check & Zero Robotic Ceremony**: Before mutating the
   graph on a miss, check the 5-way rubric in
   [references/miss-diagnosis-examples.md](references/miss-diagnosis-examples.md)
   (`Ambiguous Scenario`, `Active Concept Gap`, `Curiosity Tangent`,
   `Overloaded Concept`, `Missing Prerequisite`) so you do not reflexively
   insert nodes on normal concept gaps or ambiguous prompts. Do **not** print a
   robotic `- **Diagnosis:** ...` header in chat. Update
   `<topic>_learning_graph.md` on every turn.

### Phase 4: Mastery Closure & Practical Payoff

When all goal concepts are `✅ Mastered`, mark `<topic>_learning_graph.md`
`100% Complete`, summarize the `★ Key Mental Shifts` with `Source` links in 3–5
bullets, and offer to transition directly into concrete codebase work or
`/slice-and-dice` review.

## Guardrails

- **No Memorization or Convention Trivia**: Never quiz on arbitrary string
  literals, badge formatting, CLI flag names, or acronym expansions.
- **No Unexplained Multiple-Choice Guessing**: Inline `(A)/(B)/(C)` options in
  plain text are welcome when they clarify the scenario, but never use
  `ask_question` modals for quiz questions and never credit a bare letter pick
  without a `"why"` explanation.
- **No Walk-Backward Refusal to Teach**: Never ask a question and then refuse to
  explain the answer when the user misses or says `"teach me"`.
- **No Pedantic Buzzword Grading**: Credit plain-English causal understanding
  immediately as `✅ Mastered`.
- **No Self-Grading (`"Does that make sense?"`)**: Mastery transitions
  (`🎯 -> ✅`) require passing a `Scenario Check` (with `"why"`), passing an
  `N_x-T1` transfer check, or an explicit user skip-ahead—never an analogy
  agreement.
