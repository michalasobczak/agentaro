# 014 — Spaces: project spaces and team spaces

Status: **implemented** 2026-11-20 (closed by owner: "Akceptuję, buduj" — Q4 proposal accepted)
Date: 2026-11-20
Depends on: [013](013-projects.md)

## 1. TL;DR

Projects (spec 013) become **spaces** of two kinds. A **project space** has a goal it works towards. A **team space** has no goal: it describes what it takes care of, and its epics are ongoing duties. Everything else stays as in spec 013: one board per space, knowledge kept per space, one team of agents. Confirmed by tests of both kinds in prompts and pages, and by a browser walk-through.

## 2. Abstract

**Current state (spec 013).** Every epic belongs to a project, and every project must have a goal.

**Need (owner, 2026-11-20).** "to powinno być przestrzenią, czyli space, a nie tylko projektem … przestrzeń zespołowa, przestrzeń projektowa … projekty mają cele, zespoły mają zadania … to tylko kategoryzacja … chodzi o to, że zespół nie musi mieć celu, do którego zmierza".

**Owner decisions.**
- The kind is a category only. Team spaces have no agents of their own: the director and its members serve every space (Q1).
- There are two fixed kinds, project and team, and a space can change its kind (Q2).
- Both kinds have the same kanban board (Q3).

## 3. Objective

**Goals**
- G1. A space has a name, a **kind** (*project* or *team*), a description, and a state (*active* or *archived*).
  - A project space must have a **goal**.
  - A team space has no goal; its description says what it takes care of.
- G2. Spec 013 applies to spaces unchanged:
  - every epic belongs to one space;
  - knowledge is kept per space: an epic's prompts contain only its own space;
  - each space has a kanban board with Done and Cancel;
  - archiving, deleting only empty spaces, and moving epics that are not yet planned work as before;
  - the calendar keeps the epic bars and the depth switch;
  - breadcrumbs start with Spaces.
- G3. Prompts name the kind:
  - project space: name, goal and description;
  - team space: name and "takes care of: <description>".
- G4. Director chat actions:
  - `add_space` (kind, name, goal for a project space, description);
  - `update_space` (also changes the kind; a project space needs a goal);
  - `add_item` and `update_item` name a `space`.
  - When the space of a new epic is unclear, the director asks.
- G5. Pages: "Spaces" in the menu. The list of spaces is grouped by kind, and each card shows a badge with its kind. The form has a kind switch, and the goal field appears only for project spaces.
- G6. Migration: projects become project spaces, except "General", which becomes a team space with no goal (Q4).

**Out of scope**
- Agents of their own per space (Q1); kinds other than project and team; shared spaces.

**Success criteria**
- S1. A team space can be created and used without a goal; a project space cannot be saved without one.
- S2. Prompts about an epic in a team space contain no goal line and nothing from other spaces (test).
- S3. Changing the kind keeps the space's epics and board.
- S4. Spec 013 tests keep passing under the new names (separation, permissions, board, calendar).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `projects` → `spaces` (+ `kind`, `goal` optional); `work_items.project_id` → `space_id` | to change |
| System | `Project` → `Space`; prompts, director actions, pages, routes `/spaces` | to change |
| System | Spec 013 artefacts (board, breadcrumbs, calendar) renamed | to change |

## 5. Functional Domain Changes

**Rules**
- R1. Project space: goal 1–2,000 characters, required. Team space: no goal; when a space becomes a team space, its goal is removed.
- R2. Description ≤ 5,000 characters; the name is unique per user (spec 013, R1).
- R3. The kind changes nothing else: the board, the epics, the archive state and the separation stay.

**Data:** the table and column are renamed by the migration, and `kind` is added. The data changelog (spec 004) keeps old entries under "Project".

## 6. Critical Path

Migration and rename → `Space` with kinds → prompts and director actions → pages and form → tests → browser walk-through → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | kinds and goals, prompts per kind, director actions | `test/models/management_runner_test.rb`, `space_test.rb` | merge | another space's text never in a prompt; project space without a goal refused |
| Integration | spaces pages, kind switch, board, breadcrumbs, permissions | `test/integration/spaces_test.rb` | merge | other users' spaces 404 |
| Manual | browser walk-through | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** ongoing team work and goal-driven projects live side by side, each in its own space.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** URLs change from `/projects` to `/spaces`.
- **Rollback:** a reverse migration renames the tables back; team spaces need a goal again.

## 9. Additional Information

- **Rejected alternatives:** free labels as kinds (the owner chose two fixed kinds); agents of their own per team space (the owner: one team); a different view for team spaces (the owner: the same board).
- **Technical debt:** none.
- **External dependencies:** none.
- **Questions:**
  - Q1. Agents of their own per team space — **no, one team** (owner).
  - Q2. Kinds — **project and team, changeable** (owner).
  - Q3. Board in team spaces — **the same kanban** (owner).
  - Q4. "General" after migration — **a team space with no goal; other projects become project spaces** (owner accepted the proposal).

## Security analysis (B20), after spec 014

Scope: this spec and specs 001–013.

- **Separation of spaces.** Unchanged from spec 013 under the new names; the tests now also cover a team space (no goal line, nothing from another space in the plan or step prompt).
- **Kinds.** The kind is checked against project / team, and the goal is removed from team spaces on every save, so a forged goal never reaches a prompt (tests). Users change only their own spaces (spec 013 tests, renamed).
- **Form without script.** The goal field is hidden by CSS (`:has` on the chosen kind), not by a script; the server decides what is required.
- **Migration.** Tables and columns renamed; "General" becomes a team space by SQL, outside the data changelog (spec 004); tried first on a copy of the owner's data (General: team, 12 epics), the copy deleted.
- **F16 (low, open)** carries over: no limit on the number of spaces.
- **Regressions in 001–013.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities.
