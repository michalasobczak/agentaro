# Agentaro

![Agentaro in one minute: spaces, epics, the director chat, calendar, team and the sandbox](docs/agentaro-demo.gif)

**If Agentaro looks useful to you, please ⭐ star the repository — it helps a solo, built-in-public project grow.**

A private agent system that runs on your own computer and works across AI providers — including subscription plans (Claude Code, Codex), not just pay-per-token APIs. *Agentaro* is Esperanto for "a group of agents".

Built in public: every prompt used to build it is posted on X. The project follows [Rondo and Context-Driven Development](https://workwithrondo.com/x): what each feature does is in its spec (table below), what was built and when is in [`CHANGELOG.md`](CHANGELOG.md).

## Intended use

For **personal, family or small-business use**, in a secured local network — not for enterprise use and not on the public internet. Agentaro is not sold. Agents on Claude Code or Codex work with your Mac account's rights inside a sandbox, so **give Agentaro accounts only to people you trust with that account.**

## Domain picture

- **Agents** do the work. Each runs on an **executor**: a command-line tool you are logged in to (Claude Code, Codex, Gemini CLI, …) or a local model (Ollama, LM Studio). No keys are stored.
- **Spaces** (projects and teams) hold **epics**; an epic is planned into **steps**, each done by an agent, optionally in the space's working folder, with CI and a dev server kept by Agentaro.
- The **director** (you talk to it by text or local voice) keeps the work list, plans, retries and reports; a **verifier** on another executor checks its answers.
- A **calendar** with one-time and recurring work, a **brain** of remembered facts, run traces, an HTTP audit log and a data changelog — all on this computer.

## Getting started

Requirements: Ruby 4.0.10 (`.ruby-version`). SQLite comes with the `sqlite3` gem; Docker is optional.

```bash
git clone https://github.com/michalasobczak/agentaro.git
cd agentaro
bin/setup                        # gems, databases, starts the server
bin/rails agentaro:admin:create  # first admin: password and an authenticator QR code
```

Open http://localhost:3000. The admin adds users and gives each a one-time link to set a password. `bin/rails test` runs the tests, `bin/ci` the local CI.

**Real use:** run `bin/start` (production mode on localhost) behind an HTTPS proxy, for example `tailscale serve --bg 3000`, with your hostname in `AGENTARO_HOSTS` in `storage/settings.env`. Create the admin with `RAILS_ENV=production`. Restart `bin/start` after updating the code.

**Backups:** the whole `storage/` folder (databases, `settings.env`, `secrets.yml`) and `var/runs/`.

## Functional architecture

Ruby on Rails 8.1 with SQLite, no external resources and no JavaScript libraries (a strict Content-Security-Policy, first-party scripts only). Command-line agents run as local processes in their tools' own sandboxes, CI and servers in macOS `sandbox-exec`; runs, traces and the audit chains stay in `storage/` and `var/`.

## Critical path

[TO BE DETERMINED]

## State (here and now)

All specs marked implemented below work in the code; the history is in [`CHANGELOG.md`](CHANGELOG.md). Open: isolation of agents (F12, F15), a feedback loop with budgets, and the learning specs 100–104.

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
| 011 | [Director chat, work list and management](specs/011-list-and-management.md) | implemented (F14, F15 open); managers removed by 012 |
| 012 | [Remove managers: the director plans](specs/012-remove-managers.md) | implemented |
| 013 | [Projects, kanban and calendar depth](specs/013-projects.md) | implemented (F16 open); renamed by 014 |
| 014 | [Spaces: project spaces and team spaces](specs/014-spaces.md) | implemented |
| 015 | [New conversation with the director](specs/015-new-conversation.md) | implemented |
| 016 | [Epics start at a time; steps run one after another](specs/016-sequential-steps.md) | implemented |
| 017 | [Talking to the director: voice and streamed answers](specs/017-voice-and-streaming.md) | implemented (real-microphone check pending) |
| 018 | [A working folder for a space](specs/018-working-folders.md) | implemented (F17, F18 accepted) |
| 019 | [A verifier in the chat](specs/019-verifier.md) | implemented |
| 020 | [Pages without reloading: the conversation keeps going](specs/020-pages-without-reloading.md) | implemented |
| 021 | [Director sees the output of each step](specs/021-director-sees-step-output.md) | implemented (Q1, Q2 open) |
| 022 | [Model lists, effort and a "Check model" button](specs/022-model-lists-and-check.md) | implemented |
| 023 | [Agent status: busy or free](specs/023-agent-status.md) | implemented (owner confirmation pending) |
| 024 | [Conversation fixes](specs/024-conversation-fixes.md) | implemented |
| 025 | [Delete an archived space](specs/025-delete-archived-space.md) | implemented |
| 026 | [Unread chat blinks; blocked epics pop up](specs/026-unread-blink-and-blocked-notices.md) | implemented |
| 027 | [Work panel beside the director chat](specs/027-work-panel-beside-chat.md) | implemented |
| 028 | [Animated page background](specs/028-animated-page-background.md) | implemented (Q1, Q2 open) |
| 029 | [Chat background patterns](specs/029-chat-background-patterns.md) | implemented (Q1, Q2 open) |
| 030 | [Run traces](specs/030-run-traces.md) | implemented |
| 031 | [Brain: long-term memory](specs/031-brain-memory.md) | implemented |
| 032 | [Automatic retry of failed steps](specs/032-automatic-step-retry.md) | implemented; partly replaced by 040 |
| 033 | [Autonomy slider: how often agents ask](specs/033-autonomy-slider.md) | implemented |
| 034 | [Recurring work: orders that repeat](specs/034-recurring-work.md) | implemented |
| 035 | [Mute the microphone in voice mode](specs/035-mute-microphone-in-voice-mode.md) | implemented (real-microphone check pending) |
| 036 | [Parallel tasks on one agent](specs/036-parallel-agent-tasks.md) | implemented; spec awaits owner review |
| 037 | [One epic at a time in a space](specs/037-one-epic-at-a-time-per-space.md) | implemented |
| 038 | [Live view of a step beside the work panel](specs/038-live-step-view.md) | implemented |
| 039 | [How much the director writes](specs/039-reply-length-switch.md) | implemented |
| 040 | [The director controls failed and hung steps](specs/040-director-controls-failed-and-hung-steps.md) | implemented |
| 041 | [Chat settings in one panel, conversation style and work tempo](specs/041-chat-settings-panel-style-and-tempo.md) | implemented |
| 042 | [On a phone, the menu shows the chosen page, not the chat](specs/042-phone-menu-closes-chat.md) | implemented |
| 043 | [Usage limits of Claude and Codex, and a deputy director](specs/043-usage-limits-and-deputy-director.md) | implemented |
| 044 | [The director on a local model (Ollama)](specs/044-director-on-a-local-model.md) | implemented |
| 045 | [A short human summary when an epic ends](specs/045-epic-summary-in-chat.md) | implemented |
| 046 | [Natural conversation mode](specs/046-natural-conversation-mode.md) | implemented |
| 047 | [Retry by agreement, and replies kept when an action is refused](specs/047-retry-by-agreement-and-kept-replies.md) | implemented |
| 048 | [Pause an epic](specs/048-pause-an-epic.md) | implemented |
| 049 | [Codex with a local model](specs/049-codex-with-a-local-model.md) | implemented |
| 050 | [Does the reply match what was done?](specs/050-reply-versus-actions-check.md) | implemented |
| 051 | [Groups of spaces, arranged with the mouse](specs/051-space-groups.md) | implemented |
| 052 | [CI and servers of a space](specs/052-space-ci-and-servers.md) | implemented |
| 053 | [A relaxed sandbox: web, local ports and Git](specs/053-relaxed-sandbox.md) | implemented |
| 054 | [A space without a sandbox](specs/054-space-without-sandbox.md) | implemented |
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

## License

[TO BE DETERMINED]
