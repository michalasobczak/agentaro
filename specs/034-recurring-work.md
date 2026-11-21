# 034 — Recurring work: orders that repeat

Status: **closed** 2026-11-21 (the owner accepted the proposals for Q1–Q4); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [007](007-calendar.md), [011](011-list-and-management.md), [016](016-sequential-steps.md), [032](032-automatic-step-retry.md), [033](033-autonomy-slider.md)

## 1. TL;DR

The owner can order work that repeats — "co poniedziałek o 8 przejrzyj backupy", "codziennie rano podsumuj nowe zgłoszenia" — in the chat or on a form. Each time it is due, Agentaro creates a new epic from the order, plans it, runs it and reports the result. Tests and a demo with a short interval confirm it.

## 2. Abstract

- **Current state:**
  - Calendar tasks repeat (daily, weekly on chosen days, monthly; at most 3 months per series, spec 007) and run one agent's prompt (spec 010). They have no steps, no plan and no report in the chat.
  - Epics (specs 013–016) have steps, a plan and a report, but run once.
- **Gap or problem:** routine work with several steps has to be ordered again every time.
- **Rationale:** recurring work is where autonomy (spec 033) and automatic retries (spec 032) pay off most: it should run without the owner.
- **Decision history:** calendar tasks stay as they are (Q4).

## 3. Objective

**Goals**
- G1. **A recurring order** has:
  - a title and a description, like an epic;
  - a space;
  - a schedule: daily, on chosen weekdays, monthly on a day, or every N hours (at least 1 hour), at a time in Europe/Warsaw;
  - an optional end date;
  - a state: active or paused.
- G2. **Ordering it.**
  - In the chat: "Co poniedziałek o 8 przejrzyj backupy w przestrzeni Serwery". The director proposes the action `add_recurring`, checked like other actions (spec 021), and repeats the schedule back in words ("co poniedziałek o 8:00, od 24 listopada").
  - Also `update_recurring`, `pause_recurring`, `resume_recurring` and `cancel_recurring` in the chat.
  - On the space's page, in a **Recurring** card, with a form to add, edit, pause and delete. (Owner fix 2026-11-21: orders are a part of their space; the separate list of all orders and its menu item were removed. The calendar and the director give the overview across spaces.)
- G3. **Each occurrence** is a new epic in the order's space, linked to the order, with the date in its title ("Przegląd backupów — 24.11"). It is planned and run as any epic, at the space's autonomy level (spec 033), with automatic retries (spec 032).
- G4. **Plan reuse** (Q2). The first occurrence is planned by the director. Later occurrences reuse the last plan whose epic succeeded, so routine runs cost no planning call. The owner or the director can ask to plan anew.
- G5. **What earlier runs found.** Each occurrence's steps get the previous occurrence's final answer, at most 2 KiB, as a section `previous_occurrence`, so a report can say what changed.
- G6. **Report.**
  - Each finished occurrence is reported in the chat, short, like any epic.
  - Option per order: **report only when something needs attention** (a failure, a block, or the agent's answer marked as needing attention). Quiet runs then show only on the order's list (Q3).
- G7. **No pile-ups.**
  - If the previous occurrence is still running or blocked, the next one is skipped, with a note on the order.
  - Occurrences missed while Agentaro was off: only the latest one runs, once, after start.
  - At most 20 active orders per user, and at most 48 occurrences per order per day.
- G8. **In the calendar** the next occurrences are shown as entries of the order, read-only; past ones link to their epics.

**Out of scope**
- Changing calendar tasks of spec 007 or moving them into orders (Q4).
- Triggers other than time (a new file, an e-mail, a web hook).

**Success criteria**
- S1. "Co poniedziałek o 8 przejrzyj backupy w Serwery" in the chat creates an active order that shows on the list and in the calendar.
- S2. At the due time an epic is created, planned, run and reported; the second occurrence reuses the plan without a planning call.
- S3. An occurrence that is due while the previous one is still running is skipped with a note.
- S4. A paused order creates nothing; resumed, it continues from the next due time.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `recurring_orders` (user, space, title, description, schedule fields, ends_on, state, report mode, last plan, next_at, last_occurrence) | to create |
| Data | `work_items.recurring_order_id` | to create |
| System | `RecurringOrder#next_occurrence`, scheduler pass creating due epics | to create |
| System | director chat actions `add_recurring` … `cancel_recurring`; orders in the live work list | to change |
| System | planning: reuse the last successful plan | to change |
| System | step prompt: `previous_occurrence` section | to change |
| System | Recurring card on the space page, form; calendar entries | to create |

## 5. Functional Domain Changes

- **State:** one-off epics → orders that create epics on a schedule.
- **Rules:**
  - R1. **Own space only.** An order and its epics belong to the owner's own space; another user's order is 404.
  - R2. **Checked schedule.** The chat action's schedule is validated in code (allowed kinds, at least 1 hour apart, time zone Europe/Warsaw); the director's wording never becomes code.
  - R3. **One at a time per order** (G7).
  - R4. **Archived or deleted space.** Archiving a space pauses its orders; deleting it deletes them with their epics (spec 025).
  - R5. **Cost guard.** Each occurrence counts toward the daily retry cap of spec 032 and the 2-at-a-time run limit.
- **Resilience:** due times are computed from the schedule, not stored as a queue, so a restart misses nothing beyond G7's rule.
- **Data:** one new table and one column; rollback drops them and created epics stay as ordinary epics.

## 6. Critical Path

1. Orders table, schedule computation with tests (month ends, time changes).
2. Scheduler pass creating epics, with G7.
3. Plan reuse and the previous-occurrence section.
4. Chat actions, list, form, calendar.
5. Tests, demo (S1–S4), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | next occurrence for each schedule kind, including 31st of the month and DST changes; G7 limits | `test/models/recurring_order_test.rb` | merge | an interval under 1 hour is refused |
| Integration | S1–S4; chat actions; space archive pauses | `test/integration/recurring_orders_test.rb` | merge | another user's order 404; CSRF; the director cannot create an order without the owner's request |
| E2E | S1–S2 on demo data with a short schedule | browser | release | — |

## 8. Expected Outcome

- **Direct effect:** routine work is ordered once and runs by itself.
- **Measurable effect:** number of occurrences finished without the owner's action.
- **Side effects:** more runs on the subscription; G7 and the caps keep them bounded.
- **Rollback:** pause all orders; drop the table.

## 9. Additional Information

- **Rejected alternatives:**
  - Extending calendar tasks with steps: calendar tasks are single prompts for one agent, and their 3-month series limit fits meetings, not routines.
  - Cron syntax in the UI: unreadable for the owner; the director translates words into the checked schedule instead.
- **Technical debt:** reused plans may go stale when the team changes; a reused plan whose agent is gone is planned anew.
- **Sources and questions:**
  - Q1. Schedules: daily, weekdays, monthly and every N hours (at least 1 hour) — enough? No end by default (proposed), or a maximum like the calendar's 3 months? (Owner, 2026-11-21: as proposed.)
  - Q2. Reuse the last successful plan (proposed), or plan every occurrence anew? (Owner, 2026-11-21: as proposed.)
  - Q3. Report every occurrence in the chat by default, or only when something needs attention? (Owner, 2026-11-21: as proposed — every occurrence by default; "only when something needs attention" is an option per order, G6.)
  - Q4. Leave calendar tasks (spec 007) as they are (proposed), or later turn them into orders? (Owner, 2026-11-21: as proposed.)

## Implementation notes (2026-11-21)

- **Data:** migration `20261121160000`: `recurring_orders` (schedule fields, state, report mode, the last plan to reuse, `next_at`, the last occurrence and a note) and `work_items.recurring_order_id`.
- **Schedules** (`RecurringOrder#next_occurrence`): daily, chosen weekdays, monthly on a day (the last day in shorter months), every N hours (1–168, counted from the start date at the given time). Times are Europe/Warsaw, so a daylight-saving change keeps the local hour (test). `next_at` is recomputed on every schedule change; it is bookkeeping, left out of the data changelog.
- **Occurrences:** the scheduler tick (30 s) runs due orders. The occurrence moves `next_at` past now first, so occurrences missed while Agentaro was off collapse into one. It is skipped with a note when the previous occurrence is still new, planned or blocked, or the space is archived.
- **Plan reuse (G4):** when an occurrence finishes, its steps become the order's plan; the next occurrence starts with them without a planning call, unless an agent of the plan is no longer a usable team member — then the director plans anew. At autonomy level Pytaj (spec 033) the first plan is approved once; reused plans start without a new approval.
- **Previous result (G5):** steps of an occurrence get a `previous_occurrence` prompt section with the last answer of the previous finished occurrence (at most 2 KiB, as data).
- **Report (G6):** "only when something needs attention" leaves out the Done note; blocks, questions and failures are reported as always. An answer marking itself as needing attention is not detected yet.
- **Chat:** `add_recurring`, `update_recurring`, `pause_recurring`, `resume_recurring`, `cancel_recurring`; the director sees the orders with their ids and schedules, and Agentaro says the checked schedule back under the answer.
- **Pages:** a **Recurring** card on each space page with a form for the schedule, Pause, Resume and Remove (the epics stay); every action returns to the space. The calendar shows coming occurrences as dashed, read-only entries that link to the order on its space page.
- **Owner fix (2026-11-21):** the first version also had a **Recurring** menu item with a list of all orders. The owner: orders belong to a space, not a separate place. The menu item and the list were removed; the overview across spaces is the calendar and the director's list.
- **Tests:** `test/models/recurring_order_test.rb` (9), `test/integration/recurring_orders_test.rb` (6).
- **Browser check on demo data** (before the owner fix): an order made on the form for a few minutes later created "Przegląd backupów — 21.11", which the director planned and the step finished, with the Done note in the chat and the plan kept; the week view showed the next occurrence. No horizontal scroll at 719 px.

## Security analysis (B20), after spec 034

- **Schedules from the chat (R2).** The director's action is checked in code: known kinds only, a valid time, weekdays 1–7, a day 1–31, at least 1 hour apart, the owner's own space; invalid ones are refused with the reason (test). Nothing the director writes becomes code or cron syntax.
- **Request.** Orders are created or changed only in the proposal pass that needs the owner's own latest message, like every work-list change.
- **Load and cost.** At most 20 active orders per user; one occurrence at a time per order; missed occurrences collapse into one; steps still go through the 2-at-a-time limit and spec 032's daily retry cap.
- **Access (R1).** Orders, their pages and their spaces are the owner's only (404 for another user's order, test); a form naming another user's space is refused.
- **Prompt content.** The previous occurrence's answer goes in as data, bounded to 2 KiB; titles and schedules are printed through ERB escaping (test with `<b>`).
- **Deletion (R4).** Archiving a space pauses its orders; deleting it deletes them (test). Removing an order keeps its epics.
- **Earlier specs.** Spec 016 chain and spec 032 retries apply to occurrences unchanged; spec 033 levels apply per space; the spec 021 work list and the verifier see the same evidence (the order list sits outside the shared work list). No regressions found.
- **Tools.** Brakeman: 0 warnings. No new gems.

