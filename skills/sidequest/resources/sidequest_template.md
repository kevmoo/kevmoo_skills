# 🧭 Conversation Map & Sidequests

> [!CAUTION] **Uncommitted & Unpushed Changes:**
>
> - **Main Quest 2 (`fix-leak`):** `lib/worker.dart`
> - **Active Side-Quest S1:** `test/debug_test.dart`

## 🏆 [COMPLETED] Main Quest 1: Migrate `UserService` to `v2` API

> **VCS State:** `🧹 Clean` -> PR #142 (Merged upstream, local workspace synced)

- [x] [#1] 🛡️ **Sub-Quest 1.1:** Identify callers across repository -> _Done_
- [x] [#4] 🛡️ **Sub-Quest 1.2:** Update client stub bindings -> _Done_
  - [x] [#2] 💀 ~~_Blocker 1.2.1:_ Fix build missing `proto/public` dep~~ ->
        _Resolved_
  - [x] [#3] 👣 ~~_Step 1.2.2:_ Merge in PR #142~~ -> _Done_

---

## ⚔️ [ACTIVE HEAD] Main Quest 2: Investigate Thread Leak Issue

> **VCS State:** `📝 Dirty` | Branch: `fix-leak` | Modified: `lib/worker.dart`

- [x] [#5] 🛡️ **Sub-Quest 2.1:** Check config and run the reproduction test case
      -> _Done_
- [ ] 🛡️ **Sub-Quest 2.2:** Profile thread spawning across workers _(IN
      PROGRESS)_
  - [x] [#6 ⭐] 💀 ~~_Blocker 2.2.1:_ Resolve local Docker network timeout~~ ->
        _Resolved_
  - [ ] 👣 _Step 2.2.2:_ Run worker profiling script

### 🌿 Active & Parked Side Quests (For Main Quest 2)

- [ ] **[Active]** Check why debug flag behaves differently on local vs remote
      machine.
  - 📝 _VCS:_ `test/debug_test.dart` (Uncommitted)
- [ ] **🎒 [Parked / Tracked for Later]** Refactor `LegacyThreadMonitor` ->
      _Filed Issue #215 in project tracker_

---

## ⏸️ [PAUSED] Main Quest 3: Code Review for PR #27

> **VCS State:** `🚀 Uploaded` -> PR #27 (Awaiting Review)

- [ ] **Status:** Waiting on author reply to our comment on line 142.
