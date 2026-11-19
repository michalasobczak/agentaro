# 007 — Calendar of tasks

Status: **implemented** 2026-11-19 (closed by owner: Q1 "allow JavaScript", Q2 "calendar either private or system wise", Q3 "series only up to quarter ahead", Q2a "admin", "all other: accept")
Date: 2026-11-19
Depends on: [002](002-authentication-roles.md), [004](004-data-changelog.md), [006](006-responsive-ui.md)

## 1. TL;DR

A full-screen calendar of tasks with day, 4-day, week and month views. Tasks have a title, location and description, last from 1 minute to 4 days, happen once or repeat (shown up to a quarter ahead), and are edited by clicking them or directly on the grid: drag, drop, resize, cut, copy, paste, duplicate. Confirmed by tests of task rules and recurrence and by a browser walk-through of every view and gesture.

## 2. Abstract

**Current state.** Agentaro has accounts, audit log, data changelog and a responsive interface (specs 002–006), but nothing to plan with.

**Need (owner, 2026-11-19).** "I want to have a calendar thing … full width and height view … day view, 4 days view (I want to see Monday, being on Friday), 7 days and full month view … tasks one time, recurring … from 1 minute long up to 4 days … recurring ones up to a quarter ahead … editable by clicking on the task … drag, drop, expand, shrink, cut, copy, duplicate … without person/agent assignment. Only title, location, description. No notifications."

**Constraint.** Direct manipulation (drag, resize, clipboard) needs JavaScript. Until now the app has none (CSP `script-src 'none'`, MANIFESTO). One first-party script, no libraries or CDN, CSP `script-src 'self'`; every action also works through plain forms (Q1).

## 3. Objective

**Goals**
- G1. Calendar page using the full width and height of the window (below the app's navigation), with a toolbar: previous / today / next, a date picker, and view switch.
- G2. Views:
  - **Day** — one day, hours on the vertical axis.
  - **4 days** — four consecutive days starting from the chosen day (on a Friday: Fri, Sat, Sun, Mon).
  - **Week** — Monday to Sunday containing the chosen day.
  - **Month** — weeks Monday–Sunday covering the month; tasks as bars, multi-day tasks span their days.
  - Day / 4 days / week show an all-day row on top and a time grid below; overlapping tasks sit side by side.
- G3. Task fields: title (required), location, description, start, end. Duration from 1 minute to 4 days.
- G4. One-time and recurring tasks. Recurrence: daily, weekly on chosen weekdays, monthly on the same day, every N days/weeks/months; ends on a date or after N times. A series lasts at most 3 months from its first occurrence (Q3).
- G5. Editing: clicking a task opens its form (title, location, description, start, end, recurrence); delete with confirmation.
- G6. Direct manipulation on the time grid and month view:
  - **drag & drop** moves a task (time grid: snaps to 15 minutes; month: to another day, same time);
  - **resize** by dragging the bottom edge (end) — and the top edge (start) — snaps to 15 minutes;
  - **cut / copy / paste**: select a task, Ctrl/⌘+X or C; click an empty slot, Ctrl/⌘+V pastes it there;
  - **duplicate**: button in the task form and Ctrl/⌘+D — copy right after the original *(Q6)*;
  - **create**: click an empty slot (or drag across slots) to start a new task there. The new-task form opens as a popup over the calendar (owner correction, 2026-11-19: "adding task should be in popup overlay rather than separate page"); without the script, the "New task" button opens the form as a page.
- G8. Two calendars: **private** (only the author sees it) and **system-wide** (all users see it; only admins create and change it). Each task belongs to one of them; the views show both, distinguished by color (Q2, Q2a).
- G7. Every change goes through the server, so it appears in the audit log and the data changelog (specs 003, 004).

**Out of scope**
- Assigning people or agents, notifications or reminders, sharing, invitations, time-zone conversion per task, import/export (iCal).

**Success criteria**
- S1. Each view shows the right days (4-day view on a Friday shows Fri–Mon).
- S2. A task shorter than 1 minute or longer than 4 days is rejected with a clear message.
- S3. A recurring task appears on every matching day of its series and nowhere else; a series longer than 3 months is rejected.
- S4. Moving, resizing, cutting, copying, pasting and duplicating work in the browser and are reflected after a reload.
- S5. A user never sees or changes another user's private tasks; system-wide tasks are visible to all users and changed only by admins (Q2, Q2a).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `tasks` (user, calendar private/system, title, location, description, starts_at, ends_at, all_day?, recurrence fields) | to create |
| Data | `task_exceptions` for changed or deleted single occurrences of a series (Q4) | to create |
| System | `Task` model, recurrence expansion, validations | to create |
| System | `CalendarController` (views), `TasksController` (create/update/destroy, JSON for the script) | to create |
| System | `app/assets/javascripts/calendar.js` (first-party, no libraries) | to create |
| System | CSP `script-src 'self'`; MANIFESTO "no JavaScript" rule | to change (Q1) |
| System | Navigation: "Calendar" item | to change |

## 5. Functional Domain Changes

**Rules**
- R1. 1 minute ≤ end − start ≤ 4 days; end after start.
- R2. Times are stored in UTC and shown in the app's time zone (Europe/Warsaw, Q8).
- R3. A recurring series is stored once; occurrences are computed when a view is shown, never stored ahead. The series ends at most 3 months after its first occurrence.
- R4. Changing one occurrence of a series asks: this occurrence only, or the whole series *(Q4)*.
- R5. Snapping: 15 minutes when dragging or resizing; any minute in the form.
- R6. Week starts on Monday.

**Resilience:** if the script fails or is blocked, all views and forms still work; only dragging and the clipboard are unavailable. A failed save puts the task back where it was and shows the error.

**Data:** new tables in the main database; every change recorded by the data changelog.

## 6. Critical Path

Task model and rules → recurrence expansion → views (day, 4 days, week, month) server-rendered → create/edit/delete forms → first-party script: drag, resize, clipboard, duplicate → tests → browser walk-through.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | 0 failures | `bin/rails test` (duration rules, recurrence, view ranges) | commit | 0-minute or 5-day task accepted; occurrence beyond 3 months |
| Integration | 0 failures | `bin/rails test` (CRUD, JSON updates, ownership) | commit | another user's task readable or changeable |
| E2E | every gesture works | browser walk-through at desktop and tablet widths | push | — |

## 8. Expected Outcome

- **Direct effect:** each user plans their tasks in a calendar.
- **Side effects:** the app ships its first JavaScript file.
- **Rollback:** remove the calendar routes, script and tables.

## 9. Additional Information

- **Rejected alternatives:** FullCalendar or similar libraries — large dependency and supply-chain surface for a small app (Rondo E04); a CDN — against on-prem and CSP.
- **Questions:**
  - Q1. Allow one first-party JavaScript file (no libraries, CSP `script-src 'self'`)? — **owner: "allow JavaScript"**
  - Q2. Whose tasks? — **owner: "calendar either private or system wise"**: each task belongs either to its author's private calendar or to the system-wide calendar seen by all users. Open: Q2a below.
  - Q2a. Who may create and change system-wide tasks? — **owner: "admin"**: only admins; other users see them read-only.
  - Q3. "Recurring ones up to a quarter ahead" — **owner: "series only up to quarter ahead"**: a series cannot run longer than 3 months; its last occurrence must fall within 3 months of its first. No "repeat forever".
  - Q4. Editing one occurrence of a recurring task (drag, resize, form): change only that occurrence, or ask "this one / whole series"? *(accepted: ask, like common calendars)*
  - Q5. All-day tasks (no hours, e.g. "trip", 1–4 days)? *(accepted: yes, all-day row on top)*
  - Q6. Duplicate puts the copy where? *(accepted: same time, next day)*
  - Q7. Phones (spec 006): calendar on phones? *(accepted: day view and task form on phones; drag & drop on tablet and desktop)*
  - Q8. Time zone? *(accepted: Europe/Warsaw for everyone)*
  - Q9. Visible hours in the time grid? *(accepted: all 24 h, scrolled to 07:00 on open)*
- **Decision history:** 2026-11-19 owner correction after the first delivery — adding a task opens in a popup overlay on the calendar, not on a separate page. Editing stays a page.
- **Implementation notes (2026-11-19):**
  - Placement without inline styles (CSP): each day column is a CSS grid of 288 five-minute rows and 60 sub-columns; tasks get generated classes (`app/assets/stylesheets/calendar_grid.css`). Overlapping tasks share the width in up to 6 lanes.
  - Gestures: drag to move (15-minute snap, across days; month view: to another day, same time), drag the top or bottom edge to resize, click or drag on an empty slot to create, right-click menus, hover + ⌘/Ctrl C, X, V, D, Delete, Esc. The clipboard survives switching weeks. Recurring tasks ask "this occurrence / whole series".
  - "This occurrence" detaches the occurrence: it is skipped in the series (`task_exceptions`) and a one-time task takes its place. "Whole series" shifts the series by the same days and time of day, weekdays and end date included.
  - Phones: day view, forms and read-only system tasks; no dragging.
- **Results (2026-11-19):** 96 tests. Browser walk-through on a demo instance with separate, deleted databases: week, 4 days (Fri–Mon from a Friday), month and day views; move across days; resize; moving one occurrence of a weekly series via the dialog; copy & paste from the context menu; duplicate (⌘/Ctrl+D); cut & paste by keyboard; open a task by clicking; drag in the month view; phone layout. Found and fixed: unreadable 1–15 minute tasks (one-line layout), precompiled assets hiding new files from development and test (now isolated), HTML instead of JSON for unknown tasks (now JSON 404).
- **Security analysis (B20):** CSP now allows first-party scripts only (no inline, no eval); the script never builds HTML from data (titles via `textContent`); JSON endpoints require the CSRF token (test); ownership and admin-only system tasks enforced server-side (tests); `return_to` limited to calendar paths (test); recurrence expansion bounded (test); every change in the audit log and data changelog. Brakeman unchanged (F8 of spec 005); bundle-audit clean. No findings.
- **Correction delivered (2026-11-19):** new tasks open in a popup (`<dialog>`) over the calendar from an empty-slot click, a drag across slots, the context menu and the "New task" button; the form is sent as JSON and validation errors appear inside the popup; on success the calendar reloads in place. Without the script the button opens the form page. Checked in the browser: prefilled time from a click and from a drag, an error shown in place, creation, Esc and the button. Validation messages now use readable field names ("End must be after the start"). Tests: 98.
