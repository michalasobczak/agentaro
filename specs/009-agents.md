# 009 — Agents and task assignment

Status: **implemented** 2026-11-19 (closed by owner: Q1 "Private + shared"; scope: "this spec only agents, assignments and thats all, let execution be next spec, and memory/context next next")
Date: 2026-11-19
Depends on: [007](007-calendar.md), [008](008-executors.md)

## 1. TL;DR

Agents: each has a name, a short description, a **master prompt** (who it is, written by a person) and an **executor** it runs on, with an optional model. Every user has private agents; admins also make shared agents for everyone. A calendar task can be assigned to one agent. Nothing runs yet. Confirmed by tests of the agent rules, permissions and assignment, and by a browser walk-through.

## 2. Abstract

**Current state.** Executors (spec 008) and a calendar of tasks (spec 007) exist; nothing connects them.

**Need (owner, 2026-11-19).** "I wanna create agents with executor as runtime parameter. agent should be assignable to the task. agent by itself should have its own master prompt like a definiton who it is." The owner then split the work: "this spec only agents, assignments and thats all, let execution be next spec, and memory/context next next".

**Plan of the following specs (owner).**
- 010: running a task on its agent's executor.
- 011: the agent's memory and the context it gets ([draft](014-agent-memory.md)); renumbered to 014 when the owner set the roadmap (work list and management first).
- 012: self-improvement, where memory is reorganized on a schedule.

## 3. Objective

**Goals**
- G1. Agent fields:
  - name;
  - description (optional, shown in lists);
  - master prompt (required): who the agent is, written by people only;
  - executor (spec 008);
  - model (optional; overrides the executor's default model);
  - enabled.
- G2. Two kinds, like the calendar (Q1):
  - **private:** created by any user; only that user sees, changes and assigns it;
  - **shared:** created by admins; every user sees it (including its master prompt) and can assign it; only admins change it.
  - Admins do not see other users' private agents.
- G3. Pages: list of my private agents and of shared agents, new, edit, delete with confirmation. Works on phones too (users manage their own agents).
- G4. A calendar task can be assigned to one agent, chosen in the task form (page and popup):
  - private tasks may use my private agents or shared agents;
  - system-wide tasks may use shared agents only;
  - the calendar shows the agent's name on the task, and a recurring task keeps its agent on every occurrence.
- G5. Every change appears in the audit log and the data changelog.

**Out of scope**
- Running tasks (spec 010); memory, context and self-improvement (specs 011, 012); teams of agents; tools and permissions of agents.

**Success criteria**
- S1. A user creates a private agent on an executor and assigns it to a task; the calendar shows it; a recurring task shows it on every occurrence.
- S2. Users cannot see, change or assign other users' private agents (404), nor change shared agents (403); private agents cannot be put on system-wide tasks.
- S3. Disabled agents, and agents whose executor is disabled, are not offered for new assignments and are refused if forged; existing assignments stay and are marked.
- S4. Deleting an agent removes it from its tasks (the tasks stay); an executor used by agents cannot be deleted.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `agents` (user, kind private/shared, name, description, master_prompt, executor, model, enabled) | to create |
| Data | `tasks.agent_id` (optional) | to change |
| System | `Agent` model; `AgentsController`; agent field in the task form, calendar and task pages | to create / to change |
| System | Executor deletion refused while agents use it | to change |
| System | Navigation: "Agents" for everyone | to change |

## 5. Functional Domain Changes

**Rules**
- R1. Name: 1–60 characters, unique among one user's private agents and among shared agents. Description ≤ 500 characters, master prompt 1–20,000 characters, model ≤ 200.
- R2. The kind (private / shared) is fixed when the agent is created; only admins create shared agents.
- R3. Assignment check when a task gets a new agent: the agent is visible to the task's author, enabled, its executor enabled, and shared if the task is system-wide. A task that keeps its agent is not re-checked, so moving or editing it still works after the agent is disabled.
- R4. A task and its agent must stay consistent: a private agent belongs to the task's author and only on a private task (checked on every save, e.g. when an admin makes a task system-wide).
- R5. Deleting an agent unassigns it from its tasks first (recorded in the data changelog).
- R6. Master prompts are not secrets; they are shown to whoever can see the agent.

**Data:** a new table and a nullable column in the main database.

## 6. Critical Path

Agent model and rules → agents pages → task assignment (form, rules, calendar, task page) → executor deletion guard → tests → browser walk-through → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | agent validations, visibility, assignment rules | `test/models/agent_test.rb` | merge | private agent on a system task or another user's task rejected |
| Integration | agents CRUD, assignment through the forms and popup, calendar display, permissions, executor guard | `test/integration/agents_test.rb` | merge | other users' private agents 404, shared agents 403 for users, forged assignment refused |
| Manual | browser walk-through | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** agents with an identity and a runtime, assignable to tasks.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** none; nothing runs yet.
- **Rollback:** drop `agents` and `tasks.agent_id`.

## 9. Additional Information

- **Rejected alternatives:** admins-only agents (owner chose private + shared).
- **Technical debt:** none.
- **External dependencies:** none.
- **Questions:** Q1 who owns agents — **private + shared** (owner).

## Security analysis (B20), after spec 009

Scope: this spec and specs 001–008.

- **Access.** Other users' private agents are 404 for everyone, admins included; shared agents are 403 to change for users (tests). The kind and owner are never taken from the form; only admins create shared agents.
- **Assignment.** A new agent on a task must be in `Agent.assignable` for the user and the task's calendar; forged ids of other users' or disabled agents are refused (test). Private agents can never sit on system-wide tasks, so their names never reach other users (model rule, test).
- **F11 (low, fixed).** Copy, paste and duplicate copied the agent without the R3 check, so a new task could get a disabled agent. Fix: the copy keeps the agent only when it is usable. Test added.
- **Data changelog.** Unassigning tasks when an agent is deleted runs callbacks, so every change is recorded (test); no bulk writes.
- **Master prompts** are not secrets (R6); they appear in the data changelog and, up to 10 KB, in audit bodies.
- **Regressions in 001–008.** Brakeman: only the known weak F8. `bundle-audit`: no vulnerabilities. New pages have no inline styles or scripts (test). An executor in use cannot be deleted (test).
