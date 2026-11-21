# Agentaro

A private agent system that runs on-prem and works across multiple AI providers — including subscription plans (e.g. Claude, ChatGPT), not just pay-per-token APIs. Vendor-agnostic: no single provider is required.

*Agentaro* is Esperanto for "a group of agents".

Built in public: every prompt used to build it is posted on X. The project follows [Rondo and Context-Driven Development](https://workwithrondo.com/x).

## Intended use

Agentaro is meant for **personal, family or small-business use** with a limited number of users. It is **not** built for enterprise use, and it is **not** meant to run publicly on the internet — only in secured local environments (a home or office network, or a private network between your own devices). Security decisions are sized for that scope.

Agentaro is **not sold** — it is not a commercial product or service. The source is public so others can use it on their own.

## Domain picture

- **Agents** do the work. Each one runs on an AI provider: a subscription-based tool (e.g. Claude Code, Codex CLI) or an API.
- **On-prem:** the system and its data run on the owner's own machine. [TO BE DETERMINED: which machine, container stack]
- **Vendor-agnostic:** providers are interchangeable; switching one should not require changing the rest of the system.
- Everything else — teams of agents, task calendar, interface — is decided in specification sessions.

## Getting started

Requirements: Ruby 4.0.10 (see `.ruby-version`; e.g. `brew install ruby`, rbenv or mise). Nothing else — SQLite is bundled with the `sqlite3` gem and no Docker is needed.

```bash
git clone https://github.com/michalasobczak/agentaro.git
cd agentaro
bin/setup        # installs gems, creates the SQLite databases, starts the server
```

Create the first admin (asks for a password and shows a QR code for Google Authenticator):

```bash
bin/rails agentaro:admin:create
```

Open http://localhost:3000 and sign in. The admin creates further users in the web interface and gives each one a one-time link to set their password — there is no e-mail.

```bash
bin/rails test   # tests
bin/ci           # local CI: setup, tests, seeds
bin/dev          # start the server again later
bin/rails agentaro:admin:password     # change an admin password (command line only)
bin/rails agentaro:admin:reset_totp   # replace an admin's authenticator
bin/rails agentaro:audit:verify       # check the audit log and changelog for tampering
bin/rails agentaro:audit:prune        # remove audit rows older than 3 months (also runs daily by itself)
```

### Running for real use (HTTPS, other devices)

`bin/dev` is for development on this machine only. For real use, run production mode behind a TLS-terminating proxy — for example [Tailscale](https://tailscale.com) with HTTPS certificates enabled. Agentaro listens only on localhost; the proxy is the only way in.

1. Put the hostname you open in the browser into `storage/settings.env` (not in git):
   ```
   AGENTARO_HOSTS=<host>.<tailnet>.ts.net
   ```
2. Create the first admin for production data:
   ```bash
   RAILS_ENV=production bin/rails agentaro:admin:create
   ```
3. Start the app and publish it:
   ```bash
   bin/start
   tailscale serve --bg 3000
   ```

Open `https://<host>.<tailnet>.ts.net` on any device in your tailnet. After updating the code, stop `bin/start` and run it again — it recompiles the stylesheet. `bin/start` sets `AGENTARO_HTTPS_PROXY=1` (Secure cookies, HSTS), shows generic error pages, answers only to `AGENTARO_HOSTS`, and prunes audit data older than 3 months once a day. Any other HTTPS proxy works the same way; Agentaro does not depend on Tailscale.

### Backups

Run folders (files agents wrote) live in `var/runs/<environment>/`. Everything else lives in `storage/`: the databases (development and production), the audit databases, `settings.env` and `secrets.yml` (encryption keys for TOTP secrets — without it every authenticator has to be set up again). Back up the whole folder.

## Functional architecture

Ruby on Rails 8.1 application with SQLite (`storage/`, not committed). No external resources; two small first-party scripts (`app/assets/javascripts/`), no JavaScript libraries. The voice mode's mute behaviour (spec 035) is tested by running `voice()` from `chat.js` in macOS's JavaScriptCore (`jsc`) with fakes (`test/javascript/`); elsewhere those tests are skipped.

- **Spaces and epics (specs 013, 014, 016, 018, 021, 025)** — project spaces have a goal, and team spaces organise ongoing work. Each space has a kanban board (New, Planned, Running, Blocked, Done). Breadcrumbs lead from the board to an epic, its steps and full run answers. A space can give its steps a working folder for editing, commands, Docker and network access. Claude Code applies the folder read restrictions described in spec 018. Codex and Docker have the access limits documented there. **Give Agentaro accounts only to people you trust with the Mac account running it.** Epics are planned when added and start at the scheduled time or immediately. Steps run in order and receive earlier successful answers from the active plan, up to 30 KiB. A stopped step blocks the epic. Use **Try again** on the epic page to resume a failed, timed-out or skipped step. Moving or replanning an epic starts a new plan and keeps prior attempts in its history. The calendar shows the epic as a bar from start to finish. An empty space can be deleted at once. Any other space is archived first, and then **Delete** removes it with its epics, steps, calendar entries and runs, after a confirmation that counts them. Steps still running in it are stopped. Its working folder is never touched.
- **Director and verifier (specs 011, 012, 015, 017, 019, 021, 024, 035)** — talk to the director on the Director page or in the side panel. **New conversation** archives the current chat. Replies stream, and hands-free voice uses local Whisper and Piper. Nobody interrupts (spec 024): while the director or the verifier writes or speaks, what you send waits in the chat, then goes together and gets one answer; voice mode listens after the director has finished. **Mute** in the voice panel (spec 035) pauses the microphone without ending voice mode: nothing is recorded or sent, a recording in progress is thrown away, the director still speaks, and clicking again listens on. When your message asks for a change, the answer you see and hear is the one written with the whole conversation; a separate check decides the change, and what was really done is noted under the answer. The director keeps your work list and plans epics for the members assigned on the Team page. The verifier checks the director's answers and posts its own comments. Both see step progress and quoted excerpts from successful steps in the live work list, including epics finished in the past 24 hours. Excerpts are limited to 1 KiB per step and 10 KiB per epic. Ask what a completed step found while later steps are running, and open its run for the full answer.
- **Automatic retries (spec 032)** — a step stopped by a passing problem is tried again by itself before its epic is blocked: a network or server error after 2 and then 10 minutes, a time limit once after 1 minute, a subscription usage limit at the reset time the tool states (at most 6 hours ahead). An unknown error is retried once; lasting problems (not logged in, missing tool, folder or agent) block at once. At most 3 attempts per step and 20 automatic retries a day. While a retry waits, the step shows "retrying at 14:05 (attempt 2 of 3)" and the epic stays Running, with no chat message or pop-up; only the last failure blocks, saying how many times it was tried. Try again starts a fresh count. Switch it off on the Team page (**Failed steps**).
- **Autonomy slider (spec 033)** — choose how often agents ask you: **Pytaj** (they ask before planning, the plan waits for **Approve plan**, steps stop to ask), **Ważne pytaj** (default: they decide small things and ask about important ones) or **Decyduj** (they never ask and pick their own recommendation). Set it in the chat header, per space on the space form, or tell the director. Sending or publishing outside Agentaro, spending money, deleting outside the run's folder, pushing to a shared repository and anything with passwords or keys are always asked. A step's question shows on the epic page with its options and in the chat; answer with a button, in your own words, or to the director, and the step goes on. What agents assumed is listed on the epic page and in the finished epic's note; **Correct** it and Agentaro remembers the correction for that space.
- **Recurring work (spec 034)** — order work that repeats in the **Recurring** card of a space's page or in the chat ("Co poniedziałek o 8 przejrzyj backupy w Serwery"): every day, on chosen weekdays, monthly on a day, or every N hours (at least 1), from a date and optionally until one. Each time it is due, Agentaro creates a new epic in the space ("Przegląd backupów — 24.11"), plans it, runs it and reports it; later occurrences reuse the last plan that worked and see what the previous one found. If the previous occurrence is still running, the next is skipped with a note; after a break only the latest missed one runs. Report every occurrence or only problems; pause, resume or remove an order at any time (its epics stay). The calendar shows the coming occurrences. At most 20 active orders.
- **Work panel (spec 027)** — on the Director page, to the right of the chat (also in voice mode, when the floating chat takes the chat's place on the left), each active space lists its epics in progress with their steps. Running ones blink, and a space with nothing planned or in progress says so. The panel updates itself every few seconds.
- **Notices (spec 026)** — the closed chat's button blinks while an answer is unread, and the tab title blinks while the tab is in the background. A blocked epic pops up on every page with its reason, **Try again**, **Open epic** and **Close**. Close is remembered on every device until the epic is blocked again. After you allow it once, a block also comes as a macOS notification while the tab is in the background.
- **Page background (spec 028)** — application pages have a subtle background of two soft glows drifting slowly behind the content, in light and dark colours. It is CSS only, never takes clicks, and stays still when the system asks for reduced motion. The chat keeps its own background.
- **Chat background (spec 029)** — the chat header (Director page and side panel) has a **Chat background** selector: Solid (default), Dots, Grid, Gradient or Animated. The choice is saved on your account, so it stays after a reload and on other devices. The pattern is drawn only behind the messages, in light and dark colours; Animated stands still as a gradient when the system asks for reduced motion. Messages waiting to be sent are opaque with a dashed outline. Every label in the chat reads at least 4.5:1 in both palettes, and the header wraps instead of clipping.
- **Brain (spec 031)** — Agentaro remembers what matters, on this Mac only. A local model (`qwen3:8b` in Ollama) reads your messages in the background and keeps short facts: preferences, decisions, constraints and facts about you, your spaces and your agents. A fact about you waits until you keep it, either on the **Brain** page or in the chat's daily list; facts about spaces and agents apply at once. A newer fact replaces an older one, which stays in its history.
  - **In prompts.** The director, the planning and every step get a "remembered context" section: your notes on the Brain page ("about you", per space, per agent) and the facts that fit the task best. Keywords and meaning (`bge-m3`) are combined, within 12 facts.
  - **In the chat.** Say "Zapamiętaj, że…" or "Zapomnij o…".
  - **On the Brain page.** See why each fact exists, edit it (the old version is kept), pin, or delete it for good.
  - **Without Ollama.** Everything works as before, and reading waits.
  - **Settings:** `AGENTARO_BRAIN_URL`, `AGENTARO_BRAIN_MODEL`, `AGENTARO_BRAIN_EMBEDDING_MODEL`.
- **Run traces (spec 030)** — every model call is kept as a trace, on this Mac only:
  - the prompt in named parts, each distinct text stored once;
  - the answer and what the agent did (tool calls and results, each up to 8 KB, marked web, file or command);
  - tokens, cost and time.

  A chat run has two calls (the answer and the check of changes). Secrets that look like keys, tokens or passwords are replaced before storing. Open a run and expand **Trace** (computer or tablet) to see each call. Traces are kept without a time limit (events older than 90 days are compressed) and go with a deleted space. Runs from before traces get one with their whole prompt: `bin/rails agentaro:traces:backfill`.
- **Voice recordings (spec 017)** — send as many recordings as needed. Each clip is transcribed on the host, with a hint of Agentaro's words and your team's names, and saved to the chat as a spoken message. The typed-chat and speech synthesis rates are managed separately.
- **Chat actions (spec 021)** — ask the director in ordinary chat, for example `Add an epic to research backups in General` or `Cancel World review`. The director proposes changes in a separate call using your latest request and work-list metadata. Agentaro checks each action before applying the batch. Send `Retry step 2 of World review` to retry a failed step. Agentaro checks the latest failed attempt, queues it once and carries forward earlier successful answers. The chain continues from there on success.
- **Running tasks (spec 010):** at a task's start time its agent runs it on its executor — Claude Code and Codex with tools confined to the run's own folder, Ollama and LM Studio as text; never late, 30-minute limit. Spec 036: each agent runs up to its own limit of steps at once (epic steps and calendar tasks, in all spaces; default 6, 1–10 on the agent's form); more wait queued and start when a slot frees, also after a failure. Worker threads follow the highest limit plus 2 for the director; both database pools are sized for 10. An agent has no folder of its own: a step works in its space's working folder (steps of one folder in turn, different folders side by side) or, without one, in its run's own folder. Runs and answers are shown on the task and marked in the calendar; "Run now" starts one by hand.
- **Agents (spec 009):** a name, a master prompt (who the agent is, written by people) and the executor it runs on, with an optional model and effort (spec 022). Every user has private agents; admins also make shared agents for everyone. Calendar tasks can be assigned to an agent.
- **Parallel tasks per agent (spec 036):** the agent's form has **Parallel tasks** (`max_parallel_tasks`): how many steps the agent may run at the same time, epic steps and calendar tasks together, over all spaces and accounts. Default 6, whole numbers 1–10; a refused value keeps the old one. A change counts for the next start at once, without a restart: a lowered limit lets running steps finish ("3/2 in progress") and starts no new one until fewer run. When the agent is at its limit a new step waits queued, without holding a worker, and starts when a slot frees (also after a failure, stop or timeout). The director's chat, planning and verification are not counted. Steps of one space working folder still run one at a time.
- **Executors (spec 008):** the AI tools Agentaro can use, managed by admins from built-in presets — command-line tools logged in on this computer (Claude Code, Codex, Gemini CLI, Grok CLI, Ollama, LM Studio) and local APIs that need no key (Ollama, LM Studio, OpenAI-compatible servers). On-demand check: version of the program, or list of models. Users see the list read-only. No keys or tokens are stored; subscriptions are used by logging in on the host (`claude login`, `codex login`).
- **Models and effort (spec 022):** the agent and executor forms offer the models each tool reports — Ollama and LM Studio (what is installed), Codex (its own model cache), Claude Code (`opus`, `sonnet`, `haiku`) — plus names an admin adds, and “Other…” for any name. **Refresh models** on the executor's page reads the list again. **Effort** (Claude Code `--effort`, Codex `model_reasoning_effort`) is chosen from the tool's levels. **Check model** asks the chosen model one short question and shows ✓ with the time or ✗ with the tool's error; one check at a time, 10 per user in 10 minutes. Model names may use letters, digits and `. _ : / @ -` only and never start with `-`.
- **Calendar (spec 007):** day, 4-day, week and month views; one-time and recurring tasks (daily, weekly on chosen days, monthly; at most 3 months per series) from 1 minute to 4 days, all-day tasks; new tasks in a popup over the calendar; drag & drop, resize, cut, copy, paste, duplicate. Private tasks per user and a system-wide calendar that admins maintain. Europe/Warsaw time.
- **Interface (spec 006):** responsive — sidebar layout on desktop and tablet (≥ 640 px), compact top bar on phones; light and dark mode, following the system or chosen with **Auto / Light / Dark** in the sidebar (saved on your account); plain CSS and inline SVG icons. Phones get sign-in, home, own sessions and password; admin tools are for desktop and tablet.

- **Accounts (spec 002):** roles `admin` and `user`; passwords (bcrypt, 12+ characters, common-password list); TOTP (Google Authenticator) — mandatory for admins, switchable per user by an admin; sessions in the database, revoked 7 days after sign-in; one-time password-change links instead of e-mail; admins managed on the command line.
- **Audit log (spec 003):** every HTTP request in `storage/*_audit.sqlite3`, sensitive values filtered, hash-chained, 3-month retention, admin view.
- **Data changelog (spec 004):** every create/update/delete with before/after values, actor and request id, same database and guarantees.

## Critical path

[TO BE DETERMINED]

## State (here and now)

- 2026-11-19: repository set up with CDD artifacts.
- 2026-11-19: blank Rails application (spec 001): Ruby 4.0.10, Rails 8.1.4.1, SQLite, minimal components, no Docker. Tests: 1 (health check). Security analysis: clean.
- 2026-11-19: specs 002–004 implemented — authentication, roles and TOTP; HTTP audit log; data changelog. Tests: 58. Security analysis: spec 005 (2 medium, 3 low findings, fixes proposed).
- 2026-11-19: spec 005 implemented — Secure cookies and HSTS behind the proxy, production mode via `bin/start`, automatic daily audit pruning, equal work on every failed sign-in. Tests: 64. Security round 1 closed.
- 2026-11-19: spec 006 implemented — responsive, designed interface (desktop, tablet, phone). Tests: 69.
- 2026-11-19: spec 007 implemented — calendar of tasks; owner correction: adding a task opens in a popup. Tests: 98.
- 2026-11-19: spec 008 implemented — executors (CLI and local API presets, check, read-only list for users). Tests: 117. Security analysis: F9, F10 fixed.
- 2026-11-19: spec 009 implemented — agents (private and shared) with a master prompt and an executor, assignable to calendar tasks. Tests: 137. Security analysis: F11 fixed.
- 2026-11-19: spec 010 implemented — tasks run on their agents' executors at their time (Claude Code, Codex verified on the host). Tests: 156. Security analysis: F13 fixed, F12 (agents can read files outside their folder) deferred by the owner — until it is decided, give agents on Claude Code or Codex only to people you trust with your Mac account's files.
- 2026-11-19: spec 011 implemented — chat with the director, work list, managers' plans approved by the director, org chart; verified with Claude. Tests: 175. Security analysis: F14 (no budget yet) and F15 (management runs have full tools) open (feedback loop and isolation specs).
- 2026-11-20: the chat with the director floats on every page as a panel on the right, opened and hidden by the user.
- 2026-11-20: roadmap changed by the owner — projects first (spec 012, draft); the memory draft dropped.
- 2026-11-20: spec 012 implemented — managers removed (owner: "nadmiar struktury"); the director plans for its members, one management run per item; verified with Claude. Tests: 180. Projects move to spec 013.
- 2026-11-20: spec 013 implemented — projects with a goal and a kanban board of epics, knowledge kept per project, calendar depth switch (epics / + steps); verified with Claude (it asked which project when unclear). Tests: 189. Security analysis: F16 (no limit on projects) open.
- 2026-11-20: spec 014 drafted — projects become spaces: project spaces (with a goal) and team spaces (no goal), same board.
- 2026-11-20: spec 014 implemented — spaces of two kinds: project (with a goal) and team (no goal); "General" became a team space. Tests: 194.
- 2026-11-20: spec 015 implemented — "New conversation" in the chat header (page and floating chat) archives the current conversation; earlier conversations are readable in the archive. Tests: 197.
- 2026-11-20: spec 016 drafted — an epic starts at a time; its steps run back to back with the earlier results, no times in the calendar.
- 2026-11-20: spec 016 implemented — epics start at a time and run their steps back to back with chained results; failure blocks, Try again resumes; calendar bars from start to end; verified with Claude (2 steps in 22 s). Tests: 206.
- 2026-11-20: spec 017 implemented — the director's replies stream word by word; voice mode: local Whisper transcribes, a local Piper voice speaks, hands-free with silence detection. Tests: 213.
- 2026-11-20: spec 018 drafted — a working folder per space (direct editing, tools and network; no reading other spaces' folders); the verifier moves to 019.
- 2026-11-20: spec 018 implemented — a space may have a working folder; its steps edit, commit, use Docker and the network there, and cannot read other spaces' folders (Claude Code; verified on the host). Tests: 224.
- 2026-11-20: spec 019 drafted — a verifier on demand (Codex checks Claude), comments only, with its own voice.
- 2026-11-20: spec 019 implemented — a verifier on demand (e.g. Codex checking a Claude director) comments in the chat and in voice mode with its own voice; the director reads and answers its comments. Tests: 232.
- 2026-11-20: spec 020 drafted — Turbo, so the floating chat (and voice mode) survives moving between pages.
- 2026-11-20: spec 020 implemented — Turbo: the floating chat and voice mode survive moving between pages; the director sees live step progress. Tests: 239.
- 2026-11-20: spec 021 drafted — bounded step-result excerpts in director and verifier chat, plus a targeted retry of one failed step.
- 2026-11-20: spec 022 implemented — model lists per executor, effort, Check model; model names can no longer pass as options. Tests: 282.
- 2026-11-20: spec 021 implemented and reviewed — the director and verifier see bounded excerpts, and the director can retry one failed step from a clear user request. The review tightened action authority, cancellation, plan isolation and prompt limits. Tests: 262. Q1, Q2 and the configured-model browser gate await review.
- 2026-11-20: spec 023 implemented (on the admin's order, Q1–Q9 proposals) — busy/free per agent on the Team page, in a chat team strip and in prompts, live without reload; agent icons with status dots next to chat messages. Tests: 310.
- 2026-11-20: spec 021 updated — ordinary chat requests can order work or change a space. Agentaro checks a fresh proposal that excludes step evidence and earlier chat replies. Tests: 284.
- Next: later, without numbers yet: feedback loop (results back to the director, budgets, stop), isolation of agents (F12, F15), memory (per space and per agent), self-improvement.

## Specifications

| No. | Title | Status |
|---|---|---|
| 001 | [Initial project structure](specs/001-initial-structure.md) | implemented |
| 002 | [Authentication, roles and TOTP](specs/002-authentication-roles.md) | implemented |
| 003 | [HTTP audit log](specs/003-http-audit-log.md) | implemented |
| 004 | [Data changelog](specs/004-data-changelog.md) | implemented |
| 005 | [Security analysis, round 1](specs/005-security-round-1.md) | implemented |
| 006 | [Responsive layout and visual design](specs/006-responsive-ui.md) | implemented |
| 007 | [Calendar of tasks](specs/007-calendar.md) | implemented |
| 008 | [Executors](specs/008-executors.md) | implemented |
| 009 | [Agents and task assignment](specs/009-agents.md) | implemented |
| 010 | [Running tasks on agents](specs/010-task-execution.md) | implemented (F12 deferred) |
| 011 | [Director chat, work list and management](specs/011-list-and-management.md) | implemented (F14, F15 open); managers invalidated by 012 |
| 012 | [Remove managers: the director plans](specs/012-remove-managers.md) | implemented |
| 013 | [Projects, kanban and calendar depth](specs/013-projects.md) | implemented (F16 open); projects renamed to spaces by 014 |
| 014 | [Spaces: project spaces and team spaces](specs/014-spaces.md) | implemented |
| 015 | [New conversation with the director](specs/015-new-conversation.md) | implemented |
| 016 | [Epics start at a time; steps run one after another](specs/016-sequential-steps.md) | implemented |
| 017 | [Talking to the director: voice and streamed answers](specs/017-voice-and-streaming.md) | implemented; 241 consecutive recordings verified in integration (microphone walkthrough pending) |
| 018 | [A working folder for a space](specs/018-working-folders.md) | implemented (F17, F18 accepted) |
| 019 | [A verifier in the chat](specs/019-verifier.md) | implemented |
| 020 | [Pages without reloading: the conversation keeps going](specs/020-pages-without-reloading.md) | implemented |
| 021 | [Director sees the output of each step](specs/021-director-sees-step-output.md) | implemented, including plain chat ordering (Q1, Q2 and configured-model browser gate open) |
| 022 | [Model lists, effort and a "Check model" button](specs/022-model-lists-and-check.md) | implemented |
| 023 | [Agent status: busy or free](specs/023-agent-status.md) | implemented with Q1–Q9 proposals, owner confirmation pending. Browser release gate failed on chat timing. Space scope [TO BE DETERMINED] |
| 024 | [Conversation fixes](specs/024-conversation-fixes.md) | implemented (owner's decisions Q1–Q6) |
| 025 | [Delete an archived space](specs/025-delete-archived-space.md) | implemented (owner's decisions Q1–Q3) |
| 026 | [Unread chat blinks; blocked epics pop up](specs/026-unread-blink-and-blocked-notices.md) | implemented (owner's decisions Q1–Q3) |
| 027 | [Work panel beside the director chat](specs/027-work-panel-beside-chat.md) | implemented (owner's decisions Q1–Q3) |
| 028 | [Animated page background](specs/028-animated-page-background.md) | implemented with proposed defaults (Q1, Q2 awaiting owner) |
| 029 | [Chat background patterns](specs/029-chat-background-patterns.md) | implemented with proposed defaults (Q1, Q2 awaiting owner; release-gate failures fixed) |
| 030 | [Run traces](specs/030-run-traces.md) | implemented |
| 031 | [Brain: long-term memory](specs/031-brain-memory.md) | implemented |
| 032 | [Automatic retry of failed steps](specs/032-automatic-step-retry.md) | implemented |
| 033 | [Autonomy slider: how often agents ask](specs/033-autonomy-slider.md) | implemented |
| 034 | [Recurring work: orders that repeat](specs/034-recurring-work.md) | implemented |
| 035 | [Mute the microphone in voice mode](specs/035-mute-microphone-in-voice-mode.md) | implemented (Q1–Q4 on the proposals, owner to confirm; behaviour tested in `jsc`; walkthrough with a real microphone pending) |
| 036 | [Parallel tasks on one agent](specs/036-parallel-agent-tasks.md) | implemented on the director's epic (backend, status UI, acceptance tests S1–S5), spec still draft for owner review; R6 per the owner's decision (space folder, one step per folder at a time); HTTP part of S5 and B20 analysis pending |
| 100 | [Ratings and sentiment](specs/100-ratings-and-sentiment.md) | closed |
| 101 | [Reflection and playbooks](specs/101-reflection-and-playbooks.md) | draft (Q1–Q3 open) |
| 102 | [Model of the owner and when agents ask](specs/102-owner-model-and-questions.md) | draft (Q1–Q4 open) |
| 103 | [Learning which agent and strategy work best](specs/103-strategy-selection.md) | draft (Q1–Q3 open) |
| 104 | [Distillation into a local model (LoRA)](specs/104-distillation-lora.md) | draft (Q1–Q4 open) |
| — | Feedback loop: results back to the director, budgets, stop | not written |
| — | Isolation of agents (F12, F15) | not written |
| — | Memory per space and per agent | not written |
| — | Self-improvement | not written |

Template: [`specs/TEMPLATE.md`](specs/TEMPLATE.md).

Spec 023: the Team page, the chat strip and both prompts show when a member is **busy** running a step of one of your epics. Team polls every 5 s. The idle chat polls every 8 s and exceeded the 5 s release gate in the browser. The director, the verifier and Agentaro notices use icons with up to two initials in chat ("Discovery Agent" → DA). In the chat's strip, members are initials only, coloured by state: green free, indigo working, amber busy (spec 024, spec 036). Consecutive messages from the same author share one visible icon. Team members have icons on the strip. The director and verifier get a chat status dot while executing a step. Spec 036 (S3, S6) supersedes busy/free: the status is the agent's load against its limit over all accounts and spaces — "free · 0/6 in progress", "2/6 in progress" (working, slots free), "busy · 6/6 in progress" only at the limit; the folded strip says "3 tasks in progress · 1 of 2 busy". Activity details stay per account: a shared agent's steps for someone else count as a number only. The director's member list says "free/working: N/M tasks in progress, K free slots" or "busy: … at its limit (a new step waits in the queue)", and its planning rules prefer members with free slots. A per-space scope is [TO BE DETERMINED].

## License

[TO BE DETERMINED]
