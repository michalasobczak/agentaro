# 037 — One epic at a time in a space

Status: **closed** 2026-11-21 (owner: "Zamknij i buduj"); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [014](014-spaces.md), [016](016-sequential-steps.md), [018](018-working-folders.md), [033](033-autonomy-slider.md), [034](034-recurring-work.md), [036](036-parallel-agent-tasks.md)

## 1. TL;DR

The epics of one space run one after another, in the order they were ordered. A second epic of the space starts its first step only when the earlier one is done or cancelled. Tests with two epics in one space confirm it, including an epic that waits for the owner's answer.

## 2. Abstract

- **Current state:**
  - Spec 016 runs the steps of one epic one at a time.
  - Spec 036 R6 lets only one **step** at a time work in one working folder.
  - Steps of different epics in the same space can still interleave: epic A runs step 1, epic B runs step 1, then A runs step 2.
- **Gap or problem:**
  - Two epics change the same code and run each other's tests half-way through, so they collide.
  - A real case (production, Słodziaki): the MVP epic waited at step 6 for the owner's answer. Meanwhile a later epic, "enlarge the island", started in the same folder and changed the game code and spec 001 under it. The waiting step then found its spec changed.
- **Rationale:** an epic is one coherent change. Its steps assume the folder holds only their own work since the epic started.
- **Decision history:** the owner chose these rules (2026-11-21):
  - the unit is the **space**, not the folder, so it also covers spaces without a folder;
  - the order is the order of ordering;
  - whether a waiting epic lets the next one run was "no difference" to the owner, so the safe default stands: it does not.

## 3. Objective

**Goals**
- G1. At most one epic of a space is in progress: started, but neither done nor cancelled.
- G2. The next epic of the space starts by itself when the current one is done or cancelled, in the order the epics were ordered.
- G3. The owner and the director see why an epic waits, and for which epic.

**Out of scope**
- Steps within one epic, which stay sequential under spec 016.
- Calendar tasks (spec 010) and the director's planning and chat runs. Planning does not change the folder, so a later epic may be planned while an earlier one runs.
- A manual "let it overtake" or "start now". The owner can cancel an epic or move it to another space instead.
- Spec 036 R6: the step-level folder lock across spaces that share one folder stays as it is.

**Success criteria**
- S1. A space with two planned epics A (ordered first) and B: A's steps all run before B's first step is queued. B starts by itself within one scheduler tick after A is done.
- S2. When A is blocked, or a step of A waits for the owner's answer (spec 033), B does not start. When A is cancelled, B starts.
- S3. Two epics in different spaces still run side by side, within the agent limits of spec 036.
- S4. Two epics already in progress in one space when this ships (as in the production case): the step that is running finishes normally. The later-ordered epic queues no further step until the earlier one is done or cancelled.
- S5. The waiting epic shows "Waits for “A” in this space" on its page and on the Work board. The director's work list shows the same line.
- S6. A recurring occurrence (spec 034) whose space has another epic in progress is created and waits as in S1. It is not skipped.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | The epic start and the queuing of the next step (`StepChain.start_due`, `queue_next`) | to change |
| System | The epic page, the Work board card and the director's work list: the waiting line | to change |
| System | Tests: unit and integration for S1–S6 | to create |
| Data | None. Order comes from the epic's id; "in progress" comes from `started_at` and the state. | exists |

## 5. Functional Domain Changes

- **State:** steps of different epics in one space interleave → epics of one space run one after another.
- **Rules:**
  - R1. An epic is **in progress** when it has started (`started_at` is set) and is not done or cancelled. Blocked, waiting for an answer and waiting for a retry (spec 032) all count as in progress.
  - R2. The **holder** of a space is its earliest-ordered epic in progress. Only the holder may queue a step. Another started epic of the same space queues nothing until it becomes the holder. This covers S4.
  - R3. With no epic in progress, the earliest-ordered planned epic of the space that may start starts: due, approved under spec 033, with steps. An epic still being planned (state new) or waiting for approval does not hold the space, and does not stop a later planned epic from starting.
  - R4. "Earliest-ordered" means the lowest epic id, which is the order in which the owner or the director created it. A recurring occurrence is ordered when it is created.
  - R5. Moving an epic to another space retires its plan (spec 016), so it no longer holds the space it left. In its new space it queues like any other.
  - R6. When the holder is done or cancelled, the next epic starts in the same scheduler pass. The scheduler also starts it within one tick if that was missed.
- **Resilience:** after a restart the holder is computed again from the stored states, so no lock is kept in memory. Two scheduler passes that start epics at the same time are serialized by the existing transaction around queuing.
- **Data:** no migration.

## 6. Critical Path

1. The owner closes the spec.
2. Add the space check to the start and to the queuing of the next step, with tests S1–S4 and S6.
3. Show the waiting line on the epic page, the board and in the director's work list (S5).
4. Pass the gates, run the B20 analysis, and update CHANGELOG and README. Restart production while no step runs.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | R1–R4: holder choice | Model test: two and three epics with different states and order | Integration | A later epic queues a step while an earlier one is in progress |
| Integration | S1, S2, S4, S6 | Scheduler test with a stub executor: finish, block, answer and cancel A | Release | B starts while A waits for an answer; B never starts after A is cancelled |
| Contract | S3 | Two spaces, two epics, overlapping runs | Release | Epics of different spaces wait for each other |
| E2E | S5 | Page test: waiting line, escaped titles, no inline style | Release | Missing or wrong epic named |
| Manual | Production case | After a restart: epic 39 finishes its running step and then waits for epic 37 | — | Epic 39 queues step 3 while epic 37 is unfinished |

## 8. Expected Outcome

- **Direct effect:** epics of one space no longer change the same code at the same time.
- **Measurable effect:** zero interleaved steps of different epics within one space, checked in `task_runs`.
- **Side effects:** a space stands still while its current epic waits for the owner. A blocked epic must be answered, retried or cancelled before the next one runs. The waiting line names the epic, so the cause is visible.
- **Rollback:** remove the space check; behaviour returns to spec 036.

## 9. Additional Information

- **Rejected alternatives:**
  - A lock per working folder only: it does not cover spaces without a folder, and the owner chose the space.
  - Releasing the space while the epic waits for an answer: faster, but it produced today's collision.
- **Open:** nothing; the owner's answers are in section 2.
- **Implementation (2026-11-21):** `WorkItem#waits_for` names the holder; `StepChain.queue_next` queues nothing for an epic that waits; finishing, cancelling or closing an epic by hand starts the next one at once; a retry of a waiting epic keeps its time (`StepRetry.hand_over_due`) and a chat retry is refused with the reason. Tests: `test/models/one_epic_per_space_test.rb` (9), `test/integration/one_epic_per_space_test.rb` (2). Spec 036's tests now give each epic its own space; three older tests that put a second epic in a busy space were moved to another space (an intended change).
- **Security analysis (B20, after specs 001–037):** Brakeman 0 warnings, bundle-audit no vulnerabilities. The holder is looked up by the account and the space, so no other account's epic title can be shown (defence in depth; spaces already belong to one account). Titles are escaped on the pages and quoted in the director's prompt like other epic titles. Accepted risk: a blocked epic stops its space until it is answered, retried or cancelled — visible on the waiting epic. No regressions found in specs 016, 021, 032, 033, 034 and 036.
