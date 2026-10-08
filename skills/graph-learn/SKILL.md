---
name: graph-learn
description: >-
  Builds a live prerequisite graph of atomic concepts and guides the user
  through unfamiliar technical domains, specifications, or codebases via
  diagnostic calibration, Socratic scenario checks, and visual state tracking.
  Use when invoking /graph-learn, learning a complex domain or architecture
  from first principles, mapping prerequisite concepts and key mental shifts,
  or verifying deep mental models before reviewing or writing code. Don't use
  for quick factual lookups (use quick-question), resolving open design
  trade-offs (use distilling-strategies-interactively), flat or purely
  sequential document reviews (use slice-and-dice), or passive text
  summarization.
key_features:
  - Live prerequisite graph with Mastered, Ready Next, and Locked state tracking
  - Pre-flight scope & topology gates (< 5 flat topics vs. > 15 large domains)
  - Leaf-first diagnostic calibration with automatic prerequisite credit
  - Socratic scenario checks & fresh transfer questions
  - Dynamic mid-session graph updates when hidden gaps surface
---

# Graph Learn (`/graph-learn`)

Help the user build a genuine, load-bearing mental model of a complex technical
domain, specification, or codebase architecture by walking a **live prerequisite
graph** one unlocked layer at a time so every foundational invariant clicks
before dependent concepts are introduced.

> [!IMPORTANT]
>
> **Artifact & Mermaid Schemas**: Read
> [`references/graph_schemas.md`](references/graph_schemas.md) before writing
> `<topic>_learning_graph.md` for the exact Mermaid `classDef` palette
> (`mastered` / `ready` / `locked`), Part 1 Concept Index table, Part 2 lazy
> Mastered Notes appendix, and Fresh Transfer Question (`N_x-T1`) template.

## Core Graph Rules & Plain-Language Vocabulary

Keep all user-facing artifacts, Mermaid diagrams, and chat updates in clear,
self-explanatory engineering language—never leak academic set-theory or graph
jargon (such as _"Knowledge Space Theory"_, _"Hasse diagram"_, _"surmise
relation"_, _"Outer Fringe"_, or `$F^+(K)$`) to the user:

| Concept                          | Rule for the Agent                                                                                                                                                                                                              | User-Facing Term & Badge    |
| :------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :-------------------------- |
| **Atomic Concept**               | Model each node (`N1`, `N2`, ...) as **one single load-bearing mechanism or invariant** that can be verified with a short scenario. Never merge distinct mechanisms into a muddy umbrella node just to keep the node count low. | `Concept` (`N1`, `N2`, ...) |
| **Hard Prerequisite (`A -> B`)** | Draw `A -> B` **only** when concept `B` cannot be genuinely understood or applied without `A`. Omit loose "related-to" associations.                                                                                            | `Prerequisite`              |
| **Direct Prerequisites Only**    | Never draw redundant shortcut arrows (`A -> C` when `A -> B -> C` already exists). Keep only direct prerequisite edges so the visual graph stays clean.                                                                         | _(Visual arrow in diagram)_ |
| **Mastered State**               | Concepts the user has empirically verified through a scenario check or calibration fast-forward.                                                                                                                                | `✅ Mastered` (Green)       |
| **Ready Next (Unlocked)**        | Unmastered concepts whose direct prerequisites are **all** `✅ Mastered`. These are the **only** concepts eligible for teaching and probing on the current turn (except a one-time Turn 1 diagnostic calibration check).        | `🎯 Ready Next` (Amber)     |
| **Locked State**                 | Concepts still waiting on one or more unmastered prerequisites. Never quiz or lecture on these prematurely once calibration resolves.                                                                                           | `🔒 Locked` (Slate)         |
| **Key Mental Shift**             | The 2–4 transformative ideas in the graph that permanently change how you reason about the whole system (e.g., shifting from perimeter/HTTPS trust to an untrusted-intermediary model).                                         | `★ Key Mental Shift`        |

---

## The Workflow at a Glance

- [ ] **Phase 1: Map Concepts & Run Pre-Flight Scope/Topology Gates** → Verify
      the topic forms a real prerequisite graph (`5-15` atomic concepts), gating
      with the user if `< 5` / flat or `> 15`, then save
      `<topic>_learning_graph.md` with a live color-coded Mermaid diagram.
- [ ] **Phase 2: Diagnostic Calibration** → Calibrate starting state
      (`✅ Mastered` vs. `🎯 Ready Next`) via leaf-first probes or a root-first
      walk (Execution Halted for User Input).
- [ ] **Phase 3: Ready-Next Teaching & Verification Loop** → Run iterative
      scenario checks, targeted teaching, fresh transfer questions, and live
      diagram updates on `🎯 Ready Next` concepts.
- [ ] **Phase 4: Dynamic Graph Updates (As Needed)** → Insert missing upstream
      prerequisites or split overloaded nodes when hidden gaps surface.
- [ ] **Phase 5: Mastery Closure & Practical Payoff** → Summarize key mental
      shifts and transition directly to concrete codebase or design work.

---

## Detailed Execution Phases

### Phase 1: Map Concepts & Run Pre-Flight Scope / Topology Gates

1. **Ground in Primary Sources First:** Read the relevant codebase modules,
   design documents, specifications, or reference materials before designing the
   graph. Do not invent speculative domain rules when source code or specs are
   available.
2. **Draft Atomic Concepts & Check Scope / Topology Before Proceeding:**
   - **Lower-Bound & Topology Check (`< 5` Concepts or Not a Real Graph):**
     Graph learning only pays off when there are **`>= 5` atomic concepts** and
     **genuine prerequisite branching or convergence** (e.g., both `N1` and `N2`
     must click before `N3` makes sense). If the topic has `< 5` concepts or is
     a flat/sequential list without hard prerequisite dependencies, **halt
     before creating `<topic>_learning_graph.md`**, explain why, and offer:
     1. **Switch to a sequential walkthrough** (`/slice-and-dice` / `SND`).
     2. **Broaden or deepen the scope** (include upstream prerequisites or
        adjacent subsystems).
     3. **Explain directly in chat** (clarify the 2–4 concepts concisely).
   - **Upper-Bound Gate (`> 15` Atomic Concepts):** Never compress distinct
     mechanisms into one node or silently skip concepts just to stay under 15.
     If mapping at honest atomic granularity yields **`> 15` concepts**, **halt
     before starting calibration**, present a cluster breakdown, and prompt via
     `ask_question` (or numbered options):
     1. `(Recommended) Start with {sub_area} first ({k} concepts)` — master the
        foundational sub-graph first.
     2. `Prune to a specific target goal` — keep only the prerequisite chain
        required for a concrete task.
     3. `Proceed with all {n} concepts in one graph` — explicit escape hatch.
3. **Construct the Persistent Graph Document (`5-15` Concepts, Zero-Spoiler &
   Lazy Notes):** Save `<topic>_learning_graph.md` in the session's artifact
   directory (or `/tmp/<topic>_learning_graph.md` in standalone CLI
   sessions—never create untracked files in the repository worktree) using the
   Part 1 / Part 2 template in
   [`references/graph_schemas.md`](references/graph_schemas.md).
   - **Zero-Spoiler Turn 1 (`<= 80` lines):** Omit definitions, misconception
     callouts, and `🔒 Locked` prose from **Part 1**—printing answers above an
     active scenario check spoils diagnostic calibration, and pre-writing locked
     nodes bloats Turn 1 latency. Append mastery notes into **Part 2** lazily as
     concepts unlock.

---

### Phase 2: Diagnostic Calibration

Keep the Turn 1 chat response concise (`<= 25` lines): link to
`<topic>_learning_graph.md` (omitting duplicate Mermaid blocks in chat), show a
compact summary table (collapsing `🔒 Locked` range rows like `N5-N8` as
needed), use plain Unicode/code instead of `$...$` LaTeX (which renders as raw
text in many Markdown viewers), and calibrate starting `🎯 Ready Next` concepts:

1. **Path A — Leaf-First Calibration (Default when prior knowledge is partial or
   unknown):**
   - Initialize the Turn 1 Mermaid diagram with root concepts marked
     `🎯 Ready Next` and downstream nodes `🔒 Locked`, then issue a **one-time
     diagnostic calibration probe** on 1–2 mid-tier or near-goal concepts (1–3
     sentence answers).
   - **Automatic Prerequisite Credit (Fast-Forward):** When the user passes an
     advanced scenario check, automatically mark both that concept and all of
     its upstream prerequisites `✅ Mastered`.
   - **Walk Backward on Misses:** When a calibration probe misses (or the user
     says `"I don't know"`), leave the advanced node `🔒 Locked`, trace backward
     along incoming prerequisite arrows to the earliest unmastered prerequisite
     (`N1`, `N2`, ...), and teach/verify that `🎯 Ready Next` prerequisite
     first.
2. **Path B — Root-First Foundation Walk (When the user is new to the topic or
   says `"Start at the roots"`):** Start with 0 `✅ Mastered` nodes, mark root
   concepts `🎯 Ready Next`, and present only their scenario checks.

> [!IMPORTANT]
>
> **Strict Interactive Gate:** After presenting the initial calibration probes
> (or root scenario checks), stop calling tools and wait for the user's
> response.

---

### Phase 3: The Ready-Next Teaching & Verification Loop

1. **Bound Each Turn to 1–2 `🎯 Ready Next` Concepts:** Never lecture on or quiz
   `🔒 Locked` concepts. Keep checks to 1–2 concrete scenario questions per
   concept (1–3 sentence user replies).
2. **Treat `"I Don't Know — Teach Me!"` as First-Class Signal:** When the user
   asks to be taught or reveals a misconception, deliver a focused **Teaching
   Block** using the turn skeleton in
   [`references/graph_schemas.md`](references/graph_schemas.md): address the
   exact conceptual gap first, explain the mechanism with concrete code/protocol
   details + a structural analogy, and **issue a Fresh Transfer Question
   (`N_x-T1`)** testing the same invariant from a new angle.
3. **Track Partial Concept Progress (`(1/2)`):** When a two-part check passes
   `a` but misses `b`, mark `a` mastered, micro-correct + transfer-test `b`
   only, and badge the node `(1/2)` on `🎯 Ready Next` until `b` passes.
4. **Update the Live Mermaid Diagram on Every Turn:** Update both the Progress
   line and Mermaid node classes/badges in `<topic>_learning_graph.md` before
   sending your chat response, and state updated `✅ Mastered` and
   `🎯 Ready Next` concepts in a 2-line chat header.

---

### Phase 4: Dynamic Graph Updates & Phase 5: Mastery Closure

- **Dynamic Graph Updates (Phase 4):**
  - _Missing Prerequisite:_ If the user struggles with `Nk` due to an unmapped
    foundational idea `N_new`, insert `N_new -> Nk`, move `Nk` back to
    `🔒 Locked`, and make `N_new` `🎯 Ready Next`.
  - _Overloaded Concept Split:_ Split nodes bundling two independent mechanisms
    into `N_ka` and `N_kb`.
  - _Curiosity Tangents:_ Answer questions about downstream `🔒 Locked` concepts
    concisely, note which node owns that invariant, and return to the active
    `🎯 Ready Next` check.
- **Mastery Closure & Practical Payoff (Phase 5):** Once every goal/leaf concept
  is `✅ Mastered`, mark `100% Complete` in `<topic>_learning_graph.md`, emit a
  3–5 bullet summary of the `★ Key Mental Shifts` and invariants mastered, and
  pivot directly to applying the model (auditing PR diffs, verifying design doc
  claims, or writing code).

---

## Anti-Patterns & Guardrails

- **No Passive Walls of Text Before Probing:** Ask the scenario check first on
  newly unlocked `🎯 Ready Next` nodes (unless the user asks to be taught
  upfront) so you never lecture on concepts the user can already derive.
- **No Trivia or Self-Grading:** Ask causal/failure-mode questions (_"Why does X
  fail when Y happens?"_), never acronym trivia or _"Does that make sense?"_
  (which measures confidence rather than comprehension).
- **Analogy Is Pedagogy, Not Proof:** Ground every analogy in a concrete
  source-code or specification citation so metaphors never mask edge-case bugs.
