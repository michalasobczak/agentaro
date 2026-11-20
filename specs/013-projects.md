# 013 — Projects

Status: **draft**
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [012](012-remove-managers.md)

## 1. TL;DR

Every user groups their work into **projects** (e.g. "company X", "house renovation"). A project has a goal — what the user wants to achieve — and holds its own work items, steps and runs. Agents working on a project see only that project, never the others. Confirmed by tests of project separation in prompts and pages, and by a browser walk-through.

## 2. Abstract

**Current state.** Each user has one work list kept by their director (spec 011). Everything the director, managers and members see is drawn from that single list, so knowledge of unrelated matters mixes in every prompt.

**Need (owner, 2026-11-20).** "brakuje nam tutaj projektów … nie mamy jak rozdzielić wiedzy pomiędzy projektami".

**Owner decisions.**
- Projects are the user's own; shared projects later (Q1).
- The user talks only to the director (spec 011, Q7; confirmed 2026-11-20).
- Memory, when it comes, is **per project** (what the user wants to achieve in it) and **per agent** (what each agent remembers itself); no memory of the user's preferences (owner: "istotne jest co chcę uzyskać na poziomie projektu, i co każdy z agentów sam pamięta"). Memory itself is a later spec.
- Projects come first as spec 012, then 013 after the owner put the removal of managers first (2026-11-20); the feedback loop, isolation of agents, memory and self-improvement follow later. The memory draft (old spec 014) was dropped.

## 3. Objective

**Goals**
- G1. Project per user: name, **goal** (what the user wants to achieve; required), description (optional), state *active* / *archived*.
- G2. Every work item belongs to exactly one project; steps (calendar tasks) and runs inherit it from their item.
- G3. Knowledge separation: a prompt about an item contains that project's goal, description and items only. Steps get the project's name and goal. No director, manager or step prompt about an item ever contains another project's data. The chat (G4) is the only place where projects meet, and there only names, goals and item titles.
- G4. One chat with the director for all projects (Q2). The chat prompt lists the user's active projects (name and goal) and their open items (titles and states) with the project of each; `add_item` names a project, and when the message does not make it clear, the director asks which one instead of guessing.
- G5. Pages: list of projects, project page with goal, items and their state, history; the work list filters by project.
- G6. Projects are created and changed by the user on the projects page, and by the director through chat actions (`add_project`, `update_project`) checked like the other actions (spec 011, R1). [TO BE DETERMINED] (Q3)
- G7. Existing items move into a project "General" created for each user (Q4).

**Out of scope**
- Shared projects (Q1, later); memory (later spec); the feedback loop, budgets, isolation of agents.
- Talking to managers or members directly.

**Success criteria**
- S1. Two projects of one user: no prompt about an item of project A contains anything from project B (test).
- S2. Users never see other users' projects (404).
- S3. A message in the chat creates an item in the right project, or the director asks which one.
- S4. Archived projects get no new items and their items are not taken up.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `projects` (user, name, goal, description, state) | to create |
| Data | `work_items.project_id` (required; existing items → "General") | to change |
| System | Prompts of `ManagementRunner` and `TaskRunner` limited to the item's project | to change |
| System | Projects pages; project filter on the list; project in the item and task pages | to create / to change |

## 5. Functional Domain Changes

**Rules**
- R1. Project name: 1–60 characters, unique per user; goal 1–2,000 characters; description ≤ 5,000.
- R2. An item's project is fixed when it is added; moving an item to another project: [TO BE DETERMINED] (Q5).
- R3. Separation is enforced by Agentaro when building prompts, not by asking the model.
- R4. Archiving a project cancels nothing that already runs; its planned steps stay in the calendar.
- R5. Deleting a project: [TO BE DETERMINED] (Q6).

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
  - Q3. Who creates projects — the user only, or also the director in the chat. [TO BE DETERMINED]
  - Q4. Existing items — moved to "General". [TO BE DETERMINED]
  - Q5. Moving an item between projects — allowed only for items not yet planned. [TO BE DETERMINED]
  - Q6. Deleting a project — only when empty; otherwise archive. [TO BE DETERMINED]
  - Q7. Team per project (which managers may work on it), or one team for all projects. Proposal: one team for now. [TO BE DETERMINED]
