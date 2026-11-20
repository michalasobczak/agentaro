# 023 — Agent status: busy or free

Status: **draft** (Q1–Q9 open)
Date: 2026-11-20 (agent icons added 2026-11-20, epic "Wdrożyć najnowszą specyfikację ikon agentów w czacie")
Depends on: [011](011-list-and-management.md), [016](016-sequential-steps.md), [020](020-pages-without-reloading.md), [021](021-director-sees-step-output.md)

## 1. TL;DR

Every team member shows whether it is **busy** or **free**. A member is busy while it is running a step of an epic that is still going. Next to the status the user sees the epic and the step, for example `busy · World review · step 2/4: Collect evidence`. The status changes within seconds when a step starts or ends, on the Team page and in the director chat. The result is confirmed by model and integration tests and a browser check during a real epic.

## 2. Abstract

- **Current state:** the Team page (`teams/show`) lists the director, the verifier and the members, with their runtime and a "not available" badge only. Step progress appears on the epic page, on the kanban card ("step N of M running") and in the director's prompt (`ManagementRunner#step_lines`). No page shows what each agent is doing now. The Team page does not refresh by itself. The chat polls `GET /director/messages` every 8 s (0.5 s while the director writes), and pages with `[data-refresh-url]` poll a fingerprint (`ChangeStamp`) every 20 s and then reload through Turbo (spec 020).
- **Gap or problem:** to know whether an agent is working, the user has to open the epics one by one. The user cannot ask the director "who is busy?" with a reliable answer either, because the team part of its prompt (`team_text`) has no status.
- **Rationale:** the owner wants to see at a glance that agents work, and on what, before handing them more work (epic "Status agentów: zajęty / wolny").
- **Decision history:** spec 020 kept polling and left server push (Turbo Streams, Action Cable) out of scope. Spec 016 runs one step at a time per epic, but an agent can still run steps of several epics at once (`config.x.run_workers = 2`). Spec 021 gave the director live step progress per epic. This spec adds the same information per agent.

## 3. Objective

**Goals**
- G1. **One rule for the status**, used everywhere: an agent is busy when at least one of the user's `TaskRun`s with purpose `epic_step` is `running` with that agent (`task_runs.agent_id`), its step is `running`, and its epic is `planned` (running). Otherwise it is free (R1–R6 give the edge cases).
- G2. **The activity next to the status:** the epic title (a link to the epic page) and `step N/M: step title`, where N is the step's place in the active plan and M is the number of steps in it (R7). Busy in several epics: every activity, oldest start first (R5).
- G3. **Team page:** each member row of the org chart and of the Members list shows a status badge (`busy` / `free`) and the activity. The director and verifier nodes show the same if they also hold a member's steps (spec 011, Q5).
- G4. **Director chat** (full page and floating chat): a compact team strip under the chat header lists the members with their status and activity. On a phone it folds into one line ("2 of 4 busy") that opens the list.
- G5. **Live update:** the status changes without reloading the page and without losing form input. Visible pages show the change within 5 seconds of a step's start or end (S2). Hidden pages update on return.
- G6. **The director knows it too:** the team part of the chat and verifier prompts gets the same status per member, so "who is busy?" is answered from data.
- G7. **Agent icons in the chat (added 2026-11-20):** every non-user message in the chat (full page and floating chat, server-rendered and added by `chat.js`) shows the author's icon to the left of the bubble: the director, the verifier, and Agentaro's own notices (`system`). Every member in the team strip (G4) has an icon too. The icon carries a status dot (busy/free, same rule as G1) wherever the agent is a member or holds a member's step (R11).

**Out of scope**
- Server push (Turbo Streams, Action Cable, SSE): the app keeps polling (spec 020).
- Status of the director's or verifier's own chat runs ("writing…" already exists in the chat).
- Steps of legacy calendar epics (`TaskRun` purpose `step` with a `Task` of a work item), and plain calendar tasks: they do not count as busy (Q3).
- History or statistics of busy time, load balancing, and preventing double booking.
- Queued work shown as busy (Q1).

**Success criteria**
- S1. With an epic "World review" running step 2 of 4 ("Collect evidence", Evidence Agent), the Team page and the chat show Evidence Agent as `busy · World review · step 2/4: Collect evidence` and the other members as `free` (integration test).
- S2. When the step's run finishes, and the next step starts with Market Analyst, an open Team page and chat show Evidence Agent free and Market Analyst busy within 5 seconds, with no full page reload, and a half-typed role in the Members form is kept (browser check plus a JS-free endpoint test).
- S3. Each edge case R2–R6 has a model test of `AgentStatus` that names the expected status.
- S4. The status endpoint returns only the signed-in user's agents and runs. Another account's busy agent, including a shared agent, never shows their epic titles (test).
- S5. The director's prompt lists each member with `busy …` or `free` (model test), and the CSP test still passes (no inline style or script; `textContent` only).
- S6. In a conversation with a director, verifier and Agentaro messages, every non-user bubble has the right icon, on first paint, after a poll and after a streamed reply, in both chat views; the team strip shows one icon per member with a busy/free dot that flips together with the label (integration test plus browser check).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `AgentStatus` (new model module): status and activities per agent for one user, plus a fingerprint | to create |
| System | `GET /team/status` (JSON): statuses for the user's team and the fingerprint | to create |
| System | `TeamsController#show` and `teams/show.html.erb`: badges and activities, `data-agent-status` hooks | to change |
| System | `directors/_chat.html.erb`: team strip under the header | to change |
| System | `ChatMessagesController#index`: carries the status fingerprint (and the statuses when it changed) | to change |
| System | `chat.js`: updates the team strip from the poll; `team_status.js` (new, first-party): updates the Team page | to change / to create |
| System | `ManagementRunner#member_line` / `team_text`: status per member in prompts | to change |
| System | `ChangeStamp.agent_status` (or `AgentStatus.stamp`) | to create |
| System | `application.css`: badge and strip styles (no inline `style=`) | to change |
| System | Agent icon (G7, R10–R12): `agent_icon` helper, icon fields in `chat_message_json`, icon in `_chat.html.erb` bubbles and strip, `bubble()` in `chat.js`, `.agent-icon` + tones + status dot in `application.css` | to create / to change |
| Data | `task_runs` (`state`, `purpose`, `agent_id`, `epic_step_id`, `started_at`), `epic_steps.state`, `work_items.state` | exists, unchanged |
| Data | Index `task_runs(user_id, purpose, state)` | [TO BE DETERMINED] (only if the query is slow) |
| Tests | `test/models/agent_status_test.rb`, `test/integration/team_status_test.rb`, additions to `director_chat_test.rb` and `management_runner_test.rb` | to create / to change |

## 5. Functional Domain Changes

**State:** the status is derived from data that already exists. Nothing new is stored. Busy/free → shown on the Team page, in the chat and in prompts. Today there is no per-agent status.

Where a step starts and ends today (the transitions that change the status):

| Transition | Place | Writes |
|---|---|---|
| Step queued | `StepChain.queue_next`, `StepChain.retry_step!` | `EpicStep` → `queued`; new `TaskRun` `queued` |
| **Step starts** | `StepChain#claim_run` (`app/models/step_chain.rb`, the `update!(state: "running")` pair), then `AgentCall#call` sets `started_at`, `agent_name` | `TaskRun` → `running`; `EpicStep` → `running` |
| **Step ends** | `TaskRunner.finish!` (run → `succeeded` / `failed` / `timed_out` / `skipped`), then `StepChain.after_run` (step gets the run's state; the epic may be blocked or done; the next step is queued) | `TaskRun`, `EpicStep`, `WorkItem` |
| Step interrupted by a restart | `Agentaro::TaskScheduler.recover!` | `TaskRun` → `failed` ("Interrupted…"), then `after_run` |
| Epic cancelled | `WorkItem#cancel!` | queued runs → `skipped`, pending/queued steps → `cancelled`, epic → `cancelled`; **a running step is left to finish** |
| Epic moved or replanned | `WorkItem#retire_plan_on_move` | `active_step_from` moves past the old steps |
| Agent deleted | `Agent#unassign_tasks` | `task_runs.agent_id` and `epic_steps.agent_id` → `nil` |

**Rules**
- R1. **Busy:** the run is `running`, purpose `epic_step`, `user_id` is the viewer, `agent_id` is the agent, its `EpicStep` is `running` and in the active plan, and its `WorkItem` is `planned`. The status comes from the run, not from `EpicStep.agent_id`. The run records who really works (spec 016), even if the step is later reassigned.
- R2. **Queued step:** a run waiting for a worker is not work yet. The agent is **free** (Q1).
- R3. **Step failed, timed out, skipped or interrupted:** the moment the run leaves `running` (in `TaskRunner.finish!` or `recover!`), the agent is free. The blocked epic shows no activity for it. A retry (Try again, or `retry_step` from the chat) makes it busy again only when the new run starts.
- R4. **Epic cancelled while a step runs:** the run keeps going until it ends (spec 016, G7), but the epic is no longer running. Proposal (Q2): show **`busy · finishing a step of a cancelled epic`** (epic title, step, and a "cancelled" mark) until the run ends, because the executor really is in use. Then the agent is free. The same applies to an epic marked done by hand while a step runs.
- R5. **Several epics at once:** an agent can run steps of different epics at the same time (two workers). It is busy, with every activity listed, oldest `started_at` first. The chat strip shows the first and "+1 more". One epic never gives two activities, because spec 016 R1 allows one step at a time.
- R6. **Agent without a team role, deleted or disabled:** only members (and the director or verifier when they run steps) are shown. A deleted agent's runs have `agent_id = nil` and count for no one. A disabled agent that still has a running step shows busy, with the existing "not available" badge next to it.
- R7. **Numbering:** N = `position − active_step_from + 1` among the active steps, M = number of active steps. This fits a replanned epic, whose positions do not start at 1. Long titles are cut to 80 characters in the strip (full title in `title=`).
- R8. **Privacy:** statuses are computed per viewer from the viewer's own runs (`task_runs.user_id`). A shared agent busy for another user shows **free** to this user, and nothing of the other user's work leaks. Proposal (Q4): no "busy elsewhere" mark.
- R10. **Icon (G7):** a circle with the agent's first letter, upper case, set with `textContent` (an agent with an empty or non-letter name gets `?`). Colour: one of a fixed palette of 8 classes `.agent-icon.tone-0` … `.tone-7` in `application.css`, chosen as `agent.id % 8`, so an agent keeps its colour on every page and across reloads. The director keeps the existing accent colour (`.is-director`, as in the chat header), the verifier the green of its bubbles (`.is-verifier`), Agentaro's notices a neutral icon with the app mark (`.is-system`). The user's own messages get no icon. Size: 1.8 rem next to bubbles, 1.4 rem in the team strip; the header avatar stays 2.4 rem. Consecutive messages of the same author show the icon only on the first of the run (Q8). The icon has `aria-hidden="true"`; the name in `.bubble-name` stays the accessible label.
- R11. **Status dot on the icon:** a small dot at the bottom right of the icon, `.is-busy` (warning colour, gentle pulse, none under `prefers-reduced-motion`) or `.is-free` (muted). It is shown on member icons in the team strip, and on the director and verifier icons only when they hold a member's step (G3). On message bubbles the icon shows the author's **current** status, not the status when the message was written (Q9). The dot has a `title` with the full label (`busy · World review · step 2/4: Collect evidence`), and the status is also given as text (badge or label), never by colour alone.
- R12. **Without reload:** icons for new messages come from `chat_message_json` (new fields `icon_letter`, `icon_tone` or `icon_kind`) so `chat.js` draws the same icon as the server. Status dots are updated from the same poll as the strip (G5), in place, with no re-render of the bubbles.
- R9. **Rendering:** text is set with `textContent`. Badges and the strip use classes from `application.css`, and the Team page script is a first-party file (AGENTS.md, CSP test). The team strip is marked as information only; it has no actions.

**Resilience**
- Polling can miss a step shorter than the interval. The status then goes straight from free to free, and that is acceptable: the epic page keeps the history.
- If a worker dies without finishing its run, the run stays `running` until the next restart (`recover!`), and the agent shows busy, as the epic page does today. A busy activity therefore shows its elapsed time ("for 12 min"), so a stuck run is visible. Detecting stuck runs is out of scope.
- If the status request fails, the last shown status stays, marked as possibly outdated after 3 failed polls (Q5).
- Two workers finishing at once: the status is read in one query per poll, so it is a consistent snapshot of committed rows.

**Data:** no migration. One query per poll joins `task_runs` (running, `epic_step`, user) to `epic_steps` and `work_items`. An index on `task_runs(user_id, purpose, state)` is added only if needed.

**Where the change events are emitted (the "events")**

There is no push channel, so an event means a committed state change that the next poll sees. The emission points are the existing writes listed in the table above, with no new hooks needed:
1. **Start:** `StepChain#claim_run`, run → `running` (one transaction with step → `running`).
2. **End:** `TaskRunner.finish!` (run leaves `running`), then `StepChain.after_run` (step and epic state, next step queued).
3. **Interrupted:** `TaskScheduler.recover!`.
4. **Cancelled or done by hand:** `WorkItem#cancel!` and `WorkItem#done!`. They change R4's label, not busy/free.
5. **Replan, move or agent deletion:** `retire_plan_on_move`, `Agent#unassign_tasks`.

Each of these writes bumps `updated_at` of `task_runs`, `epic_steps` or `work_items`. `AgentStatus.stamp(user)` is a digest of the busy rows (run id, step id, step state, epic state). The chat poll and `/team/status` compare it with the stamp the client already has and send the statuses only when it changed. If 5 s polling turns out too heavy, an in-memory counter (like `ReplyStream`, process-local: the scheduler runs in the web server) can be bumped at points 1–3 instead. That is an optimisation, not part of the first build (Q6).

## 6. Critical Path

Owner closes the spec (Q1–Q6) → `AgentStatus` with model tests for R1–R8 → `GET /team/status` with the stamp and a privacy test → Team page badges plus `team_status.js` (poll every 5 s while visible) → chat strip plus `chat_messages#index` carrying the stamp and statuses → `member_line` in prompts → CSS → full test suite → browser check with a running epic (S1, S2) → Rondo B20 security analysis over specs 001–023 → CHANGELOG and README.

Completion condition: S1–S5 pass and the B20 analysis has no open finding.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | `AgentStatus` gives busy/free and activities for R1–R8: running, queued, failed, timed out, interrupted, cancelled while running, two epics, replanned numbering, deleted agent | `test/models/agent_status_test.rb` | merge | a queued run, or a run of another user, never makes an agent busy |
| Unit | prompts list `busy …`/`free` per member | `management_runner_test.rb` | merge | another user's epic titles never appear |
| Integration | Team page and chat render the status; `/team/status` and `/director/messages` return statuses and the stamp; the stamp changes on start and end | `team_status_test.rb`, `director_chat_test.rb` | merge | signed out → 401/redirect; no other user's data |
| Integration | every non-user bubble and every strip member has an icon with the right letter and tone class; status dot class matches the status | `director_chat_test.rb` | merge | user bubbles never get an icon; no inline `style=` |
| Contract | JSON shape `{stamp, agents:[{id, status, activities:[{epic_id, epic, step, of, title, cancelled, started_at}]}]}` used by both scripts | integration test | merge | no HTML in JSON fields |
| E2E | — (no browser test suite) | — | — | — |
| Manual | S2: an epic of 2+ steps, Team page and floating chat open, the status flips within 5 s, typed input kept | owner + browser | release | no full page reload during the flip |

## 8. Expected Outcome

- **Direct effect:** the user sees at a glance which agents work and on what, wherever they are, and can ask the director.
- **Measurable effect:** S1–S5 pass, and the status flips within 5 s in the browser check.
- **Side effects:** one more small poll on the Team page (5 s while visible). The chat poll carries a few more bytes when the stamp changes. The chat header takes one line more.
- **Rollback:** remove the strip, the badges, the endpoint and `AgentStatus`. No data changes to undo.

## 9. Additional Information

- **Rejected alternatives:** a stored `agents.status` column updated at each transition (two sources of truth; wrong after a crash; shared agents serve several users); Turbo Streams or Action Cable (out of scope by spec 020); the existing 20 s full-page auto refresh on the Team page (too slow, and blocked by its forms).
- **Technical debt:** the kanban card shows `step position of all steps`, which goes wrong after a replan. Align it with R7 later. Legacy calendar epic steps are not counted (Q3).
- **External dependencies:** none.
- **Sources and questions:**
  - Q1. **Queued step:** free (proposal) or "next: …"? Proposal: free. Optionally a muted "next: World review, step 3/4" without changing the status. [TO BE DETERMINED]
  - Q2. **Cancelled epic with a step still running:** "busy · finishing a step of a cancelled epic" (proposal) or free at once? [TO BE DETERMINED]
  - Q3. **Legacy calendar steps** (`purpose: "step"` runs of a work item's tasks): ignore (proposal) or count as busy? [TO BE DETERMINED]
  - Q4. **Shared agent busy for another user:** free with no mark (proposal, privacy) or a neutral "busy elsewhere"? [TO BE DETERMINED]
  - Q5. **Where in the chat:** a strip under the header (proposal), or only an icon in the header that opens the list? [TO BE DETERMINED]
  - Q7. **Icon look:** first letter on a colour from a fixed palette (proposal), or an image chosen per agent (needs upload, storage and a new column)? [TO BE DETERMINED]
  - Q8. **Repeated messages:** icon on the first message of a run of the same author (proposal) or on every message? [TO BE DETERMINED]
  - Q9. **Status on old messages:** the dot shows the agent's current status (proposal), or no dot on bubbles at all, only in the strip and the header? [TO BE DETERMINED]
  - Q6. **Polling interval:** 5 s on the Team page and the chat's own rhythm (8 s, 0.5 s while writing) for the strip. Is up to 8 s in the chat acceptable, or should it also be 5 s? [TO BE DETERMINED]

## Files to change (implementation map)

| File | Change |
|---|---|
| `app/models/agent_status.rb` (new) | `AgentStatus.for(user)` → `{agent_id => [activities]}` (one query, R1–R8); `AgentStatus.stamp(user)` |
| `app/models/change_stamp.rb` | optionally `agent_status(user)`, delegating to `AgentStatus.stamp` |
| `config/routes.rb` | `resource :team` → add `get :status` |
| `app/controllers/teams_controller.rb` | `@statuses = AgentStatus.for(current_user)`; `status` action (JSON) |
| `app/views/teams/show.html.erb` | badge + activity in the org chart nodes and the Members rows (`data-agent-status="<id>"`), `data-status-url`, `data-status-stamp` |
| `app/helpers/application_helper.rb` | `agent_status_badge(agent, activities)`, `agent_activity_label(activity)`, `agent_status_json(user)` shared by views and JSON |
| `app/views/directors/_chat.html.erb` | team strip under `.chat-head` (`data-team-strip`, `data-status-stamp`), rendered server-side for the first paint |
| `app/controllers/chat_messages_controller.rb` | `index`: add `team_stamp`, and `team` only when the client's `team_stamp` param differs |
| `app/assets/javascripts/chat.js` | in `poll()`: send `team_stamp`, re-render the strip with `textContent` when `data.team` comes |
| `app/assets/javascripts/team_status.js` (new) + layout script tag | Team page: poll `/team/status` every 5 s while visible, via `agentaroOnPage` (spec 020, R1); update badges in place |
| `app/models/management_runner.rb` | `member_line` / `team_text`: append `busy: "<epic>" step N/M "<title>" for X min` or `free` |
| `app/assets/stylesheets/application.css` | `.agent-status`, `.is-busy`, `.is-free`, `.team-strip` (plus mobile fold); `.agent-icon`, `.tone-0`…`.tone-7`, `.is-director`/`.is-verifier`/`.is-system`, `.agent-icon .status-dot`, bubble row layout with the icon |
| `app/helpers/application_helper.rb` (icons) | `agent_icon(agent_or_kind, status: nil, size:)`; `chat_message_json` gains `icon_letter`, `icon_tone`, `icon_kind` |
| `app/views/directors/_chat.html.erb` (icons) | icon before `.bubble` for non-user rows; icon per member in the team strip |
| `app/assets/javascripts/chat.js` (icons) | `bubble()` draws the icon from the JSON fields; status dots updated from the poll |
| `app/models/reply_stream.rb` | unchanged: the streamed bubble is always the director's, so `chat.js` gives it the director icon |
| Emission points (unchanged code, covered by tests) | `StepChain#claim_run` (start), `TaskRunner.finish!` + `StepChain.after_run` (end), `TaskScheduler.recover!` (interrupted), `WorkItem#cancel!` / `#done!` (cancelled or closed), `WorkItem#retire_plan_on_move`, `Agent#unassign_tasks` |
| `test/models/agent_status_test.rb`, `test/integration/team_status_test.rb` (new); `test/integration/director_chat_test.rb`, `test/models/management_runner_test.rb` | gates in §7 |
| `README.md`, `CHANGELOG.md` | spec 023 row and status; entry after implementation |
