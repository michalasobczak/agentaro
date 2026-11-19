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

Everything lives in `storage/`: the databases (development and production), the audit databases, `settings.env` and `secrets.yml` (encryption keys for TOTP secrets — without it every authenticator has to be set up again). Back up the whole folder.

## Functional architecture

Ruby on Rails 8.1 application with SQLite (`storage/`, not committed). No JavaScript, no external resources.

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
- Next: task calendar and provider adapters (Claude Code, Codex).

## Specifications

| No. | Title | Status |
|---|---|---|
| 001 | [Initial project structure](specs/001-initial-structure.md) | implemented |
| 002 | [Authentication, roles and TOTP](specs/002-authentication-roles.md) | implemented |
| 003 | [HTTP audit log](specs/003-http-audit-log.md) | implemented |
| 004 | [Data changelog](specs/004-data-changelog.md) | implemented |
| 005 | [Security analysis, round 1](specs/005-security-round-1.md) | implemented |
| 006 | [Responsive layout and visual design](specs/006-responsive-ui.md) | implemented |

Template: [`specs/TEMPLATE.md`](specs/TEMPLATE.md).

## License

[TO BE DETERMINED]
