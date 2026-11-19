# 001 — Initial project structure

Status: **implemented** 2026-11-19 (closed by owner's instruction: "create initial code structure … I expect blank project structure")
Date: 2026-11-19
Depends on: —

## 1. TL;DR

A blank, minimal Ruby on Rails application with SQLite, so anyone can clone the repository and run it locally without extra services. Confirmed when a fresh clone boots and its test suite passes.

## 2. Abstract

The repository holds only CDD artifacts; there is no code yet.

The owner chose the stack: the latest Ruby and Ruby on Rails, and SQLite as the only database, because people should be able to clone the repository and run it as is. The database file is never committed.

Agents will run on subscription plans (Claude Code, Codex CLI) signed in on the host. A container would need extra work to reach those logins (on macOS the Claude login lives in the Keychain), so Docker is deliberately left out for now.

## 3. Objective

**Goals**
- G1. Rails application named `agentaro` in the repository root, generated with the smallest set of framework components.
- G2. Latest stable versions at the time of writing: Ruby 4.0.10, Rails 8.1.4.1, pinned in `.ruby-version` and `Gemfile.lock`.
- G3. SQLite as the database; database files ignored by git.
- G4. A test suite that runs and passes on the blank application.

**Out of scope**
- Any domain feature (agents, providers, calendar, teams), models, pages or authentication.
- Docker, Kamal, CI pipelines, background jobs, mail, file uploads, JavaScript tooling.

**Success criteria**
- S1. `bin/setup` (or `bundle install` + `bin/rails db:prepare`) on a fresh clone succeeds with only Ruby installed.
- S2. `bin/rails test` passes.
- S3. `bin/rails server` boots and `GET /up` returns 200.
- S4. `git ls-files` contains no database file, no `config/master.key` and no other secret.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | Rails application skeleton (`app/`, `bin/`, `config/`, `db/`, `lib/`, `public/`, `test/`, `Gemfile`) | to create |
| System | `.ruby-version` (4.0.10) | to create |
| Data | `storage/*.sqlite3` (development, test) | to create, ignored by git |
| Organization | `config/master.key` | to create locally, ignored by git |
| Organization | `.gitignore` | to change (merge Rails entries) |
| Organization | `README.md`, `AGENTS.md`, `MANIFESTO.md` — run and test commands, decided stack | to change |

## 5. Functional Domain Changes

- **State:** no application → a blank Rails application that boots and has a health check (`/up`).
- **Rules:** none (no domain yet).
- **Resilience:** not applicable.
- **Data:** SQLite databases are created locally by `db:prepare`; no schema yet.

## 6. Critical Path

Install Ruby 4.0.10 → `rails new` with the minimal option set and SQLite → merge into the repository without overwriting CDD artifacts → `bin/rails db:prepare` → `bin/rails test` → boot and check `/up` → confirm no secrets or database files are tracked. Complete when S1–S4 hold.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | 0 failures, 0 errors | `bin/rails test` | commit | — |
| E2E | HTTP 200 | `bin/rails server`, then `curl localhost:3000/up` | commit | — |
| Manual | no `*.sqlite3`, `master.key`, `.env` in git | `git ls-files` | push | a tracked database or key fails the gate |

## 8. Expected Outcome

- **Direct effect:** the repository is a runnable Rails application with no features.
- **Measurable effect:** a fresh clone is running within minutes, with only Ruby installed.
- **Side effects:** contributors need Ruby 4.0.10 (e.g. Homebrew, rbenv or mise).
- **Rollback:** revert the commit.

## 9. Additional Information

- **Rejected alternatives:** Docker / Docker Compose (Rondo E18 prefers containers) — postponed, because subscription logins on the host are not easily reachable from a container. PostgreSQL — would require a separate server.
- **Technical debt:** no container stack; deployment is local only.
- **External dependencies:** RubyGems; Homebrew used on the owner's Mac to install Ruby.
- **Sources and questions:** —
