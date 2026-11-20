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

Ruby on Rails 8.1 application with SQLite (`storage/`, not committed). No external resources; two small first-party scripts (`app/assets/javascripts/`), no JavaScript libraries.

- **Director and management (spec 011):** you talk only to your director in a chat — on the Director page, or from any page in a panel on the right. The director keeps your work list, picks a manager for each item, and approves the manager's plan; the steps go into the calendar for the manager's team members. Your team (director, managers, members with roles) is set up on the Team page and shown as an org chart. Agents answer in JSON; Agentaro checks every answer before applying it.
- **Running tasks (spec 010):** at a task's start time its agent runs it on its executor — Claude Code and Codex with tools confined to the run's own folder, Ollama and LM Studio as text; 2 at a time, never late, 15-minute limit. Runs and answers are shown on the task and marked in the calendar; "Run now" starts one by hand.
- **Agents (spec 009):** a name, a master prompt (who the agent is, written by people) and the executor it runs on, with an optional model. Every user has private agents; admins also make shared agents for everyone. Calendar tasks can be assigned to an agent.
- **Executors (spec 008):** the AI tools Agentaro can use, managed by admins from built-in presets — command-line tools logged in on this computer (Claude Code, Codex, Gemini CLI, Grok CLI, Ollama, LM Studio) and local APIs that need no key (Ollama, LM Studio, OpenAI-compatible servers). On-demand check: version of the program, or list of models. Users see the list read-only. No keys or tokens are stored; subscriptions are used by logging in on the host (`claude login`, `codex login`).
- **Calendar (spec 007):** day, 4-day, week and month views; one-time and recurring tasks (daily, weekly on chosen days, monthly; at most 3 months per series) from 1 minute to 4 days, all-day tasks; new tasks in a popup over the calendar; drag & drop, resize, cut, copy, paste, duplicate. Private tasks per user and a system-wide calendar that admins maintain. Europe/Warsaw time.
- **Interface (spec 006):** responsive — sidebar layout on desktop and tablet (≥ 640 px), compact top bar on phones; light and dark mode; plain CSS and inline SVG icons. Phones get sign-in, home, own sessions and password; admin tools are for desktop and tablet.

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
- Next: 012 projects; later, without numbers yet: feedback loop (results back to the management, budgets, stop), isolation of agents (F12, F15), memory (per project and per agent), self-improvement.

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
| 011 | [Director chat, work list and management](specs/011-list-and-management.md) | implemented (F14, F15 open) |
| 012 | [Projects](specs/012-projects.md) | draft |
| — | Feedback loop: results back to managers, budgets, stop | not written |
| — | Isolation of agents (F12, F15) | not written |
| — | Memory per project and per agent | not written |
| — | Self-improvement | not written |

Template: [`specs/TEMPLATE.md`](specs/TEMPLATE.md).

## License

[TO BE DETERMINED]
