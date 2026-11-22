# 016 — Epics start at a time; steps run one after another

Status: **implemented** 2026-11-20 (closed by owner: "Akceptuję, buduj" — Q5–Q7 proposals accepted)
Date: 2026-11-20
Depends on: [010](010-task-execution.md), [012](012-remove-managers.md), [013](013-projects.md), [014](014-spaces.md)

## 1. TL;DR

An epic has one **start time**: the time the user gives, or at once. Its steps no longer get times in the calendar. They run **one after another**: when one finishes, the next starts at once, with the results of the earlier steps. A failed step stops the epic. The calendar shows each epic as a bar from its start to its end. Confirmed by tests with stand-in agents and a real epic with Claude.

## 2. Abstract

**Current state (specs 010–014).**
- The director plans every step at its own time, and each step becomes a calendar task.
- Steps wait for their times, even when the previous step finished long before.
- The calendar shows epics as bars from the first step to the last.

**Need (owner, 2026-11-20).**
- "nie chcę planowania do kalendarza każdego kolejnego taska… chcę wiedzieć, kiedy zaczyna się epika, mój temat"
- "nie chcę, żeby stepy były w czasie, bo chcę, żeby jeden po drugim od razu startował, po co ma czekać?"

**Owner decisions.**
- The start time comes from the user, or the epic starts at once (Q1).
- Each step gets the results of the earlier steps (Q2).
- A failed step stops the epic and blocks it, and "Try again" resumes from that step (Q3).
- The calendar shows a bar from the epic's start to its end (Q4).

## 3. Objective

**Goals**
- G1. **Start time:** an epic has a start time (`starts_at`), taken from the conversation ("start Monday 9:00"), or none, which means at once. It replaces *handle from* (spec 011).
- G2. **Planning ahead:** the director plans an epic as soon as it is added, not at its start. The plan is an ordered list of steps (`title`, `description`, `agent`), with no times and at most 10 steps. Agentaro checks it as before (members only, available agents). The epic becomes *planned*, with its start time.
- G3. **Running in sequence:**
  - at the start time, the first step runs; when a step succeeds, the next one is queued at once;
  - each step runs on its agent's executor like any run (spec 010: own folder, 15-minute limit, at most 2 runs at a time across the app);
  - the steps of one epic never run in parallel.
- G4. **Chained results:** a step's prompt contains its epic, its space (spec 014) and the answers of the earlier steps of the same epic, in order. Long answers are shortened to fit a budget, so the latest ones stay whole.
- G5. **Failure:** a failed, timed-out or skipped step stops the epic. The epic becomes *blocked* with the reason, and the director says so in the chat. "Try again" resumes from the failed step. When planning itself failed, "Try again" plans again, as before.
- G6. **End:** when the last step succeeds, the epic is *done* (Q5) and the chat says so, with a link to the results.
- G7. **Cancel:** no further step starts. A step that is already running finishes, and its answer is kept.
- G8. **Calendar:** each started or planned epic is a bar in the time grid, from its start to its end. A running epic ends at "now"; a planned epic is a short mark at its start. The colour shows the state. Steps are not in the calendar, and the depth switch of spec 013 goes away (Q6).
- G9. **Pages:**
  - the kanban card shows the start time and step progress ("step 2 of 4 running");
  - the epic page lists the steps in order, each with its agent, state, run and answer;
  - breadcrumbs: Spaces › space › epic › step run.

**Out of scope**
- Steps running in parallel; the director reviewing results between steps (feedback loop, later); budgets and stop.

**Success criteria**
- S1. A planned epic with a start time runs its first step at that time; each next step starts within seconds after the previous one succeeds; the epic ends *done*.
- S2. The second step's prompt contains the first step's answer (stand-in test).
- S3. A failing step blocks the epic; no later step runs; "Try again" resumes from that step.
- S4. No step of a new epic appears as a calendar task; the epic's bar spans its start to its end.
- S5. Users see only their own epics, steps and runs (spec 011 S4 still holds).
- S6. A real epic on the host: Claude as director plans 2–3 steps; Claude agents run them back to back and the later step uses the earlier answer.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `epic_steps` (epic, position, title, description, agent, state) | to create |
| Data | `work_items.starts_at` (from `handle_from`), `started_at`, `finished_at` | to change |
| Data | `task_runs.epic_step_id` (step runs belong to a step, not a calendar task) | to change |
| System | `ManagementRunner`: plan without times, at once; `StepChain` (start, next, stop, resume); scheduler starts due epics | to create / to change |
| System | Calendar (epic bars by start and end, no depth switch), board, epic page, step prompts | to change |

## 5. Functional Domain Changes

**Rules**
- R1. One step of an epic at a time. The next step is queued only after the previous one succeeded, and only while the epic is *planned* (or running). A cancelled or blocked epic starts nothing.
- R2. Chained results budget: at most 30 KB of earlier answers, newest whole first; older ones are shortened with a note.
- R3. Agents are read when the step runs (spec 010, R2). An unavailable agent skips the step, which blocks the epic (G5).
- R4. The limits of specs 011 and 012 stay: at most 10 steps per plan, only the user's own members.
- R5. Steps planned before this spec stay as they are: calendar tasks with their runs, visible on the epic page (Q7).

**Resilience:** after a restart, an epic whose step was queued or running continues from that step (spec 010 recovery marks an interrupted run as failed, which blocks the epic; "Try again" resumes).

**Data:** a new table and columns; the migration copies `handle_from` into `starts_at`.

## 6. Critical Path

Data → plan without times, planned at once → chain runner (start, next, stop, resume) with stand-in tests → step prompts with earlier answers → calendar bars, board, epic page → real epic on the host → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | planning, sequence, chained prompt, failure and resume, cancel | `test/models/step_chain_test.rb`, `management_runner_test.rb` | merge | no step runs after a failure or cancel; never two steps of one epic at once |
| Integration | epic page, board, calendar bars, permissions | `test/integration/spaces_test.rb` | merge | other users' steps and runs 404 |
| E2E | Claude epic of 2–3 steps back to back | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** an epic starts when you say and finishes as fast as the agents work; the calendar shows epics, not steps.
- **Measurable effect:** S1–S6 pass.
- **Side effects:** less waiting, and runs come in bursts. The limit of 2 parallel runs (spec 010) still applies.
- **Rollback:** drop the new table and columns; epics fall back to timed steps.

## 9. Additional Information

- **Rejected alternatives:** steps at their own times (the owner: why wait?); independent steps without chained results (owner); continuing after a failed step (owner); only a start mark in the calendar (owner).
- **Technical debt:** the director does not look at results between steps yet (feedback loop).
- **External dependencies:** none.
- **Questions:**
  - Q1. Start of an epic — **a time from the user, or at once** (owner).
  - Q2. Chained results — **yes, the earlier steps' answers** (owner).
  - Q3. A failed step — **stop and block; Try again resumes** (owner).
  - Q4. Calendar — **a bar from start to end** (owner).
  - Q5. When all steps succeed — **the epic becomes *done* automatically, and the chat says so.** (owner accepted the proposal).
  - Q6. The calendar depth switch (spec 013, G9) — **removed, as steps are no longer in the calendar.** (owner accepted the proposal).
  - Q7. Steps planned before this spec — **left as they are (calendar tasks with their runs).** (owner accepted the proposal).

## Owner fix after release (2026-11-20)

- "najwyraźniej director nie widzi postępów pracy agentów… bez sensu": the director's chat prompt (and the verifier's) shows, for every open, planned, running or recently finished epic (last 24 hours), each step's state, agent, duration ("running for 4 min so far", "succeeded in 2 min") and the error of a stopped step, with the instruction to report this progress instead of sending the user to look it up. Titles and states only; results stay on the epic page (spec 013, G3).

## Security analysis (B20), after spec 016

Scope: this spec and specs 001–015.

- **Agents still only propose.** The director's plan is checked as before (members only, available agents, at most 10 steps); steps get no times, so time checks are gone with the times. Agentaro alone queues, stops and resumes steps (tests).
- **Chained results are data.** Earlier answers go into the next step's prompt as text within a 30 KB budget (test). An answer that contains instructions (e.g. from a web page) can now steer the next agent — the same risk as any agent reading the web (F12), now along a chain. Agents still cannot change Agentaro; the effect stays inside the epic's own steps. Noted under F12/F15 for the isolation spec.
- **One step at a time per epic** (R1, test); the global limit of 2 parallel runs (spec 010) still caps the load. Faster chains mean more runs in a short time; budgets (F14) remain open.
- **Separation.** Step runs belong to the user (`user_id`), so other users' step runs are 404 and their epics cannot be resumed (tests).
- **Resilience.** A run interrupted by a restart blocks its epic instead of losing track (test).
- **Regressions in 001–015.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities.
- **Owner change (2026-11-22), G7:**
  - The owner's words: "kazałem anulować", "anuluj to porządnie". A cancelled epic's running step (a local agent looping on its own test) kept working for 30 minutes.
  - Cancelling an epic now also cancels its running step and stops it with all its processes (spec 025's stop, or its saved process group). Its files stay.
  - Test `pause_epic_test.rb`; the G7 test in `step_chain_test.rb` adapted.

