# 048 — Pause an epic

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [016](016-sequential-steps.md), [036](036-parallel-agent-tasks.md), [037](037-one-epic-at-a-time-per-space.md), [040](040-director-controls-failed-and-hung-steps.md)

## 1. TL;DR

The owner can pause one epic and resume it later, by a button or in words to the director. A step that is running finishes, and its result is kept. After it nothing more of that epic starts until the owner resumes it, also across restarts. Tests and a browser check confirm it.

## 2. Abstract

- **Current state:**
  - An epic can only be cancelled. Its plan is then gone, and a new epic must be planned again.
  - A running step can only be stopped. The director has no pause.
- **Gap or problem:** on 2026-11-22, before a restart, the owner wrote: "zapauzuj te wszystkie co teraz się uruchomiły, bo chcę zrobić restart". The director answered: "pauzy w ogóle nie mam, mogę je tylko anulować".
- **Decision history:** the owner chose (2026-11-22):
  - a running step finishes, then the epic stands;
  - the pause is for a single epic only;
  - a paused epic keeps its space, so the epics after it wait;
  - only the owner resumes it, by hand; a pause survives restarts.

## 3. Objective

**Goals**
- G1. **Pause.**
  - A planned epic (started or not, also one waiting for approval, its start time or its turn) can be paused.
  - Ways to pause: the epic's page, the work panel beside the chat, and the chat action `pause_epic`. The chat action needs the owner's words ("wstrzymaj miasto", "zapauzuj…").
  - A step that is running goes on until it ends. Its result, error or question is recorded as usual.
- G2. **While paused:**
  - no run of that epic starts: no next step, no retry, no step queued earlier, and no retry waiting for its time;
  - the director's decisions about a failed step (spec 040) are still made and recorded, but what they start waits;
  - questions can still be answered.
- G3. **Resume.**
  - Ways to resume: the epic's page, the work panel, and the chat action `resume_epic` (on the owner's words).
  - What waited starts. With nothing waiting, the next pending step is queued.
- G4. **The space.** A paused epic still holds its space (spec 037). The epics after it wait, and the reason is shown: "waits for … (paused)".
- G5. **Seen everywhere:**
  - the epic's page, the work panel and the board show "Paused since 16:30". While its step still runs, the label reads "Pausing — the current step finishes first";
  - the director's work list says it is paused by the owner, and that `resume_epic` resumes it.
- G6. **Restarts.** The pause is saved on the epic, so it holds after a restart. A step interrupted by the restart is not started again until the epic is resumed.

**Out of scope**
- Pausing a whole space or everything at once, and a "safe to restart" indicator. The owner chose a single epic.
- Stopping the running step at once: the existing Stop does that.
- Pausing recurring orders: they have their own pause (spec 034).

**Success criteria**
- S1. Pausing an epic whose step 2 is running:
  - step 2 finishes, and its result is shown;
  - step 3 stays pending;
  - the epic shows "Paused".
- S2. After a restart the paused epic still starts nothing. Resume queues step 3.
- S3. A second epic of the same space waits while the first is paused, and starts after the first is resumed and done.
- S4. "wstrzymaj miasto" in the chat pauses the epic with that title. A sentence without such words does not.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `work_items.paused_at` | to create |
| System | `WorkItem#pause!`, `#resume!`, `#paused?` | to create |
| System | scheduler: no claim for a run of a paused epic | to change |
| System | `StepChain.queue_next`, `StepReviewer`: what they start waits | to change |
| System | chat actions `pause_epic`, `resume_epic` | to create |
| System | epic page, work panel, board, director's work list | to change |

## 5. Functional Domain Changes

- **State:** an epic is running or cancelled → it can also be paused (a flag on a planned epic, not a new state, so every rule about planned epics still holds).
- **Rules:**
  - R1. One check, in the scheduler's claim: a queued run of a paused epic is never claimed. Every path (next step, retry, review decision, recovery after a restart) passes through it.
  - R2. Pausing or resuming an epic that is done, cancelled or blocked is refused with the reason. A blocked epic already stands; Try again resumes it.
  - R3. The chat actions need the owner's own words in the latest message (like spec 041). Only the owner's own epics.
  - R4. Cancelling a paused epic works as before.
- **Resilience:** a pause saved while a step runs is read again when the step ends. The next step is never queued in between.
- **Data:** a migration adds `work_items.paused_at` (nullable). Back up production before it.

## 6. Critical Path

1. A test reproduces it: a pause while step 2 runs today still queues step 3.
2. The flag, the claim rule and `queue_next`.
3. Resume.
4. The views and the chat actions.
5. A browser check on demo data, B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | S1, S2 (recovery), S3 | model and scheduler tests | commit | a retry with `retry_at` of a paused epic is not handed over |
| Integration | buttons and actions; S4 | request and runner tests | commit | another user's epic cannot be paused; no words, no action |
| Manual | S1 on the epic page and in the work panel | browser on demo data | release | — |

## 8. Expected Outcome

- **Direct effect:** the owner can hold an epic without losing its plan, also before a restart.
- **Side effects:** a paused epic blocks its space until resumed, so the epics after it wait (the owner's choice).
- **Rollback:** revert the code. The column stays unused.

## 9. Additional Information

- **Rejected alternatives:** a new state "paused". It would have to be added to every rule that reads "planned"; a flag keeps them.
- **Sources and questions:** none open.
- **Implementation (2026-11-22):**
  - `work_items.paused_at` (migration `20261122180000`).
  - `WorkItem#pause!`, `#resume!`, `#pause_label`. The scheduler's claim refuses an `epic_step` run of a paused epic (R1).
  - `StepRetry.hand_over_due` keeps a waiting retry. `StepChain.queue_next` queues no next step of a started paused epic.
  - A paused epic that was never started still starts and queues its first step, which is not claimed; so it holds its space too (G4).
  - Buttons: Pause/Resume on the epic's page and in the work panel (JSON, CSRF header). Labels: "paused" / "pausing".
  - Chat actions `pause_epic` and `resume_epic` need the owner's words.
  - Tests: `pause_epic_test.rb` (6) and `test/integration/pause_epic_test.rb` (3).
  - Browser check on demo data: the panel shows "paused · Resume"; the epic's page "Paused since 17:42"; the next epic "Waits for … and it is paused".
- **Security analysis (B20, after specs 001–048):**
  - A paused epic that blocked (its step failed and the director stopped it) kept its pause, so Try again would have resumed nothing. A block now clears the pause. Fixed with a test.
  - The actions reach only the owner's own epics (404 otherwise) and only change a planned epic.
  - Brakeman 0 warnings.

