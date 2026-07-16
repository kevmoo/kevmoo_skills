# 🧭 Conversation Map & Sidequests

## 🏆 [COMPLETED] Main Quest 1: Migrate `UserService` to `v2` API
> **VCS State:** `🧹 Clean` -> PR #142 (Merged upstream,
> local workspace synced)
* [x] 🛡️ **Sub-Quest 1:** Identify callers across repository -> *Done*
* [x] 🛡️ **Sub-Quest 2:** Update client stub bindings
  * [x] 💀 ~~*Blocker:* Fix build missing `proto/public` dep~~ -> *Resolved*
  * [x] 👣 ~~*Step:* Merge in PR #142~~ -> *Done*

---

## ⚔️ [ACTIVE HEAD] Main Quest 2: Investigate Thread Leak Issue
> **VCS State:** `📝 Dirty` | Branch: `fix-leak` | Modified: `lib/worker.dart`
* [x] 🛡️ **Sub-Quest 1:** Check config and run the reproduction test case
* [ ] 🛡️ **Sub-Quest 2:** Profile thread spawning across workers *(IN PROGRESS)*
  * [x] 💀 ~~*Blocker:* Resolve local Docker network timeout~~ -> *Fixed*
  * [ ] 👣 *Step:* Run worker profiling script

### 🌿 Active & Parked Side Quests (For Main Quest 2)
* [ ] **[Active]** Check why debug flag behaves differently on local vs
  remote machine.
  * 📝 *VCS:* `test/debug_test.dart` (Uncommitted)
* [ ] **🎒 [Parked / Tracked for Later]** Refactor `LegacyThreadMonitor` ->
  *Filed Issue #215 in project tracker*

---

## ⏸️ [PAUSED] Main Quest 3: Code Review for PR #27
> **VCS State:** `🚀 Uploaded` -> PR #27 (Awaiting Review)
* [ ] **Status:** Waiting on author reply to our comment on line 142.
