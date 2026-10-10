---
name: teach-me
description: >-
  Builds a primary-source-grounded prerequisite graph (or linear mastery track)
  of atomic concepts and guides the user through unfamiliar technical domains,
  specifications, or codebases one concept at a time via Socratic scenario
  checks, targeted teaching blocks, and fresh transfer questions. Use when
  invoking /teach-me, "teach me", learning a complex domain or architecture
  from first principles, mapping prerequisite concepts and key mental shifts,
  or verifying deep mental models before reviewing or writing code. Don't use
  for single-turn factual lookups (use quick-question), resolving open design
  trade-offs (use distilling-strategies-interactively), non-educational
  document/code review, co-editing, or issue triage (use slice-and-dice), or
  passive text summarization.
key_features:
  - Shared 2x3 Goal-vs-Topology routing across sequential, thematic, and convergent DAG structures
  - Root-first default with conversational skip-ahead and immediate teaching on any missed check
  - Strictly 1 active concept per turn with first-principles causal probes (zero syntax/convention trivia)
  - Generous plain-English grading without robotic diagnosis headers
  - Progressive disclosure via references/graph_schemas.md and references/miss-diagnosis-examples.md
---

# Teach Me (`/teach-me`)

Help the user build and verify a load-bearing, first-principles mental model of
a technical domain, specification, or codebase. Ground every concept in primary
sources, separate **Assessment** (`Scenario Check`, `Transfer Question`) from
**Pedagogy** (`Teaching Block`, analogies), and advance **one concept at a
time** so each foundational invariant clicks before dependent concepts unlock.

## Goal vs. Content Topology: `/teach-me` vs. `/slice-and-dice`

Human conversation is linear—you can only cover **1 item per turn**—regardless
of how the underlying material is structured. **User Goal** selects the skill;
**Content Topology** selects how items are organized:

| Content Topology                                          | `/teach-me` (Goal: Build & Verify a First-Principles Mental Model)                                                                           | `/slice-and-dice` (Goal: Review, Co-Edit, or Triage to Lock Concrete Decisions — Zero Socratic Quizzing)                             |
| :-------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| **1. Sequential / Document Order (`A -> B -> C`)**        | Linear mastery track (`[1/N]`) with 1 `Scenario Check` -> `Teaching Block` -> `Transfer Question` per step when `0` convergence nodes exist. | Top-to-bottom walkthrough (`[SND 1/N]` .. `[SND N/N]`) to critique, edit, and lock document sections in order.                       |
| **2. Thematic Clusters (`{A, B}, {C, D}`)**               | Groups concepts by subsystem (or scopes `> 12` concepts to one foundational cluster first) and verifies mastery 1 concept at a time.         | Groups an unordered backlog of issues or audit findings by theme/subsystem to lock triage decisions slice by slice.                  |
| **3. Convergent Prerequisite Graph / DAG (`A & B -> C`)** | Live color-coded Mermaid prerequisite graph (`✅ Mastered`, `🎯 Ready Next`, `🔒 Locked`) where mastering `A` and `B` unlocks `C`.           | Dependency-ordered slices (`A`, `B` before `C`) with a Mermaid dependency diagram to lock foundational architecture decisions first. |

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
| **State**      | `✅ Mastered` / `🎯 Ready Next` / `🔒 Locked`   | `✅ Mastered`: verified via check or user skip-ahead. `🎯 Ready Next`: all direct prerequisites `✅ Mastered` (eligible for the current turn). `🔒 Locked`: waiting on prerequisites (never quiz or lecture early). Flag transformative ideas with `★ Key Mental Shift`. |
| **Assessment** | `Scenario Check` / `Transfer Question (N_x-T1)` | **1 concrete causal _"why / what breaks if..."_ question** testing whether the invariant holds. `N_x-T1` verifies understanding after a `Teaching Block` by changing the **failure mode**, never just swapping nouns.                                                    |
| **Pedagogy**   | `Teaching Block`                                | Focused explanation delivered immediately when the user says `"teach me"` or misses a check—citing `Source` mechanics + a 1-sentence structural analogy. Never counts as mastery without a follow-up `N_x-T1`.                                                           |

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
     1. `(Recommended) Run linear/thematic mastery checks in teach-me` — keep
        the `Scenario Check` -> `Teaching Block` -> `Transfer Question` loop
        over a compact `[1/N]` checklist (with `Source`) without a Mermaid DAG.
     2. `Take an unquizzed guided tour` — walk through with primary-source
        `Teaching Blocks` and zero quizzing (or switch to `/slice-and-dice` for
        document review/co-editing).
     3. `Broaden scope into a convergent system graph` — include upstream or
        adjacent subsystems so genuine convergence dependencies emerge.
   - **Upper-Bound Scope Gate (`> 12–15` Atomic Concepts)**: If honest atomic
     mapping yields **`> 15` concepts** (or `> 12` across multiple subsystems),
     **halt before starting calibration**, present a high-level cluster
     breakdown in chat, and offer:
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

### Phase 2: Root-First Start + Conversational Skip-Ahead

1. **Keep Turn 1 Chat `<= 25` Lines**: Link to `<topic>_learning_graph.md`
   (never paste a duplicate Mermaid code block into chat), show a compact
   concept table (collapsing `🔒 Locked` range rows such as `N3–N8`), and start
   at **1 foundational root concept (`N1`)** marked `🎯 Ready Next` (see
   [references/graph_schemas.md](references/graph_schemas.md)).
2. **Invite Conversational Skip-Ahead**: Explicitly tell the user they can say
   _"I already know N1/N2, skip to N3"_ at any time to fast-forward those nodes
   (and their upstream prerequisites) directly to `✅ Mastered`.
3. **Pose 1 Root `Scenario Check` & Yield**: Ask **1 concise causal
   `Scenario Check`** on `N1` (1–3 sentence answer), then **stop calling tools
   and wait for the user's response**. Never simulate user answers.

### Phase 3: One-Concept-at-a-Time Assessment & Teaching Loop

1. **Strictly 1 Active Concept per Turn**: Probe or teach **1 `🎯 Ready Next`
   concept at a time** (1 scenario question, or 1 short `Teaching Block` + 1
   follow-up transfer check). Never bundle two concepts (`N1` + `N2`) or 4
   sub-questions into a 50-line wall of text.
2. **Generous Plain-English Grading**: When the user's plain-English intuition
   captures the core causal invariant (e.g., _"it's making a change w/out a
   difference"_), immediately mark the concept `✅ Mastered`, affirm why their
   intuition holds in 1 sentence, update `<topic>_learning_graph.md`, and pose
   the `Scenario Check` for the next `🎯 Ready Next` concept. Never withhold
   credit for missing buzzwords.
3. **Immediate Teaching on `"Teach Me"` or Any Missed Check (No Walk-Backward
   Refusal)**: If the user says `"teach me"` or misses a check on _any_ node,
   **teach that concept immediately**—never refuse to explain a question you
   just asked or send the user backward empty-handed. Follow the turn skeleton
   in [references/graph_schemas.md](references/graph_schemas.md):
   - Deliver a focused **`Teaching Block`**: affirm what held up in the user's
     answer first, explain the core mechanism anchored in `Source`, and give a
     1-sentence structural analogy.
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
- **No Walk-Backward Refusal to Teach**: Never ask a question and then refuse to
  explain the answer when the user misses or says `"teach me"`.
- **No Pedantic Buzzword Grading**: Credit plain-English causal understanding
  immediately as `✅ Mastered`.
- **No Self-Grading (`"Does that make sense?"`)**: Mastery transitions
  (`🎯 -> ✅`) require passing a `Scenario Check`, passing an `N_x-T1` transfer
  check, or an explicit user skip-ahead—never an analogy agreement.
