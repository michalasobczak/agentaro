# Agentaro

A private agent system that runs on-prem and works across multiple AI providers — including subscription plans (e.g. Claude, ChatGPT), not just pay-per-token APIs. Vendor-agnostic: no single provider is required.

*Agentaro* is Esperanto for "a group of agents".

Built in public: every prompt used to build it is posted on X. The project follows [Rondo and Context-Driven Development](https://workwithrondo.com/x).

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

Open http://localhost:3000 (health check: http://localhost:3000/up).

```bash
bin/rails test   # tests
bin/ci           # local CI: setup, tests, seeds
bin/dev          # start the server again later
```

## Functional architecture

Ruby on Rails 8.1 application with SQLite (`storage/*.sqlite3`, not committed). No domain features yet — the only endpoint is the health check `/up`.

## Critical path

[TO BE DETERMINED]

## State (here and now)

- 2026-11-19: repository set up with CDD artifacts.
- 2026-11-19: blank Rails application (spec 001): Ruby 4.0.10, Rails 8.1.4.1, SQLite, minimal components, no Docker. Tests: 1 (health check). Security analysis: clean.
- Next: specification session for the first feature. Direction proposed by the owner: a task calendar and provider adapters (Claude Code, Codex).

## Specifications

| No. | Title | Status |
|---|---|---|
| 001 | [Initial project structure](specs/001-initial-structure.md) | implemented |

Template: [`specs/TEMPLATE.md`](specs/TEMPLATE.md).

## License

[TO BE DETERMINED]
