# 013 — Projects

Status: **implemented** 2026-11-20, F16 open (closed by owner: "to robimy projekty" after the proposals for Q3–Q7; kanban added: "i zadania mają być w ramach projektów jako tablica kanban"; calendar depth added: "kalendarz to jest dla mnie dla epiców … powinien być przełącznik głębokości widoczności zadań"; Q8, Q11, Q12 answered by the owner, Q9 and Q10 recommended options)
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [012](012-remove-managers.md)

## 1. TL;DR

Every user groups their work into **projects** (e.g. "company X", "house renovation"). A project has a goal — what the user wants to achieve — and holds its own work items, steps and runs. Agents working on a project see only that project, never the others. Confirmed by tests of project separation in prompts and pages, and by a browser walk-through.

## 2. Abstract

**Current state.** Each user has one work list kept by their director (spec 011). Everything the director, managers and members see is drawn from that single list, so knowledge of unrelated matters mixes in every prompt.

**Need (owner, 2026-11-20).** "brakuje nam tutaj projektów … nie mamy jak rozdzielić wiedzy pomiędzy projektami"; "i zadania mają być w ramach projektów jako tablica kanban".

**Owner decisions.**
- Projects are the user's own; shared projects later (Q1).
- The user talks only to the director (spec 011, Q7; confirmed 2026-11-20).
- Memory, when it comes, is **per project** (what the user wants to achieve in it) and **per agent** (what each agent remembers itself); no memory of the user's preferences (owner: "istotne jest co chcę uzyskać na poziomie projektu, i co każdy z agentów sam pamięta"). Memory itself is a later spec.
- Projects come first as spec 012, then 013 after the owner put the removal of managers first (2026-11-20); the feedback loop, isolation of agents, memory and self-improvement follow later. The memory draft (old spec 014) was dropped.

## 3. Objective

**Goals**
- G1. Project per user: name, **goal** (what the user wants to achieve; required), description (optional), state *active* / *archived*.
- G2. Every work item belongs to exactly one project; steps (calendar tasks) and runs inherit it from their item.
- G3. Knowledge separation: a prompt about an item contains that project's goal, description and items only. Steps get the project's name and goal. No director or step prompt about an item ever contains another project's data. The chat (G4) is the only place where projects meet, and there only names, goals and item titles.
- G4. One chat with the director for all projects (Q2). The chat prompt lists the user's active projects (name and goal) and their open items (titles and states) with the project of each; `add_item` names a project, and when the message does not make it clear, the director asks which one instead of guessing.
- G5. Pages: list of projects (with counts per state); project page with its goal and a **kanban board** of its items (Q8–Q10):
  - a card is a work item: title, priority, due date, its steps and their last results;
  - columns are the item states: *New*, *Planned*, *Blocked*, *Done*; cancelled items are folded under the board;
  - cards can be dragged only within a column, to set their order (the order the director sees); states are changed by the director, and by the user with **Done** and **Cancel** on a card (cancel removes steps not started, spec 011);
  - ~~the work list filters by project~~ — **invalidated** by the owner after release ("no need to have epics list i think when i can see projects"): the list page is removed; epics live on their project boards.
- G10. **Breadcrumbs** (owner fix after release): Projects › project › epic › step › run on the project, epic, step and run pages; ordinary calendar tasks have none.
- G8. **Epics.** In the interface the work items are called **epics** (owner's word): the director's units of work; agents' calendar tasks are their **steps**.
- G9. **Calendar depth** (Q11, Q12): a switch *Epics* / *Epics + steps*, remembered per browser session.
  - *Epics* (default): the user's own tasks as before, agents' steps hidden, and each epic with steps as one bar from the start of its first step to the end of its last, in the all-day row (and in the month view), coloured by its state; a click opens the epic;
  - *Epics + steps*: the same, plus all steps as today.
  - Epics without steps (new, blocked before planning) are not in the calendar.
- G6. Projects are created and changed by the user on the projects page, and by the director through chat actions (`add_project`, `update_project`) checked like the other actions (spec 011, R1) (Q3).
- G7. Existing items move into a project "General" created for each user (Q4).

**Out of scope**
- Shared projects (Q1, later); memory (later spec); the feedback loop, budgets, isolation of agents.
- Talking to managers or members directly.

**Success criteria**
- S1. Two projects of one user: no prompt about an item of project A contains anything from project B (test).
- S2. Users never see other users' projects (404).
- S3. A message in the chat creates an item in the right project, or the director asks which one.
- S4. Archived projects get no new items and their items are not taken up.
- S5. The calendar in *Epics* shows no agent steps, only epic bars spanning their steps; *Epics + steps* shows both.
- S6. Cards keep the order set by dragging; Done and Cancel work only on the user's own epics.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `projects` (user, name, goal, description, state) | to create |
| Data | `work_items.project_id` (required; existing items → "General"); `position` orders cards in a column | to change |
| System | Prompts of `ManagementRunner` and `TaskRunner` limited to the item's project | to change |
| System | Projects pages with the kanban board (`kanban.js`, first-party); project filter on the list; project in the item and task pages | to create / to change |
| System | Calendar: depth switch, epic bars | to change |

## 5. Functional Domain Changes

**Rules**
- R1. Project name: 1–60 characters, unique per user; goal 1–2,000 characters; description ≤ 5,000.
- R2. An item may move to another project while it is *new* or *blocked* (Q5), by the director (`update_item` with a project).
- R3. Separation is enforced by Agentaro when building prompts, not by asking the model.
- R4. Archiving a project cancels nothing that already runs; its planned steps stay in the calendar.
- R5. Only an empty project can be deleted; others are archived (Q6). Archived projects can be made active again.
- R6. One team for all projects (Q7).

**Data:** a new table and a required column in the main database; a migration creates "General" per user who has items.

## 6. Critical Path

Projects table and migration → projects pages → items in projects → prompts limited to the project → chat with projects (Q2) → tests → browser walk-through → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | project rules, prompts contain only their project | `test/models/project_test.rb`, `management_runner_test.rb` | merge | another project's text never in a prompt |
| Integration | projects pages, list filter, chat actions, permissions | `test/integration/projects_test.rb` | merge | other users' projects 404 |
| Manual | browser walk-through | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** work and knowledge separated by project.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** shorter prompts (less unrelated context).
- **Rollback:** drop `work_items.project_id` and `projects`.

## 9. Additional Information

- **Rejected alternatives:** a director per project (owner: one director); memory of the user's preferences (owner).
- **Technical debt:** none yet.
- **External dependencies:** none.
- **Questions:**
  - Q1. Whose projects — **own, shared later** (owner).
  - Q2. Chat with several projects — **one chat** (owner, 2026-11-20): the director sees the list of projects (names and goals) and, for each new item, picks the project or asks which one.
  - Q3. Who creates projects — **the user and the director** (owner accepted the proposal).
  - Q4. Existing items — **moved to "General"** (accepted).
  - Q5. Moving an item between projects — **only items not yet planned** (accepted).
  - Q6. Deleting a project — **only when empty; otherwise archive** (accepted).
  - Q7. Team — **one team for all projects** (accepted).
  - Q8. A kanban card is — **an epic** (work item) (owner).
  - Q9. Columns — **the item states** (recommended option).
  - Q10. Dragging — **only to set the order within a column; Done and Cancel buttons on the card** (recommended option).
  - Q11. An epic in the calendar — **a bar from its first step to its last** (owner).
  - Q12. Depth switch — **Epics / Epics + steps** (owner).

## Security analysis (B20), after spec 013

Scope: this spec and specs 001–012.

- **Separation of projects (S1, R3).** Enforced when prompts are built: the plan prompt and step prompts carry only the epic's own project (goal, description, other epics' titles); the chat carries project names, goals and epic titles only. Test with a "confidential" project whose description, epic titles and descriptions never appear in another project's prompts. Busy times in the plan prompt are times only, without titles.
- **Separation of users (S2).** Projects, boards, ordering, Done and Cancel of other users are 404, and ordering refuses other users' epics (tests). The director's project actions reach only the user's own projects, never archived ones (tests).
- **Board.** Ordering changes only positions of epics of one project and one column (tests); Done and Cancel use the same per-user lookups as the epic page. `kanban.js` and the depth switch add no inline script or style (tests); text is rendered escaped.
- **Migration.** SQL, so moving existing epics into "General" is not in the data changelog (spec 004); recorded in the CHANGELOG.
- **F16 (low, open).** The director may add up to 20 projects per reply, and there is no limit on the number of projects. Messages are limited (20 per 10 minutes), so a misbehaving director could still create many projects. Proposal: at most 50 active projects per user, refused in the checks of the chat. To be decided by the owner.
- **Regressions in 001–012.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities. F12, F14, F15 stay open.
