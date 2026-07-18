# 🧭 Conversation Map & Sidequests

## 🏆 [COMPLETED] Main Quest 1: Migrate `UserService` to `v2` API
> **VCS State:** `🧹 Clean` -> PR #142 (Merged upstream, local workspace synced)
* [x] [#1] 🛡️ **Sub-Quest 1.1:** Identify callers across repository -> *Done*
* [x] [#4] 🛡️ **Sub-Quest 1.2:** Update client stub bindings -> *Done*
  * [x] [#2] 💀 ~~*Blocker 1.2.1:* Fix build missing `proto/public` dep~~ -> *Resolved*
  * [x] [#3] 👣 ~~*Step 1.2.2:* Merge in PR #142~~ -> *Done*

---

## ⚔️ [ACTIVE HEAD] Main Quest 2: Investigate Thread Leak Issue
> **VCS State:** `📝 Dirty` | Branch: `fix-leak` | Modified: `lib/worker.dart`
* [x] [#5] 🛡️ **Sub-Quest 2.1:** Check config and run the reproduction test case -> *Done*
* [ ] 🛡️ **Sub-Quest 2.2:** Profile thread spawning across workers *(IN PROGRESS)*
  * [x] [#6 ⭐] 💀 ~~*Blocker 2.2.1:* Resolve local Docker network timeout~~ -> *Resolved*
  * [ ] 👣 *Step 2.2.2:* Run worker profiling script

### 🌿 Active & Parked Side Quests (For Main Quest 2)
* [ ] **[Active]** Check why debug flag behaves differently on local vs remote machine.
  * 📝 *VCS:* `test/debug_test.dart` (Uncommitted)
* [ ] **🎒 [Parked / Tracked for Later]** Refactor `LegacyThreadMonitor` -> *Filed Issue #215 in project tracker*

---

## ⏸️ [PAUSED] Main Quest 3: Code Review for PR #27
> **VCS State:** `🚀 Uploaded` -> PR #27 (Awaiting Review)
* [ ] **Status:** Waiting on author reply to our comment on line 142.
