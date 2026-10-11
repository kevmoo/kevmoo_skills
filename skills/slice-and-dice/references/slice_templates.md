# Slice-and-Dice (`SND`) Turn Templates

Reference templates for active `[SND K/N]` turns across Mode 1 (Unquizzed
Learning & Document Review) and Mode 2 (Co-Authoring & Iterative Editing),
showing the **4 Tracker States** (`[ ]`, `[-]`, `⏳ Deferred`, `☑️ Done`) and
the **Two-Tier End-of-Slice Action Footer**.

## Template 1: Case B Slice (Agent Offers Comments/Questions) with Upfront Realization & Split Anchors

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

- `☑️ [SND 1/5] Summary & Phases Overview (Source: Proposal §1)` -- **Done (Kept as-is)**
- **`[-] [SND 2/5] Client Constructors & Credential Wiring (Source: Proposal §2, lib/src/client.dart#L140-L152)`** 👈 *Active now*
- `[ ] [SND 3/5] Shared Type Inventory (Source: Proposal §3, lib/src/types.dart#L1-L60)` *(Updated: verified Row 4 in source)*
- `[ ] [SND 4/5] Cross-Platform Implications (Source: Proposal §4)`
- `[ ] [SND 5/5] Release & Versioning (Source: Proposal §5)`

> [!NOTE]
>
> **Realization / Plan Update**: While checking `lib/src/client.dart#L140-L152`
> for `[SND 2/5]`, I realized my initial draft critique against the 3-parameter
> constructor was wrong: passing `client:` disables internal lifecycle closure,
> whereas `clientFactory:` grants ownership so `.close()` tears down the
> underlying client cleanly. I dropped that draft critique below and narrowed
> `[SND 2/5]` to the two remaining constructor edge cases.

---

### `[-] [SND 2/5]` Client Constructors & Credential Wiring

- **Doc Section**: `Proposal → Credentials & Client Construction`

#### 💬 Comment 2A (Optional `registrar` Parameter)

- **📌 Exact Text to Anchor On**:
  > `CoreWeb.registerWith(null); // registrar is dynamic`

```text
Could we make the parameter optional (`static void registerWith([Object? registrar])`) so pure-Dart callers don't have to pass `null` explicitly?

In `lib/src/core_web.dart:71`, `registerWith` never reads the `registrar` argument -- it only sets the default platform instance.
```

#### 💬 Comment 2B (Default Instance Initialization)

- **📌 Exact Text to Anchor On**:
  > `Pure-Dart consumers import the contracts from common directly.`

```text
In `platform_interface.dart:30`, `_instance` currently defaults to `MethodChannelImpl()`.

Once the base platform class moves to the pure-Dart package while `MethodChannelImpl` stays in the framework package, how will `_instance` be defaulted on mobile when no explicit registration call runs?
```

👉 **Decision needed:** Say `"accept"` (or `"accept with <tweak>"`) to lock these comments and advance, `"keep as-is"` to ignore them and advance, `"defer"` to revisit at the end, or reply to zoom in.
````

## Template 2: Case B Slice — Co-Authoring / Edit (`Before` → `After` + `What Changed`)

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

- `☑️ [SND 1/5] Executive Summary & Goals (Source: docs/rollout_plan.md#L1-L40)` -- **Done (Applied edit)**
- `⏳ [SND 2/5] Legacy Migration Timeline (Source: docs/rollout_plan.md#L42-L50)` -- **Deferred (Revisit after `[SND 5/5]`)**
- **`[-] [SND 3/5] Rollout Criteria & Confidence Gates (Source: docs/rollout_plan.md#L52-L68)`** 👈 *Active now*
- `[ ] [SND 4/5] Testing & Corpus Verification Strategy (Source: docs/rollout_plan.md#L70-L105)`
- `[ ] [SND 5/5] 2027 Horizon & Non-Goals (Source: docs/rollout_plan.md#L107-L140)`

---

### `[-] [SND 3/5]` Rollout Criteria & Confidence Gates

- **Target Section**: `docs/rollout_plan.md#L52-L68`

#### 1. Current Text (`Before`)

```text
Now that the opt-in flag and browser CI are merged, burn down any remaining
rendering or stability blockers before flipping the default on main.
```

#### 2. Proposed Text (`After`)

```text
With the opt-in flag and browser CI merged:
1. **Publish Opt-In Guidance**: Document the opt-in configuration and automatic
   fallback behavior for early adopters.
2. **Execute Default-On Checklist**: Define and burn down the concrete
   benchmark and stability gates required before flipping the default on main.
```

#### 3. What Changed (`Added` / `Changed` / `Removed`)

- **Added**:
  1. Explicit developer documentation deliverable for the opt-in flag.
  2. Explicit Default-On Checklist step separating early-adopter opt-in from
     default-on flip criteria.
- **Changed**:
  - Replaced the generic *"burn down any remaining blockers"* phrasing with the
    two concrete milestones above.
- **Removed**:
  - Nothing substantive removed.

👉 **Decision needed:** Say `"accept"` (or `"accept, but change X"`) to apply `After` and advance, `"keep as-is"` to keep `Before` and advance, `"defer"` to revisit at the end, or reply to zoom in.
````

## Template 3: Case A Slice — Read-Only Walkthrough / `"No Comment Needed"`

```markdown
### `[-] [SND 4/5]` Testing & Corpus Verification Strategy (`docs/rollout_plan.md#L70-L105`)

- **✅ Verdict: No comment needed (holds up in source)**
- **How It Works**: `test/corpus_runner_test.dart#L22-L64` already runs the 50-package corpus under both compilers and fails CI on any new diff.

👉 **Next:** Say `"ok"` / `"next"` to advance to `[SND 5/5]`, `"defer"` to revisit at the end, or reply to zoom in.
```
