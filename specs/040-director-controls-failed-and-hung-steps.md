# 040 — The director controls failed and hung steps

Status: **closed** 2026-11-21 (owner: "Zamknij i buduj", proposals in section 9 accepted); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [016](016-sequential-steps.md), [018](018-working-folders.md), [025](025-delete-archived-space.md), [030](030-run-traces.md), [032](032-automatic-step-retry.md), [033](033-autonomy-slider.md), [036](036-parallel-agent-tasks.md), [038](038-live-step-view.md)

## 1. TL;DR

When a step fails, the director decides what comes next instead of a fixed retry rule. It reads the error and the step's log, then retries, retries with changed instructions, replans the rest, asks the owner or stops the epic. The director gives each step its own time limit, from 5 minutes to 4 hours. It sees the processes each running step started, and stops the ones that hang. Every process a step started is stopped when the step ends. Tests with stand-in agents and processes confirm it; a real epic in production confirms the decisions.

## 2. Abstract

- **Current state:**
  - Spec 032 retries a failed step by a fixed rule:
    - a time limit once, after 1 minute;
    - a passing error twice;
    - a usage limit after its reset;
    - the same step and the same instructions each time.
  - Every step has the same time limit, 30 minutes. In the last 3 days, 7 steps hit it at an average of 25.7 minutes' work.
  - When a step ends, Agentaro kills the process group of `claude` or `codex`. Claude Code runs Bash commands in process groups of their own, detached from it. Such a command (a server, a test, a Docker client, a loop) survives the step and nobody cleans it up. Seen on this computer: a shell in a project folder with parent PID 1.
- **Gap or problem:**
  - A blind retry may repeat the same mistake, or undo what the first attempt did; its result is unknown.
  - 30 minutes is too short for research and builds, and too long for a step that hangs.
  - Leftover processes hold ports, files and CPU, and can break the next attempt.
- **Rationale:** the owner wants the director in control ("potrzeba większej kontroli dyrektora nad tym, co agenci robią").
- **Decision history:** the owner chose these options (2026-11-21):
  - the director decides about every failed attempt, usage limits and network errors included;
  - the director sets each step's time limit, 5 minutes to 4 hours, 30 minutes when it gives none;
  - the director may stop tools, but only the ones it knows a step of its project started;
  - the director looks at running steps by itself every few minutes;
  - every process of a step is stopped when the step ends;
  - at **Decyduj** the owner wants only the result: no questions.
  - This replaces spec 032's fixed rule.

## 3. Objective

**Goals**
- G1. **Decision after a failure.** Every attempt that does not succeed (failed, timed out, stopped by a restart) goes to the director. It gets:
  - the step, its attempt number and the time it used against its limit;
  - the error, and the end of the step's log (spec 038);
  - for a usage limit, the reset time.

  It decides one of:
  - **retry** as it was, at once or at a time it gives (for example after a usage-limit reset), optionally with a new time limit;
  - **retry with changes:** new instructions for the step, kept on the step with the reason;
  - **replan** the remaining steps of the epic from this step;
  - **ask the owner**, with its recommendation (spec 033), except at Decyduj;
  - **stop** the epic, which blocks it with the director's reason.

  The decision and its reason appear in the chat (one short line) and on the epic's page.
- G2. **Time limit per step.** The director gives each step a time limit when it plans (5 minutes to 4 hours), and may change it when it retries. A step without one has 30 minutes. The step's page and the live view show the limit and the time used.
- G3. **The step's processes.** Agentaro knows every process a step started, also those in process groups of their own. It shows them in the live view and to the director: the command, how long it has run, CPU. When the step ends, whether it succeeded, failed, ran out of time or was stopped, all of them are stopped, and the step's log says which ones were stopped.
- G4. **Looking at running steps.** Every 5 minutes the director looks at each running step that has a process older than 5 minutes. It may stop any of that step's processes that it judges hung; the step goes on. It may also do it when the owner asks in the chat.
- G5. **Autonomy.**
  - At **Decyduj** the director decides everything itself and never asks.
  - At **Ważne pytaj** it asks only before it stops an epic or replans it.
  - At **Pytaj** it asks before every decision, with its recommendation.

**Out of scope**
- Docker containers started by a step. They keep running and stay a known gap: the owner did not pick them.
- Stopping processes of other projects, of the owner, or of other programs. Only a step's own processes can be stopped (R3).
- Calendar tasks (spec 010), which keep their own fixed limit.

**Success criteria**
- S1. A step that fails with a command error makes the director retry it with changed instructions. The second attempt carries the new instructions and the reason, and the chat shows the decision in one line.
- S2. A step that hits a usage limit with "resets 15:05" is retried after 15:05 by the director's decision, not before.
- S3. The director plans a step with 90 minutes; it runs past 30 minutes and is stopped at 90. A step planned without a limit is stopped at 30. A limit below 5 minutes or above 4 hours is refused.
- S4. A stand-in agent starts a detached process (its own process group, parent gone) and ends. The process is stopped within 10 seconds of the step's end and named in the step's log. A process started outside the step, with the same command, keeps running.
- S5. A step with a process that hangs for 6 minutes: the director's review stops that process, the step goes on and finishes, and the stopped process shows in the log.
- S6. At Decyduj a failing step leads to no question in the chat; at Pytaj every decision is a question with the director's recommendation.
- S7. The director cannot stop a process that is not one of a running step's own, and cannot set a limit outside 5 minutes to 4 hours (refused, nothing done).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | Spec 032's fixed retry rule | to remove (replaced by G1) |
| System | The director's decision run after a failed attempt, and its actions | to create |
| System | Time limit per step, set at planning and at retry | to create |
| System | Tracking a step's processes, stopping them at the end, showing them | to create |
| System | The director's review of running steps every 5 minutes | to create |
| Data | The step's time limit; the decision and its reason; the step's processes while it runs | to create |
| System | Tests: decisions, limits, processes, reviews, autonomy, refusals | to create |

## 5. Functional Domain Changes

- **State:** a fixed retry rule, one 30-minute limit and processes left behind → the director decides, each step has its own limit, and a step leaves no process behind.
- **Rules:**
  - R1. **Bounds of decisions.** At most 5 attempts per step and 20 retries per owner per day. Past them the epic blocks with the reason, as in spec 032. At Decyduj too: it is the result the owner gets.
  - R2. **What the director sees is evidence, not instructions.** The error and the step's log come quoted as the agent's output, as in spec 021. Text in them cannot make the director act, and the director's actions are checked by Agentaro as in spec 033 (R4, R5).
  - R3. **Only a step's own processes.** A process belongs to a step when Agentaro saw it start under the step: a descendant of the step's agent, or carrying the step's marker. It is recognised by its process id together with its start time, so a reused process id is never stopped. Anything else is never listed, never stopped, and a request to stop it is refused.
  - R4. **How a process is stopped.** First a request to end, then a forced stop after 5 seconds. Its own children go with it.
  - R5. **Time limit.** 5 minutes to 4 hours, whole minutes, 30 by default. It is checked when the director gives it; a value outside the range is refused, and the step keeps its old limit.
  - R6. **Changed instructions are visible.** A retry with changes keeps the earlier instructions on the step's page, with the director's reason.
  - R7. **Reviews cost calls.** A running step is reviewed at most once every 5 minutes, and only while it has a process older than 5 minutes. Each review is a director run with its trace (spec 030).
  - R8. **A restart.** A step interrupted by a restart goes to the director like any failed attempt. Processes that a step started before the restart are found by its marker and stopped, unless the step's executor outlived the restart (spec 036, R5).
- **Resilience:**
  - If the director cannot decide (its executor fails, or its answer is not valid), the epic blocks with "the director could not decide" and the error. Nothing is retried blindly.
  - If a process cannot be stopped, the log says so, and the director sees it at its next look.
- **Data:**
  - Migration: the step's time limit and the attempt's decision (what, why, by whom).
  - The list of a running step's processes is kept only while the step runs, and in its log afterwards.
  - Spec 032's automatic-retry setting on the Team page is removed. The director's decisions replace it, and the owner keeps control through the autonomy level.

## 6. Critical Path

1. The owner closes the spec.
2. Process tracking and cleanup (G3, R3, R4, R8), with tests using a stand-in agent that detaches a process.
3. Time limit per step (G2, R5) at planning and at retry.
4. The decision run and its actions (G1, G5, R1, R2, R6), replacing spec 032's rule.
5. The review of running steps and stopping a process (G4, R7).
6. Tests, the B20 analysis, CHANGELOG and README. Restart production while no step runs; watch the first real failure in production.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | R1, R3, R5 | Limits, attempt caps, process ownership by id and start time | Integration | A foreign or reused process listed; a limit outside the range saved |
| Integration | S1–S3, S6, S7 | Stand-in director and agent: each decision, usage-limit timing, autonomy levels | Release | A blind retry; a question at Decyduj; an action outside the rules applied |
| Contract | S4, S5, R4, R8 | Real child processes, detached ones, a hanging one; a restart | Release | A step's process left running; another process stopped |
| E2E | G1, G2, G3 | Epic page and live view: decision, reason, limit, processes; no inline style | Release | — |
| Manual | First real failure in production | Owner reads the decision in the chat | — | — |

## 8. Expected Outcome

- **Direct effect:** a failure gets a reasoned next step. Long work gets the time it needs. No step leaves processes behind.
- **Measurable effect:** zero leftover processes of finished steps. Fewer steps stopped at a limit that was too short.
- **Side effects:**
  - More director calls: one per failed attempt, and one per review of a long-running step every 5 minutes.
  - A decision takes the director's time (seconds to a minute) before the next attempt.
- **Rollback:** fall back to spec 032's fixed rule and the 30-minute limit. The process cleanup can stay on its own.

## 9. Additional Information

- **Rejected alternatives:**
  - The director only for timeouts and unknown errors: the owner wants every failure decided.
  - A stall timer (no activity for N minutes): the owner chose the director's estimate.
  - A space setting for the limit.
  - Docker containers: not chosen. They stay running, a known gap; a later spec may add them.
- **Open:**
  - The 5-minute review interval and the 5-attempt cap are proposals.
  - The removal of the Team page's automatic-retry switch is a proposal.
- **Implementation (2026-11-21):**
  - `ProcessTracker` follows a step's processes every 2 seconds while it runs. It looks down the tree of the agent's process (by parent), into the process groups of its children, and keeps the processes that lost their parent. Each process is kept by its id and start time, in `processes.json` in the run's folder. When the step ends (in `AgentCall`), and after a restart (`TaskScheduler#interrupt!`), every process still alive is asked to end, then forced after 5 seconds, together with its children.
  - `EpicStep#time_limit_minutes` is set from the plan (`"minutes"`) and from the director's retry. `StepChain` passes it as the timeout.
  - `StepReview` and `StepReviewer`: a failed attempt queues a director run (`step_review`), and the director answers retry, change, replan, ask or stop. Agentaro checks the answer and applies it. At Pytaj and Ważne pytaj a decision becomes a question with "Zgoda" first.
  - The scheduler's tick calls `StepReview.review_running_due`. The chat action `stop_process` stops a step's process on the owner's words.
  - Spec 032's `StepRetry.schedule`, its waits and the Team page switch are removed. Its classification, reset times, waiting retries and prompt section stay.
  - New step states: `reviewing` ("director decides") and `replaced`.
  - Tests: `test/models/step_review_test.rb` (15), `test/integration/step_review_test.rb` (3).
  - Tests adapted to the intended change: spec 032's tests (the fixed rule removed), spec 036's retry-folder test, and the director's work line, which now shows the limit.
- **R3 as built:** a process belongs to a step when the poller saw it in the step's tree; there is no environment marker. Known limit: a process whose parent ended before the first look (within 2 seconds) is not seen. Claude Code keeps its commands' parent alive while they run, so in practice they are seen.
- **Security analysis (B20, after specs 001–040):**
  - Brakeman 0 warnings, bundle-audit no vulnerabilities.
  - Stopping is limited to processes the tracker saw under the step, recognised by id and start time, and of the server's own user.
  - Fixed during the analysis: a saved list naming a process of the server's own group (or the server itself) is not obeyed. Test "R3: the tracker never takes Agentaro…".
  - The saved list is written without following links and read only as a regular file. Agents cannot write in the run's folder: their writes are limited to `work/` or the space's folder, and `var/runs` is denied.
  - The director's evidence (error, log, processes) is quoted. Its answer is limited to the decisions and checked:
    - limits 5–240 minutes;
    - retries at most 24 hours ahead and never before a usage-limit reset;
    - new plans with team members only;
    - only the step's own process ids;
    - at most 5 attempts per step and 20 retries a day.
  - A malicious step output can at most steer the director's choice among these, as planning already can.
  - The chat's `stop_process` needs the owner's own words, the owner's own running step and one of that step's processes.
  - Accepted risks:
    - more director calls: one per failure, and one per long-running step every 5 minutes;
    - Docker containers stay a known gap.
