# 010 — Running tasks on agents

Status: **implemented** 2026-11-19, F12 deferred by owner (closed by owner: Q1 "Full tools in own folder", Q2 "Never run late", Q3 "Mark not supported yet", Q4 "2")
Date: 2026-11-19
Depends on: [007](007-calendar.md), [008](008-executors.md), [009](009-agents.md)

## 1. TL;DR

When a calendar task with an agent reaches its start time, Agentaro runs it: it builds a prompt from the agent's master prompt and the task, sends it to the agent's executor (a CLI logged in on the host or a local API) and stores the answer as a **run**. Every occurrence of a recurring task runs once. Runs and their results are visible on the task and marked in the calendar. Confirmed by tests with stand-in programs and servers, and by real runs on the host's tools.

## 2. Abstract

**Current state.** Tasks can be assigned to agents (spec 009); agents point at executors (spec 008), which can be checked but not used.

**Need (owner, 2026-11-19).** "implement execution of tasks via agents (and its executors) according to calendar and schedule".

**Approach.**
- **Scheduler:** a background thread in the app process (like the daily audit pruning, spec 005) looks every 30 seconds for occurrences whose start time has come.
- **Runs:** each occurrence is a row in `task_runs`. A unique key on (task, occurrence start) means a restart or a second process never runs the same occurrence twice.
- **Executors:** CLIs get the prompt on standard input, never on the command line, where other processes could read it. Arguments stay fixed per preset (spec 008, Q3).

## 3. Objective

**Goals**
- G1. Scheduling: at an occurrence's start time, a task with an assigned, usable agent (spec 009, R3) gets a run. Disabled agents or executors produce a run marked *skipped* with the reason.
- G2. Prompt: the agent's master prompt, then the task: title, description, location, start and end in Europe/Warsaw. Stored with the run.
- G3. Execution per preset (fixed arguments, prompt on standard input):
  - Claude Code: `claude -p --output-format text --no-session-persistence --permission-mode acceptEdits [--model M] --settings <sandbox>`; the sandbox setting confines writes and commands to the run folder (and the system temp folders, which Claude's sandbox always allows) and forbids reading Agentaro's `storage/` (Q1, verified on the host);
  - Codex: `codex exec --skip-git-repo-check --sandbox workspace-write --ephemeral --color never -C <run folder> -o <answer file> [-m M] -`; writes confined to the run folder, no network (verified on the host);
  - Ollama CLI: `ollama run <model>`; LM Studio CLI: `lms chat <model> -p` (prompt as argument; LM Studio reads no stdin);
  - Ollama API: `POST /api/chat`; LM Studio / OpenAI-compatible API: `POST /chat/completions`;
  - Gemini CLI, Grok CLI: not supported yet (Q3) — their runs are *skipped* with that reason.
- G4. Each run executes in its own empty working folder (`var/runs/<id>/work`, outside `storage/`), with the minimal environment of spec 008 (R4), a timeout (default 15 minutes) and output limited to 200 KB.
- G5. Run states: queued → running → succeeded / failed / timed out / skipped / missed. Output, errors, exit status, duration and times are stored.
- G6. Visibility: the task page lists its runs (newest first) with state and result; a run page shows the prompt and the full answer; the calendar marks occurrences that ran (ok, failed, running). Runs are visible to whoever may see the task.
- G7. "Run now" on a task (editable by the user): runs the chosen occurrence immediately, once.
- G8. Concurrency: at most 2 runs at the same time (Q4); further runs wait in the queue.
- G9. Missed runs: never run late (Q2). An occurrence is due only within 2 minutes after its start; past occurrences without a run are shown as *missed* (computed, not stored) and can be run by hand.

**Out of scope**
- Memory and context beyond the master prompt (spec 011); self-improvement (spec 012); notifications; agents creating or changing tasks; retries other than "Run now"; tools beyond Q1.

**Success criteria**
- S1. A task assigned to an agent on Claude Code, Codex and Ollama runs at its start time on the owner's Mac and stores the answer.
- S2. Every occurrence of a recurring task runs exactly once, also after a restart.
- S3. A hanging executor is stopped at the timeout; a failing one gives a *failed* run with its error; the app keeps working.
- S4. Users see runs only of tasks they may see; "Run now" only on tasks they may change.
- S5. The prompt never appears in a process's arguments (except LM Studio CLI, Q3), and no Agentaro secret reaches the executor's environment.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `tasks.agent_assigned_at`; `task_runs` (task, occurrence_start, agent and executor names at run time, preset, model, state, trigger scheduled/manual, prompt, output, error, exit_status, started_at, finished_at; unique task + occurrence for scheduled runs) | to create |
| System | `TaskScheduler` (background thread), `TaskRunner` (prompt, execution per preset), executor adapters (CLI, API) | to create |
| System | Task page runs list, run page, "Run now", calendar marks | to change / to create |
| System | `ExecutorCheck` shares process handling with the runner | to change |

## 5. Functional Domain Changes

**Rules**
- R1. A scheduled run is created only for occurrences that start at or after the moment the task got its agent (`tasks.agent_assigned_at`), never for the past (no flood of old runs when an agent is assigned).
- R2. The task and agent are read at run time: an agent changed before the start time is the one that runs.
- R3. Runs are never deleted with the agent; deleting a task deletes its runs.
- R4. Full tools in the agent's own folder (Q1): CLIs may write files and run commands inside the run folder; Ollama and LM Studio answer with text only. Reading outside the folder is not prevented by the tools, except that Claude is denied Agentaro's `storage/`.
- R5. Output is stored as text and shown escaped; it is never executed or rendered as HTML.

**Resilience:** an executor failure fails the run only; the scheduler thread survives errors and logs them; runs left *running* by a crash are marked *failed (interrupted)* at the next start; queued runs are picked up again.

**Data:** a new table in the main database; run output may be large — kept at most 200 KB per run.

## 6. Critical Path

`task_runs` → runner with CLI and API adapters (tested with stand-ins) → scheduler thread → pages (task runs, run, Run now, calendar marks) → real runs on the host → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | prompt building, adapters (fake CLI on PATH, local HTTP server), states, timeout, output limit, scheduler picks the right occurrences once | `test/models/task_run_test.rb`, `task_scheduler_test.rb` | merge | prompt never in argv; no secrets in env; no duplicate runs |
| Integration | runs list and page, Run now, permissions, calendar marks | `test/integration/task_runs_test.rb` | merge | other users' runs 404; read-only users cannot Run now |
| E2E | real runs: Claude Code, Codex, Ollama | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** agents do the work at the scheduled time.
- **Measurable effect:** S1–S5 pass.
- **Side effects:** subscription usage; processes started by the app; output stored in the database.
- **Rollback:** stop the scheduler (setting) and drop `task_runs`.

## 9. Additional Information

- **Rejected alternatives:** Solid Queue or another job system (one more database and process for a few runs a day); cron on the host (outside the app, harder to set up per clone); passing prompts as arguments (visible in the process list, length limits).
- **Technical debt:** the scheduler lives in the web process; with several processes the unique key prevents duplicates, but runs share the process's threads.
- **External dependencies:** the vendors' CLIs and local servers.
- **Questions:**
  - Q1. Tools — **full tools in own folder** (owner).
  - Q2. Missed start — **never run late** (owner).
  - Q3. Gemini CLI, Grok CLI — **not supported yet** (owner).
  - Q4. Parallel runs — **2** (owner).

## Security analysis (B20), after spec 010

Scope: this spec and specs 001–009.

- **Process start.** No shell; fixed arguments per preset; prompt on standard input (test: never in the arguments), except LM Studio CLI (accepted). Minimal environment — no `SECRET_KEY_BASE`, no `AGENTARO_*` (test). Each run in its own folder under `var/runs`; timeout kills the process group (test).
- **Confinement (Q1, verified on the host).** Claude Code: writes and commands sandboxed to the run folder and the system temp folders; Agentaro's `storage/` denied for reading (verified: Read tool, `head`, `ls` all blocked). Codex: `workspace-write` sandbox — writes only in the run folder, no network (verified: a write to the home folder failed).
- **F12 (high, open — owner decision).** Full tools can still *read* outside the run folder: Codex can read Agentaro's `storage/` (databases with other users' private tasks, `secrets.yml`), and both tools can read other files of the macOS account (e.g. other projects, `~/.ssh`). Anyone who can give a task to such an agent — any user with a private agent — can ask it to read those files, so an Agentaro account becomes read access to the host account. Options: (a) only admins may use agents on CLI executors (users get local APIs only); (b) run agents as a separate macOS user without access to the owner's files (strongest; needs host setup); (c) accept for personal use only. **Deferred by the owner** (2026-11-19: "for now, skip this gate resolution"); stays open until decided.
- **F13 (low, fixed).** "Run now" could be repeated without limit, using the subscription. Fix: at most 10 manual runs per user per 10 minutes.
- **Output.** Stored as text (≤ 200 KB), rendered escaped (test with a `<script>` answer); the data changelog keeps only the size of prompts and answers (test).
- **Access.** Runs of other users' private tasks are 404; system-wide runs are visible to all and started only by admins (tests).
- **Technical debt.** `var/runs` folders are kept without retention; the scheduler shares the web process.
- **Regressions in 001–009.** Brakeman: only the known weak F8. `bundle-audit`: no vulnerabilities. Executor checks reuse the new process runner; their tests pass unchanged.
