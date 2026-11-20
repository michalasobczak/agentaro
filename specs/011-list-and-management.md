# 011 — Director chat, work list and management

Status: **implemented** 2026-11-19, F14 and F15 open (closed by owner: "Akceptuję, buduj" — Q5 and Q6 proposals accepted)
Date: 2026-11-19
Depends on: [007](007-calendar.md), [009](009-agents.md), [010](010-task-execution.md)

## 1. TL;DR

Every user talks to **one agent only: their director**, in a chat. From the conversation the director keeps the user's **work list**. For each item it picks a **manager**; the manager breaks the item into steps for its **agents** and proposes them; the director reviews and **approves the plan itself**. Approved steps become calendar tasks that run at their time (spec 010). The user sees the list and the calendar, and the team as an org chart. Confirmed by tests with stand-in agents and by a real conversation and plan with Claude on the host.

## 2. Abstract

**Current state.** Users place tasks in the calendar themselves and assign agents (specs 007, 009); agents run them at their time (spec 010).

**Need (owner, 2026-11-19).**
- "chciałbym im dać zadanie za pośrednictwem dyrektora i żeby działali dalej sami"
- "ja im daję zadania na liście, a to dyrektor z kierownikiem to zaplanuje"
- "ja chcę tylko z dyrektorem rozmawiać, nie z kierownikami i pracownikami"

**Owner decisions.**
- Every user has their own list (Q1).
- The director chooses, the manager plans (Q2).
- The user talks to the director in a chat; the list is a view of what the director keeps (Q7).
- **The director approves plans itself** (Q8, replaces Q3 "approval at first").
- Items are taken up at once, or from a date given in the conversation (Q4).

**Approach: agents propose, Agentaro applies.** Director and managers get no tools to change Agentaro. They run like any agent (spec 010), but their prompt asks for an answer in a fixed JSON form.
- Agentaro checks every answer: known ids, the user's own team, times in the future, the limits of spec 007.
- Agentaro then applies it: chat replies, list changes, choice of manager, steps, approval.
- An invalid answer is retried once with the errors; after that the director tells the user in the chat that something failed.

With no human approval, these checks are the only brake until a later spec adds budgets and a stop button. That is why the limits below (Q6) are hard.

**Later specs (owner's direction).**
- Feedback loop — step results go back to the manager and director, follow-up steps, *done*, and reports in the chat; budgets and stop.
- Isolation of agents (F12).
- Memory, then self-improvement.
- Renumbered 2026-11-20: the owner put projects first as spec 012; the rest comes later, without numbers yet.

## 3. Objective

**Goals**
- G1. **Chat with the director** (one conversation per user):
  - the user writes; the director answers within a run (spec 010). The page is a real chat (owner fix after release): bubbles, "writing…" dots, Enter sends, messages sent and received as JSON without reloading; on every other page the same chat floats as a panel on the right that the user opens and hides (owner fix, 2026-11-20);
  - the director sees the conversation (latest 30 messages), the current list and the team.
  - It answers `{"reply": "...", "actions": [...]}`; possible actions: `add_item`, `update_item`, `cancel_item`, `reprioritize`.
  - Agentaro applies valid actions and shows them under the reply ("added to the list: …").
- G2. **Work list** per user (private; Q1), kept by the director:
  - an item has a title, a description, an optional *handle from* date and time, an optional *due* date and a priority (normal / high);
  - states: *new* → *with manager* → *planned* (steps in the calendar) → *done* / *cancelled*; *blocked* when the management cannot continue (the director asks the user in the chat);
  - the user sees the list and each item's history (read-only; changes go through the chat).
- G3. **Team** per user, set up by the user on the team page:
  - one **director**;
  - **managers** under it, each with **members**;
  - candidates are the user's private agents and the shared agents (spec 009);
  - every member has a role text (e.g. "researcher", "writer") that managers read when assigning work.
- G4. **Org chart:** the director, managers and members as a tree (HTML and CSS, no script), with each agent's executor and availability.
- G5. **Director picks a manager.** When an item becomes due, the director runs with the item and the managers with their members' roles.
  - It answers `{"manager": <id>, "note": "..."}` or `{"blocked": "question for the user"}`.
  - A question is posted in the chat.
- G6. **Manager plans.** The manager runs with:
  - the item and the director's note;
  - its members and their roles;
  - the user's busy times for the next 14 days;
  - the rules.
  - It answers `{"steps": [{"title", "description", "agent": <id>, "starts_at", "minutes"}], "summary": "..."}` or `{"blocked": "..."}`.
- G7. **Director reviews and approves** (Q8). The director runs with the item and the manager's plan.
  - It answers `{"approve": true, "note": "..."}` or `{"approve": false, "comment": "..."}`; a rejected plan goes back to the manager, at most 3 times, then *blocked*.
  - An approved plan becomes calendar tasks with their agents, linked to the item, and the director tells the user in the chat ("planned: 3 steps, first on Monday 9:00").
- G8. The item's page shows its history: director's choice and note, plans, reviews, steps with their runs and results (spec 010).
- G9. Director and manager runs are normal runs (spec 010) marked *chat*, *director* or *manager*; every change appears in the audit log and the data changelog.

**Out of scope**
- Step results going back to the management, follow-up steps, automatic *done*, reports (feedback loop spec); budgets and stop (same).
- Talking to managers or members; shared lists or teams; agents changing Agentaro through tools (MCP, see section 9); memory (later spec).

**Success criteria**
- S1. Telling the director in the chat "research X and write a summary by Friday" adds an item with a due date, and the reply says so.
- S2. With stand-in director and manager, the item ends *planned*: valid steps in the calendar, assigned to the manager's members, approved by the director, with a message in the chat.
- S3. Invalid answers (unknown agent, agent outside the manager's team, time in the past, too long, too many steps, not JSON) never change anything; after one retry the director reports the failure in the chat.
- S4. Users never see other users' chats, lists, teams or plans.
- S5. A real run on the host: Claude as director and manager turns a chat message into a planned item.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `chat_messages` (user, author user / director / system, content, applied actions, run) | to create |
| Data | `work_items` (user, title, description, handle_from, due_on, priority, position, state, manager, director note, blocked text, replan count) | to create |
| Data | `team_roles` (user, agent, role director / manager / member, manager it belongs to, role text) | to create |
| Data | `tasks.work_item_id`; `task_runs.purpose` (step / chat / director / manager) and `work_item_id` | to change |
| System | `ManagementRunner` (prompts, JSON parsing and checks, retry, applying actions); scheduler picks up due items | to create |
| System | Pages: director chat, list (read-only) and item history, team with org chart | to create |

## 5. Functional Domain Changes

**Rules**
- R1. Management answers are data, never instructions to Agentaro: only the fields above are read; every id is checked against the user's own list and team, every time against the rules; anything else is ignored.
- R2. Hard limits: at most 10 steps per plan, within 14 days, 3 re-plans per item, 20 list actions per chat reply (Q6).
- R3. One management run per item at a time, and one chat run per user at a time (messages written meanwhile are answered together).
- R4. Director, managers and members must be usable agents (spec 009); otherwise the item is *blocked* and the user is told in the chat (or on the team page when the director itself is unusable).
- R5. Steps are private calendar tasks of the user.
- R6. Prompts contain only the user's own data: their chat, list, team and busy times.
- R7. One agent may hold several roles in the same team, e.g. director and manager (Q5).

**Resilience:** a failed or timed-out management run leaves the item where it was and marks it *blocked*; the director's next chat reply includes it, and "Try again" on the item runs it once more.

**Data:** new tables in the main database; tasks and runs gain links to items.

## 6. Critical Path

Data model → team page and org chart → chat with the director (stand-in tests) → list actions → manager planning and director review with checks → scheduler picks up due items → real conversation and plan on the host → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | answer parsing and checks, actions, states, limits, re-plan | `test/models/management_runner_test.rb`, `work_item_test.rb` | merge | invalid answers change nothing |
| Integration | chat, list, item history, team and org chart, permissions | `test/integration/director_chat_test.rb` | merge | other users' chats and items 404 |
| E2E | Claude as director and manager plans an item from a chat message | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** the owner talks to one director; the work gets planned and scheduled without the owner touching the calendar.
- **Measurable effect:** S1–S5 pass.
- **Side effects:** several runs per item (chat, director, manager, steps) — more subscription use; no human checks plans (Q8), so the limits of R2 and the later budgets matter.
- **Rollback:** drop the new tables and columns.

## 9. Additional Information

- **Rejected alternatives:**
  - A write MCP server for the management. The owner asked "dlaczego nie serwer MCP?". Planning needs one answer, not actions. A token for Agentaro in the environment of agents that can read files and use the web (F12) could be misused, e.g. by a hidden instruction on a web page. JSON also works on every executor, including Ollama and LM Studio. A **read-only** MCP (memory, history) is planned after the isolation of agents.
  - The user approving plans (owner chose the director).
  - Talking to managers (owner: only the director).
- **Technical debt:** planning sees the user's busy times, not other users' load on shared agents.
- **External dependencies:** none new.
- **Questions:**
  - Q1. Whose list — **each user their own** (owner).
  - Q2. Roles — **director chooses, manager plans** (owner).
  - Q3. Approval by the user — replaced by Q8.
  - Q4. When items are picked up — **at once, or from a date given** (owner).
  - Q5. One agent in several roles (e.g. director and manager) — **yes** (owner accepted the proposal).
  - Q6. Limits — **10 steps per plan, 14 days ahead, 3 re-plans, 20 list actions per reply** (owner accepted the proposal).
  - Q7. How the user talks to the management — **chat with the director, list as a view** (owner).
  - Q8. Who approves plans — **the director** (owner).

## Security analysis (B20), after spec 011

Scope: this spec and specs 001–010.

- **Agents propose, Agentaro applies (R1).** Director and manager answers are parsed as JSON. Every id is checked against the user's own list and team, and every time against the rules. All chat actions are checked before any is applied. Tests cover: other users' items unreachable, agents outside the manager's team refused, times in the past, too many steps, beyond 14 days, after the due date. No answer can reach the database or another user.
- **Separation of users (S4).** Chats, lists, items, teams and management runs of other users are 404; team candidates are limited to the user's own and shared agents (tests).
- **Output.** Chat messages, notes and plans are shown as text (test with markup); the data changelog keeps only the size of chat messages.
- **Rate limit.** At most 20 messages to the director per user per 10 minutes, like "Run now" (F13).
- **F14 (medium, open — feedback loop spec).** No budget yet. One chat reply may add 20 items. Each item may cost up to about 10 management runs (choice, plan, 3 re-plans with reviews) and up to 10 steps. With no human approval (Q8), one message can schedule a lot of subscription use. The feedback loop spec brings budgets and a stop button, as the owner planned. Until then, keep requests small.
- **F15 (low, open — isolation spec).** Director and managers run with the same tools as steps (spec 010: files in their folder, web), although they only need to answer. Least privilege calls for no tools in management runs; to be done with the isolation of agents.
- **Regressions in 001–010.** Brakeman: no warnings (the weak F8 is gone since sign-in remembers only page requests). `bundle-audit`: no vulnerabilities. A time-dependent test fixed (pinned to a fixed time).
