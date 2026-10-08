# Slice-and-Dice (`SND`) Turn Templates

Reference templates for active `[SND K/N]` turns across Mode 2 (Co-Authoring &
Iterative Editing) and Mode 1 (Document / Proposal Review).

## Template A: Co-Authoring / Edit Slice (`Before` → `After` + `What Changed`)

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

*(`"skip"` = `⏭️ Skipped (Deferred — revisit later)`, never delete; `"drop"` = discard)*

- `☑️ [SND 1/5] Executive Summary & Goals` — **Locked**
- **`[-] [SND 2/5] Rollout Criteria & Confidence Gates`** 👈 *Reviewing now*
- `[ ] [SND 3/5] Cross-Package API Boundaries`
- `[ ] [SND 4/5] Testing & Corpus Verification Strategy`
- `[ ] [SND 5/5] 2027 Horizon & Non-Goals`

---

### `[-] [SND 2/5]` Rollout Criteria & Confidence Gates

- **Target Section**: `docs/rollout_plan.md#L42-L50`

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

How does **`[SND 2/5]`** look? (Reply with tweaks, `"skip"` to defer and come
back later, `"drop"` to keep `Before`, or `"next"` to apply `After` and advance
to `[SND 3/5]`.)
````

## Template B: Document Review Slice with Explicit Agent Realization & Split Anchors

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

- `☑️ [SND 1/5] Summary & Phases Overview` — **Locked**
- **`[-] [SND 2/5] Client Constructors & Credential Wiring`** 👈 *Reviewing now*
- `[ ] [SND 3/5] Shared Type Inventory` *(Updated: verified Row 4 in source)*
- `[ ] [SND 4/5] Cross-Platform Implications`
- `[ ] [SND 5/5] Release & Versioning`

> [!NOTE]
>
> **Where I Changed My Mind & Updated the Plan**: While checking
> `lib/src/client.dart#L140-L152` for `[SND 2/5]`, I realized my initial draft
> critique against the 3-parameter constructor was wrong: passing `client:`
> disables internal lifecycle closure, whereas `clientFactory:` grants ownership
> so `.close()` tears down the underlying client cleanly. I dropped that draft
> critique below and narrowed `[SND 2/5]` to the two remaining constructor edge
> cases.

---

### `[-] [SND 2/5]` Client Constructors & Credential Wiring

- **Doc Section**: `Proposal → Credentials & Client Construction`

#### 💬 Comment 2A (Optional `registrar` Parameter)

- **📌 Exact Text to Anchor On**:
  > `CoreWeb.registerWith(null); // registrar is dynamic`

```text
Could we make the parameter optional (`static void registerWith([Object? registrar])`) so pure-Dart callers don't have to pass `null` explicitly?

In `lib/src/core_web.dart:71`, `registerWith` never reads the `registrar` argument—it only sets the default platform instance.
```

#### 💬 Comment 2B (Default Instance Initialization)

- **📌 Exact Text to Anchor On**:
  > `Pure-Dart consumers import the contracts from common directly.`

```text
In `platform_interface.dart:30`, `_instance` currently defaults to `MethodChannelImpl()`.

Once the base platform class moves to the pure-Dart package while `MethodChannelImpl` stays in the framework package, how will `_instance` be defaulted on mobile when no explicit registration call runs?
```

How do **Comment 2A** and **Comment 2B** look? (Reply with edits, `"skip"` to
defer for later, `"drop"` to omit, or `"next"` to lock `[SND 2/5]` and move to
`[SND 3/5]`.)
````
