# Miss Diagnosis & Transfer Question Examples (`teach-me`)

Use this guide during **Phase 3 (Teaching & Verification Loop)** and **Phase 4
(Miss Diagnosis & Dynamic Graph Updates)** whenever a user misses a
`Scenario Check` or `Transfer Question`.

Agents default to mutating the prerequisite graph (inserting a new prerequisite
node) whenever a check fails. **Resist that reflex**: most misses are caused by
an ambiguous question or a normal gap on the active concept itself, neither of
which changes the graph topology.

---

## 1. Five-Way Miss Diagnosis Procedure (Evaluate in Order)

When a user's answer misses the target invariant, classify the cause by walking
this decision list top-to-bottom:

| Order | Diagnosis                                             | Diagnostic Signal                                                                                                                                                                     | Required Action                                                                                                   | Mutates Graph?   |
| :---- | :---------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------- | :--------------- |
| **1** | **Ambiguous Scenario Question** _(Agent fault)_       | The user's answer is valid under a reasonable interpretation because your scenario omitted a key boundary condition (e.g., threat capability, concurrency model, or caller contract). | State the missing constraint in 1 sentence and re-ask the tightened check. Do **not** lecture on the concept yet. | **No**           |
| **2** | **Active Concept Gap / `"Teach Me"`** _(Normal path)_ | Prerequisites are solid and the prompt was clear, but the user hasn't yet grasped the active `🎯 Ready Next` invariant (or said `"I don't know"`).                                    | Deliver a **Teaching Block** (Pedagogy) followed by a **Fresh Transfer Question (`N_x-T1`)** (Assessment).        | **No**           |
| **3** | **Curiosity Tangent**                                 | The user asks about a `🔒 Locked` downstream node or an orthogonal code detail instead of answering the scenario.                                                                     | Answer in 1–2 sentences, name the node that owns that invariant, and re-surface the active `🎯 Ready Next` check. | **No**           |
| **4** | **Overloaded Concept**                                | The node bundles two distinct mechanisms that can fail independently; the user proves one and misses the other.                                                                       | Split `N_x` into `N_xa` (`✅ Mastered`) and `N_xb` (`🎯 Ready Next`) with separate `Source` anchors.              | **Yes (Split)**  |
| **5** | **Missing Upstream Prerequisite**                     | The user fails because they lack a foundational mechanism _external_ to `N_x` that was never mapped in the index.                                                                     | Insert `N_new -> N_x`, move `N_x` back to `🔒 Locked`, and make `N_new` `🎯 Ready Next`.                          | **Yes (Insert)** |

---

## 2. Worked Diagnosis Examples

### Worked Example A: Ambiguous Scenario Question (Do Not Mutate Graph or Lecture)

- **Active Concept (`N4`)**: `Isolate Message Ownership & TransferableTypedData`
  (`Source: lib/src/worker_pool.dart#L88-L112`)
- **Initial Scenario Check (`N4`)**:
  > _"Worker A sends a `Uint8List` buffer of 50 MB to Worker B over a `SendPort`
  > and then mutates `buffer[0] = 0xFF`. What does Worker B observe, and what
  > happens to memory usage?"_
- **User Reply**:
  > _"If it's sent via `Isolate.exit` or wrapped in `TransferableTypedData`,
  > Worker A can't mutate it afterward and memory isn't copied."_
- **Why Inserting a Node Is Wrong**: The agent intended to test standard
  `SendPort.send(uint8List)` deep-copy semantics, but forgot to specify which
  send API was called. The user's reasoning is sound.
- **Proper Diagnosis & Response (Outcome 1 — Ambiguous Scenario)**:
  > _"Good catch on the API boundary—my scenario didn't specify that Worker A
  > called plain `sendPort.send(buffer)` while staying alive (without
  > `TransferableTypedData`). Since you already named both the zero-copy
  > transfer wrapper and the post-transfer mutation restriction, `N4` is
  > `✅ Mastered`."_

---

### Worked Example B: Missing Prerequisite vs. Active Concept Gap

- **Active Concept (`N5`)**: `Transparency Log Inclusion vs. Active Key Pinning`
  (`Source: docs/attestation_spec.md#section-4.2`)
- **Direct Prerequisites**: `N3: Untrusted Registry Threat Model`
  (`✅ Mastered`)
- **Scenario Check (`N5`)**:
  > _"An attacker compromises a publisher's OIDC workload token for 5 minutes,
  > signs a backdoored release, and records the signature in the public append-
  > only transparency log. Why does transparency-log verification still allow a
  > client to install the compromised package immediately?"_
- **Case 1 — Active Concept Gap (Outcome 2, No Graph Mutation)**:
  - _User Reply_: _"Doesn't the transparency log reject signatures if the build
    didn't come from the official branch?"_
  - _Diagnosis_: The user understands `N3` (untrusted registry) and knows what
    an append-only log is, but confuses **auditability** (recording every valid
    signature) with **policy enforcement** (blocking unauthorized branches at
    install time).
  - _Action_: Keep the graph unchanged. Deliver a **Teaching Block** contrasting
    append-only recording (passive security camera) vs. branch/identity policy
    verification (active door lock), then pose `N5-T1`.
- **Case 2 — Missing Upstream Prerequisite (Outcome 5, Insert Node)**:
  - _User Reply_: _"Wait—what is an OIDC workload token, and how can a build
    sign anything without a long-lived private key stored in CI secrets?"_
  - _Diagnosis_: The graph jumped straight from `N2: Asymmetric Signatures` to
    `N5: Transparency Logs` without mapping **keyless ephemeral workload
    certificates**. The user cannot reason about a 5-minute OIDC compromise
    until keyless signing is understood.
  - _Action_: Insert `N4: Ephemeral Workload Certificates` (`N2 -> N4 -> N5`),
    move `N5` back to `🔒 Locked`, and probe/teach `N4` as `🎯 Ready Next`.

---

## 3. Designing Fresh Transfer Questions (`N_x-T1`)

After delivering a **Teaching Block**, never re-ask the original question with
different variable or service names.

> **The Fresh Transfer Rule**: Change the **failure mode or scenario
> mechanics**, not the surface nouns. A valid `N_x-T1` question must **fail for
> a different operational reason** than the original check if the user memorized
> your words without understanding the underlying invariant.

| Quality                       | Original Check (`N3`: Untrusted Registry Threat Model)                                                                                                        | Candidate Transfer Question (`N3-T1`)                                                                                                                                                                                                                                                                                                   | Why It Fails or Succeeds                                                                                                                                               |
| :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Weak (Noun Swap Only)**     | _"A mirror serves a valid signature for `pkg-a` when the client requested `pkg-b`, and the signed payload omits the package name. How does the attack work?"_ | _"A CDN serves a valid signature for `image-x` when Docker requested `image-y`, and the payload omits the image name. What happens?"_                                                                                                                                                                                                   | **Invalid**: Identical cross-package substitution mechanics with `"pkg"` replaced by `"image"`.                                                                        |
| **Strong (New Failure Mode)** | _(Same cross-package substitution check above)_                                                                                                               | _"Now suppose the signed payload includes the exact package name `pkg-b` and `SHA-256` digest, but the registry strips the `attestations` field from the JSON metadata response and serves an older unattested `pkg-b@1.0.0` tarball. If the client only verifies attestations when the field is present, what invariant is violated?"_ | **Valid**: Tests the same `N3` untrusted-intermediary invariant via a **downgrade / omission failure mode** rather than a **cross-package substitution** failure mode. |
