# 008 — Executors

Status: **implemented** 2026-11-19 (closed by owner: Q1 "Yes, accept scope", Q2 "no API keys, we assume that tool is logged locally or accessible without token also locally, we skip token based usage", Q3 "Presets only", Q4 "Read-only for users")
Date: 2026-11-19
Depends on: [002](002-authentication-roles.md), [003](003-audit-log.md), [004](004-data-changelog.md), [006](006-responsive-ui.md)

## 1. TL;DR

Admins manage **executors**: the AI tools Agentaro will later use to do work, reached either as a command-line program on the host (Claude Code, Codex, Gemini, Grok, Ollama, LM Studio) or as a local HTTP API that needs no token (Ollama, LM Studio, an OpenAI-compatible server). Admins add them from built-in presets, edit, enable or disable, check and delete them; users see the list read-only. Confirmed by tests of validation, permissions and the check, and by checking the tools installed on the host.

## 2. Abstract

**Current state.** Agentaro has accounts, audit, data changelog, a responsive interface and a calendar of tasks (specs 002–007). It knows nothing about AI providers yet.

**Need (owner, 2026-11-19).** "let admin to be able to manage "executor" which are Claude, Codex, Grok or any other AI tool which can be used as CLI/API, so this includes also Ollama, LMStudio etc."

**Rationale.** The project's purpose is vendor-agnostic, on-prem agents that also use subscriptions (README, MANIFESTO). Subscriptions are reachable only through the vendors' own CLIs logged in on the host, while local and paid models are reachable through HTTP APIs. One registry of executors with two kinds, CLI and API, covers both. It is the base for agents and for assigning tasks later.

**Decisions (owner).** No tokens: every tool is either logged in on the host (subscriptions, e.g. `claude login`) or reachable locally without a key; token-based APIs are skipped (Q2). Programs come only from built-in presets, never typed in the web (Q3). Users see executors read-only (Q4).

**Risk.** A CLI executor starts a program on the host. With presets only, a stolen admin session can start nothing but the listed tools, with fixed arguments, and only to check their version.

## 3. Objective

**Goals**
- G1. Admin page "Executors": a list with name, kind (CLI / API), preset, enabled state and the last check result.
- G2. Add and edit an executor by choosing a **preset** (Q3); the program and its arguments come from the preset and cannot be changed in the web:
  - **CLI:** Claude Code (`claude`), Codex (`codex`), Gemini CLI (`gemini`), Grok CLI (`grok`), Ollama (`ollama`), LM Studio (`lms`).
  - **API, no token (Q2):** Ollama (`http://localhost:11434`), LM Studio (`http://localhost:1234/v1`), OpenAI-compatible server (llama.cpp, vLLM, LocalAI; `http://localhost:8080/v1`).
- G3. Fields: name (unique), preset, enabled, default model (optional), notes; for API presets also the base URL (default from the preset).
- G4. **Check** an executor on demand, and see the result with a timestamp:
  - CLI: the program is found and `<program> <version argument>` answers within 10 seconds; the version is shown;
  - API: the models endpoint answers within 10 seconds; the list of models is shown.
- G5. Enable / disable without deleting; delete with confirmation.
- G6. Every change appears in the audit log and the data changelog.
- G7. Regular users see the list read-only: name, kind, preset, default model, enabled, last check (Q4); no base URL, notes or check output.

**Out of scope**
- Running prompts or tasks on executors, agents, teams, assigning calendar tasks to executors, cost or usage tracking, logging into vendor subscriptions from the web (the owner logs in on the host, e.g. `claude login`), automatic discovery.
- API keys and token-based APIs (Q2); custom programs or arguments (Q3).

**Success criteria**
- S1. An admin adds Claude Code, Codex, Ollama (API) and LM Studio (API) from presets, and the check succeeds for those installed and running on the host.
- S2. A regular user sees the list read-only and cannot add, change, check or delete executors (Q4).
- S3. The web offers no way to choose a program, arguments or a key; a forged request with them changes nothing.
- S4. Invalid definitions are rejected with a clear message: blank or duplicate name, unknown preset, a base URL that is not http(s) or carries a user name, password, query or fragment.
- S5. A check of a broken executor (missing program, endpoint down, timeout) shows the error and does not hang the page.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `executors` (name, preset, enabled, base_url, default_model, notes, last_checked_at, last_check_ok, last_check_output) | to create |
| System | `Executor` model, `Executor::PRESETS` (kind, program, version argument, protocol, default URL), validations | to create |
| System | `ExecutorCheck` (CLI: spawn without shell, timeout; API: HTTP GET with timeout) | to create |
| System | `ExecutorsController#index` (everyone, read-only) and `Admin::ExecutorsController` (new, create, edit, update, destroy, check; `desktop-only`) | to create |
| System | Navigation: "Executors" for everyone | to change |

## 5. Functional Domain Changes

**State:** no providers → admin-managed registry of CLI and API executors.

**Rules**
- R1. Only admins add, change, check and delete executors; everyone signed in sees the read-only list (Q4).
- R2. A CLI program runs without a shell: the preset's program name and fixed arguments. The program is looked up on the server's `PATH` and in the usual install folders (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.lmstudio/bin`).
- R3. Only presets (Q3). The program, arguments and protocol come from code, not from the database or the web.
- R4. A check runs with a 10-second timeout and a minimal environment (`PATH`, `HOME`, `USER`, `LANG`, `TMPDIR` — none of Agentaro's own secrets), in the system temporary folder; on timeout the process group is killed. Output kept: at most 2 KB, escape codes removed.
- R5. No API keys (Q2). Base URL: `http` or `https`, no user name or password, no query or fragment. Plain `http` is expected for local endpoints. The check does not follow redirects.
- R6. A disabled executor is kept but will not be used by later specs; it can still be checked.
- R7. Names are unique, 1–60 characters.

**Resilience:** a check runs in the request with a timeout; a missing program, refused connection or timeout is a failed check, not an error page.

**Data:** a new table in the main database; changes recorded by the data changelog.

## 6. Critical Path

Model, presets and validations → read-only list and admin pages → check (CLI, API) → tests → check against the tools installed on the host.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | validations, presets, check (CLI and API, success, failure, timeout) | `test/models/executor_test.rb` | merge | unknown presets and bad URLs rejected; a hanging program is killed |
| Integration | admin CRUD, enable/disable, check, read-only list | `test/integration/executors_test.rb` | merge | regular user gets 403 on every change; forged program/arguments ignored |
| E2E | real check of executors installed on the host | manual run on the owner's Mac | release | — |
| Manual | browser walk-through of the admin pages | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** admins keep one list of AI tools Agentaro can use, and see which of them work.
- **Measurable effect:** S1–S5 pass.
- **Side effects:** the app can now start processes on the host (version checks of preset tools only) and make HTTP requests to admin-chosen addresses (the models endpoint only).
- **Rollback:** drop the table and the admin pages; nothing else depends on them yet.

## 9. Additional Information

- **Rejected alternatives:** a single "provider" per vendor (a vendor can be reached both by CLI subscription and by API); a shell command string (injection risk); custom programs from the web (Q3); API keys in the database or environment (Q2).
- **Technical debt:** the API base URL may point anywhere the server can reach (admin-only, GET of the models endpoint only); revisit when agents start sending prompts.
- **External dependencies:** the vendors' CLIs and local servers installed by the owner; Ruby's standard library only (`Process.spawn`, `Net::HTTP`).
- **Sources and questions:**
  - Q1. Scope: list, add from presets, edit, enable/disable, delete, check. — **Accepted.**
  - Q2. API keys. — **None:** "we assume that tool is logged locally or accessible without token also locally, we skip token based usage".
  - Q3. Which programs. — **Presets only.**
  - Q4. Visibility. — **Read-only for users.**

## Security analysis (B20), after spec 008

Scope: this spec and specs 001–007, looking for regressions and gaps.

- **Process start.** Presets only (Q3): the program name and arguments are constants in `Executor::PRESETS`; the table has no program or argument columns; forged parameters are ignored (test). No shell; minimal environment (no `SECRET_KEY_BASE`, no `AGENTARO_*`); working folder is the system temp folder; on timeout the whole process group is killed (test with a child process). Residual: a preset tool that detaches into its own session would survive the kill — accepted, the tools are the owner's own.
- **Outgoing HTTP (SSRF).** Admin-only, GET of a fixed models path, no redirects, no credentials in the URL. Residual: the address may point anywhere the server can reach — accepted for the intended use (technical debt above).
- **F9 (low, fixed).** A check holds a server thread for up to 10 seconds; repeated checks could exhaust Puma's threads. Fix: `rate_limit` 20 checks per minute.
- **F10 (low, fixed).** The models response was read whole into memory. Fix: at most 1 MB read, then the check fails. Test with a 1.2 MB answer.
- **Output.** Kept at most 2 KB, escape and control characters removed, rendered escaped by ERB, shown only to admins; users never see addresses, notes or output (test).
- **Regressions in 001–007.** Brakeman: only the known weak F8 (`HEAD` vs `GET` in return-to). `bundle-audit`: no vulnerabilities. New pages have no inline styles or scripts (test). Audit log and data changelog record executor changes; nothing secret is stored.
