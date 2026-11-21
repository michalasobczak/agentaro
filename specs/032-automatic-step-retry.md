# 032 — Automatic retry of failed steps

Status: **closed** 2026-11-21 (the owner accepted the proposals for Q1–Q4); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [010](010-task-execution.md), [016](016-sequential-steps.md), [021](021-director-sees-step-output.md), [026](026-unread-blink-and-blocked-notices.md)

## 1. TL;DR

A step that fails for a passing reason (time limit, subscription usage limit, network, a crashed tool) is tried again by itself, a few times, with growing pauses, before the epic is blocked. A step that fails for a lasting reason blocks at once, as today. Tests and a demo with a stand-in tool that fails and then succeeds confirm it.

## 2. Abstract

- **Current state:**
  - A failed, timed-out or skipped step blocks its epic at once (spec 016). A system message says so, and spec 026 pops the block up on every page.
  - The owner resumes with **Try again** on the epic, or with "Retry step 2 of …" in the chat (spec 021).
  - Runs have a 30-minute limit. Subscription tools (Claude Code, Codex) sometimes stop with a usage limit that resets at a stated hour.
- **Gap or problem:**
  - Most failures are passing: a limit that resets, a network hiccup, a step that ran out of time halfway.
  - Each one needs the owner to notice and press a button, often at night, so work waits for hours.
- **Rationale:** the owner wants fewer interruptions (spec 033) and work that keeps going without them.
- **Decision history:**
  - Try again and the chat retry stay as they are; this spec adds the automatic path in front of them.
  - Choosing another agent or model after a failure belongs to spec 103.

## 3. Objective

**Goals**
- G1. **Kinds of failure.** Each failed attempt is classified from the run's state and error:

  | Kind | Examples | Retried |
  |---|---|---|
  | `timeout` | the 30-minute limit | yes |
  | `usage_limit` | "usage limit reached", "rate limit", "resets at 3pm", HTTP 429 | yes, after the reset |
  | `transient` | network or DNS errors, HTTP 5xx, "overloaded", the tool crashed with no answer, the local model server unreachable | yes |
  | `lasting` | agent or executor deleted or switched off, working folder missing, the tool not installed or not logged in, the agent's own answer that it cannot do the task | no |
  | `stopped` | cancelled or skipped by the owner or the system | no |

  The patterns are in code, with tests for real messages of Claude Code and Codex. An unknown error counts as `transient` once (Q2).
- G2. **When.** At most 2 automatic retries per step and plan, so 3 attempts in all (Q1):
  - `transient`: after 2 minutes, then after 10 minutes;
  - `timeout`: after 1 minute, once only;
  - `usage_limit`: at the reset time read from the message plus 2 minutes, at most 6 hours ahead; if no time is given, after 30 minutes, then 2 hours.
- G3. **What the retry knows.** The retried step gets a prompt section `retry` (named, spec 030), as data:
  - which attempt it is and why the previous one stopped (kind and the error, at most 300 characters);
  - after a timeout: "the previous attempt ran out of time; deliver the result in smaller parts, the essential part first";
  - in a space with a working folder: "the previous attempt may have changed files; check the current state before you continue".
- G4. **Visible, not noisy.**
  - While a retry waits, the step shows "retrying at 14:05 (attempt 2 of 3) — usage limit", and the epic stays in Running, not Blocked.
  - The work panel (spec 027) and the director's live work list show the same.
  - No chat message and no pop-up for a retry. Only when the last attempt fails does the epic block, with today's message plus "tried 3 times".
- G5. **The owner stays in charge.**
  - Cancelling the epic, moving or replanning it cancels a waiting retry.
  - **Try again** and the chat retry start a fresh count of attempts.
  - A switch in settings turns automatic retries off (on by default, Q4).
- G6. **Daily cap.** At most 20 automatic retries per user per day, so a broken setup cannot burn the subscription. Beyond it, steps block as today and the block says the cap was reached.

**Out of scope**
- Switching to another agent, model or executor after a failure (spec 103).
- Retrying the director's planning or chat answers (they have their own handling).
- Calendar tasks without an epic (spec 010).

**Success criteria**
- S1. A step whose tool fails once with a network error and then succeeds finishes the epic without any action by the owner, and the run history shows both attempts.
- S2. A step that hits "usage limit reached — resets at 3pm" waits until 15:02 and runs again; the epic shows the waiting time.
- S3. A step whose agent was deleted blocks at once, with no retry.
- S4. A step that fails three times blocks the epic with "tried 3 times" and today's pop-up.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `task_runs.failure_kind`, `task_runs.retry_at`, `task_runs.attempt` | to create |
| System | `StepRetry.classify(run)` and `StepRetry.schedule(step, run)` | to create |
| System | `StepChain.after_run`: retry before blocking | to change |
| System | scheduler: start runs whose `retry_at` has come | to change |
| System | step prompt: `retry` section | to change |
| System | epic page, work panel, live work list: waiting retry | to change |
| System | settings: automatic retries on or off | to create |

## 5. Functional Domain Changes

- **State:** failure → blocked becomes failure → classified → waiting retry → running … → blocked only after the last attempt or for a lasting failure.
- **Rules:**
  - R1. **Only the same step, the same plan.** A retry is a new run of the same step, carrying forward the earlier successful answers, like the chat retry (spec 021).
  - R2. **One claim.** A waiting retry, Try again, a chat retry and a cancellation cannot all start the step: the claim is atomic, as in spec 021.
  - R3. **The error is data.** The previous error in the prompt is quoted as data, never as instructions, and is filtered for secrets (spec 030 R2).
  - R4. **No retry of irreversible work.** If the step's previous attempt reported an irreversible action (spec 033), the step blocks instead of repeating it (Q3).
  - R5. **Limits.** Retries count toward the 2-at-a-time run limit; a waiting retry holds no slot.
- **Resilience:** after a restart, waiting retries are read from the database and start when due; a retry missed while the server was down starts at once.
- **Data:** three columns on `task_runs`; rollback removes them and steps block at once again.

## 6. Critical Path

1. Classification with tests on real error texts.
2. Scheduling and the scheduler pass.
3. Retry section in the prompt.
4. Display, settings switch, daily cap.
5. Tests, demo (S1–S4), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | each kind classified from real messages; reset time parsed; backoff and cap | `test/models/step_retry_test.rb` | merge | a lasting failure is never retried; a cancelled epic never retries |
| Integration | S1–S4 with a stand-in tool; Try again resets the count; race of retry and Try again starts one run | `test/integration/step_retry_test.rb` | merge | another user's epic cannot be retried |
| E2E | S1 and S2 on demo data in the browser | browser | release | — |

## 8. Expected Outcome

- **Direct effect:** passing failures no longer stop work or interrupt the owner.
- **Measurable effect:** share of blocks that needed the owner, before and after; time from failure to the epic finishing.
- **Side effects:** a failing step can take up to a few hours longer to report a lasting problem (usage limits).
- **Rollback:** switch retries off; drop the columns.

## 9. Additional Information

- **Rejected alternatives:**
  - Retrying everything blindly: repeats lasting errors and burns the subscription.
  - Leaving it to the director: slower and costs a model call per failure.
- **Technical debt:** the error patterns follow the tools' current messages and need updating when the tools change them.
- **External dependencies:** none.
- **Sources and questions:**
  - Q1. 3 attempts in all (2 automatic retries) and the pauses in G2 — acceptable? (Owner, 2026-11-21: as proposed.)
  - Q2. An error that matches no pattern: retry once (proposed) or block at once? (Owner, 2026-11-21: as proposed.)
  - Q3. Steps in a space with a working folder: retry them too, with the "check the current state" note (proposed), or never retry them automatically? (Owner, 2026-11-21: as proposed.)
  - Q4. Automatic retries on by default, with a switch to turn them off (proposed)? (Owner, 2026-11-21: as proposed.)

## Implementation notes (2026-11-21)

- **Data:** migration `20261121140000`: `task_runs.failure_kind`, `retry_at`, `attempt` (default 1) and an index on state and `retry_at`; `users.auto_retry` (default on).
- **A waiting retry is a queued run** of the same step with trigger `retry`, the next attempt number and `retry_at`. The step stays queued and the epic stays planned (Running on the board), so cancelling, moving and replanning handle it like any queued step: a cancelled epic marks it skipped, and a retired plan makes the worker skip it.
- **Handing over.** Each scheduler tick (30 s) hands due retries to the workers and clears `retry_at`, so a retry is queued once. A worker skips a run whose `retry_at` is still ahead (after a restart all queued runs are recovered). A waiting retry holds no worker (R5).
- **Classification** (`StepRetry.classify`): lasting and passing errors are read from the run's error; a usage limit also from the last 2,000 characters of the answer, where Claude Code reports it. Reset times: a Unix time after `limit reached|`, a clock time ("resets 3pm", "try again at 3:05 PM"; a passed hour means tomorrow), or a duration ("try again in 2 hours 13 minutes"). An interrupted run (Agentaro restarted) is a passing error, so it is retried too.
- **Counting.** Try again and the chat retry start at attempt 1 again (G5). Only runs with trigger `retry` count toward the daily cap.
- **Block messages** add why no retry followed: "Tried 3 times.", "Automatic retries are switched off." or the daily cap.
- **Display:** the step badge on the epic page, the work panel (a `note` field in its JSON) and the director's live work list ("…; Agentaro retries it by itself").
- **Setting:** **Failed steps → Try again by itself** on the Team page (`PATCH /account/auto_retry`).
- **R4** (no retry of irreversible work) waits for spec 033, which defines how a step reports such an action; until then the folder note of G3 applies.
- **Tests:** `test/models/step_retry_test.rb` (11), `test/integration/step_retry_test.rb` (3). The older step-chain tests cover blocking and manual retries with automatic retries switched off.

## Security analysis (B20), after spec 032

- **Injection (R3).** The previous error enters the retried prompt as a quoted, 300-character excerpt labelled as data, after the run-trace secret filter (test with an API-key-like string). It cannot add actions: steps never propose actions.
- **Cost.** At most 3 attempts per step and 20 automatic retries per user per day; lasting errors (login, missing tool, folder, agent) are never retried; usage-limit waits are capped at 6 hours.
- **Concurrency (R2).** A retry starts only through the same atomic claim as every step run (latest attempt, queued step, planned epic). A waiting retry and a cancellation, Try again or replanning cannot both run: tests cover cancel and Try again.
- **Access.** The switch changes only the signed-in user's setting; signed out it is refused (test). Retries are created only for the epic's owner, on the epic's own step and agent.
- **Side effects.** In spaces with a working folder a retry may meet half-done changes; the prompt tells the agent to check the state first. Repeating irreversible actions is covered when spec 033 lands (R4).
- **Earlier specs.** Spec 016 blocking is unchanged when retries are off or exhausted; spec 021 chat retries still need a blocked epic; spec 023 agent status counts only running steps, so a waiting retry does not show an agent as busy; spec 026 notices appear only on a real block; spec 030 traces show the `retry` prompt section. No regressions found.
- **Tools.** Brakeman: 0 warnings. No new gems.

