# 012 — Remove managers: the director plans

Status: **implemented** 2026-11-20 (closed by owner: "Akceptuję, buduj" — Q1 proposal accepted)
Date: 2026-11-20
Depends on: [011](011-list-and-management.md)

## 1. TL;DR

Correction of spec 011: the team has only a **director** and **members**. When an item becomes due, the director itself breaks it into steps for the members; Agentaro checks the plan and puts it in the calendar. The choice of a manager, the manager's plan and the director's review disappear. One management run per item instead of about three. Confirmed by tests with stand-in agents and by a real plan with Claude on the host.

## 2. Abstract

**Current state (spec 011).** Each item takes three management runs: the director picks a manager (G5), the manager plans steps for its members (G6), and the director reviews the plan (G7), up to 3 re-plans. The team page builds a three-level tree.

**Need (owner, 2026-11-20).** "po co mi manager w zasadzie? mam dyrektora i memberów, po co dodatkowy poziom złożoności?" and "w 12 daj korektę, żeby zlikwidować managera, to nadmiar struktury".

**What is lost, and why it is acceptable.**
- The director's review of someone else's plan: Agentaro's checks stay (R1 of spec 011: own team, times, limits), and the owner sees every plan in the item's history.
- Specialised planners for large teams: the owner's teams are small; projects (spec 013) will group the work instead.

**What is gained.**
- About a third of the management runs: less subscription use (F14) and faster planning.
- A simpler team page and org chart (two levels).

## 3. Objective

**Goals**
- G1. Team: one director and any number of members directly under it, each with a role text (spec 011, G3). One agent may be both director and member (spec 011, R7).
- G2. Planning: when an item becomes due (spec 011, Q4), the director runs with:
  - the item;
  - the members and their roles;
  - the user's busy times for the next 14 days;
  - the rules.
  - It answers `{"steps": [{"title", "description", "agent": <id>, "starts_at", "minutes"}], "summary": "..."}` or `{"blocked": "question for the user"}`.
- G3. Agentaro checks the plan as before (spec 011: known members only, times in the future, within 14 days, before the due date, at most 10 steps). It then makes calendar tasks for the members, marks the item *planned* and tells the user in the chat ("planned: 3 steps, first on Monday 9:00"). An invalid answer is retried once with the errors, then the item is *blocked* (spec 011).
- G4. Item states: *new* → *planned* → *done* / *cancelled*; *blocked* when planning cannot continue. The state *with manager* is removed.
- G5. Item history shows the director's plan and summary; histories of items planned by managers before this change stay readable.
- G6. Org chart: the director and its members (two levels).
- G7. Migration of existing teams (Q1): members move directly under the director (an agent in two managers' teams stays once, with the first role text); manager roles are removed — the agents stay; open items *with manager* go back to *new*; queued manager and review runs are skipped.

**Out of scope**
- Projects (spec 013); the feedback loop, budgets and stop; isolation of agents (F12, F15).

**Success criteria**
- S1. With a stand-in director, a due item ends *planned* after one management run, with valid steps for the members in the calendar and a message in the chat.
- S2. A plan naming an agent outside the team, a time in the past, beyond 14 days, after the due date or with too many steps changes nothing; after one retry the director's failure is reported in the chat.
- S3. Managers can no longer be added; after migration no team has managers, and members are under the director.
- S4. Users never see other users' teams, plans or runs (spec 011, S4 still holds).
- S5. A real run on the host: Claude as director turns a chat message into a planned item.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `team_roles`: role *manager* and the parent link removed; members belong to the director | to change |
| Data | `work_items.manager_agent_id`, `director_note`, `replan_count`, `review_comment`, `proposed_plan` (the plan is applied at once); state *with_manager* | to remove |
| Data | `task_runs.purpose`: new runs only *step*, *chat*, *director* (plans); old *manager* and *review* runs kept for history | to change |
| System | `ManagementRunner`: pick, manager plan and review replaced by the director's plan | to change |
| System | Team page and org chart; item page; README, MANIFESTO wording | to change |

## 5. Functional Domain Changes

**Rules**
- R1. Spec 011, R1 (agents propose, Agentaro applies) and the limits (10 steps, 14 days, 20 chat actions) stay; the limit of 3 re-plans goes with the review.
- R2. A step may go only to a member of the user's team (the director only if it is also a member).
- R3. One management run per item at a time (spec 011, R3).
- R4. Old runs and plans are never rewritten; only teams and open items are migrated.

**Data:** a migration (Q1) in SQL; its changes to teams and items are not in the data changelog (spec 004), only in this spec and the CHANGELOG. Columns dropped after it.

**Resilience:** unchanged from spec 011 — a failed run blocks the item; "Try again" runs it once more.

## 6. Critical Path

Migration of teams and open items → director plan prompt and checks → team page and org chart → item page → tests → real plan on the host → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | plan parsing and checks, one run per item, states, migration | `test/models/management_runner_test.rb` | merge | invalid plans change nothing; agents outside the team refused |
| Integration | team page without managers, org chart, item history (old and new), permissions | `test/integration/director_chat_test.rb` | merge | other users' items and teams 404 |
| E2E | Claude as director plans an item from a chat message | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** a simpler team and a faster, cheaper path from a chat message to steps in the calendar.
- **Measurable effect:** S1–S5 pass; one management run per item instead of about three.
- **Side effects:** no review of plans by a second agent.
- **Rollback:** restore the spec 011 code and columns from git; teams would have to be rebuilt by hand.

## 9. Additional Information

- **Rejected alternatives:** optional managers (owner: "nadmiar struktury"); the director reviewing its own plan (no second view, one more run).
- **Technical debt:** none new.
- **External dependencies:** none.
- **Questions:**
  - Q1. Existing managers. Proposal: their members move directly under the director (an agent that was a member under two managers stays once, with the first role text); the manager roles are removed — the agents stay in the Agents list and can be added as members. Open items *with manager* go back to *new* and are planned again by the director. **Accepted** (owner).

## Security analysis (B20), after spec 012

Scope: this spec and specs 001–011.

- **Fewer brakes, same checks.** No second agent reviews plans any more; every plan still passes Agentaro's checks before anything is saved (only the user's own members, times in the future, within 14 days, before the due date, at most 10 steps; tests). A director that is not a member cannot give steps to itself (test).
- **F14 (medium, open — feedback loop spec)** is smaller: one management run per item instead of up to about ten (choice, plan, 3 re-plans with reviews). One message can still add 20 items, each with up to 10 steps.
- **Team page.** The form no longer takes a parent; the role is checked against director / member, so a forged "manager" is refused (test). Teams stay per user (S4 tests unchanged).
- **Migration.** Done in SQL, so its changes to teams and items are not in the data changelog (spec 004); recorded here and in the CHANGELOG. Tried on a copy of the owner's data first: the manager role removed, 4 members kept under the director, past runs untouched; the copy was deleted.
- **Old runs.** Manager and review runs left in the queue are skipped and change nothing (test); past ones stay readable.
- **Regressions in 001–011.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities. F12 and F15 stay open (isolation spec).
