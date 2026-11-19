# 003 — HTTP audit log

Status: **draft** — items marked *(proposal)* wait for the owner's acceptance
Date: 2026-11-19
Depends on: [002](002-authentication-roles.md)

## 1. TL;DR

Every HTTP request to Agentaro is recorded: who, when, from where, what was asked for (with sensitive values filtered) and how it ended. Rows are chained with hashes so a later edit is detectable, and they are kept for 3 months. Confirmed by tests that requests are logged, secrets never appear and a tampered row breaks verification.

## 2. Abstract

**Current state.** After spec 002 the application knows who is signed in, but nothing records what people do.

**Gap.** Without a record of requests there is no way to investigate an incident or show who accessed what.

**Rationale.** Rondo E12 (record and protect the audit log: actor, time, no secrets). ISO 27001 A.8.15 (logging) and A.8.16 (monitoring activities).

**Decision history (owner, 2026-11-19).** All HTTP traffic is logged, including request bodies with sensitive values filtered. Retention 3 months. Rows are chained with hashes (tamper evidence).

## 3. Objective

**Goals**
- G1. One row per HTTP request: time, request id, user (if signed in), session id, IP, user agent, method, path, query string, filtered body, response status, duration.
- G2. Bodies are filtered with the same rules as Rails parameter filtering, extended with `password`, `otp`, `code`, `token`, `secret`; the stored body is capped at 10 KB *(proposal)*.
- G3. Hash chain: each row stores `SHA-256(previous hash + canonical row content)`. A command verifies the chain: `bin/rails agentaro:audit:verify`.
- G4. Retention: rows older than 3 months are removed by `bin/rails agentaro:audit:prune`; the hash of the oldest remaining row is kept as the new chain anchor.
- G5. Admins can browse and filter the log in the web interface (read-only).
- G6. The log lives in a separate SQLite database `storage/audit.sqlite3` *(proposal)*, so heavy logging does not slow the main database and the log can be backed up on its own.

**Out of scope**
- Shipping logs to an external system (SIEM).
- Alerting.
- Logging response bodies.

**Success criteria**
- S1. Every request — including failed sign-ins, 404s and `/up` — produces exactly one row.
- S2. No password, TOTP code, token or secret appears in any row.
- S3. Changing or deleting any row makes `agentaro:audit:verify` fail and name the first broken row.
- S4. The application has no code path that updates or deletes audit rows, except pruning.
- S5. Regular users cannot open the audit log.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `storage/audit.sqlite3` with table `audit_events` | to create |
| System | Rack middleware recording requests (runs after the response is built) | to create |
| System | Rake tasks `agentaro:audit:verify`, `agentaro:audit:prune` | to create |
| System | Admin page "Audit log" | to create |
| Organization | README (retention, verify command), MANIFESTO | to change |

## 5. Functional Domain Changes

**State:** no record of activity → every request recorded.

**Rules**
- R1. Logging must not change the response; if writing the row fails, the request still completes and the failure goes to the Rails log.
- R2. Rows are written in order; concurrent requests are serialized when the hash chain is extended (SQLite write lock).
- R3. Static assets are logged like any other request *(proposal: yes — "all traffic")*.
- R4. The user is resolved from the session. A failed sign-in stores the username as typed, never whether that account exists, so the log does not become an enumeration aid.

**Resilience:** if `audit.sqlite3` is unavailable, requests are served and errors logged. [TO BE DETERMINED: should the app refuse requests instead (fail closed)?] *(proposal: fail open, report in the Rails log)*

**Data:** separate database, own migrations; size grows with traffic — 3-month pruning bounds it.

## 6. Critical Path

Second database configured → middleware writing rows with filtered body → hash chain → verify and prune tasks → admin page → tests S1–S5.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | 0 failures | `bin/rails test` (filtering, hash chain, prune keeps chain verifiable) | commit | a secret stored in a row; a tampered row passes verify |
| Integration | 0 failures | `bin/rails test` (requests produce rows, admin-only page) | commit | regular user opens the audit log |
| Manual | rows appear for real browsing | sign in, browse, `agentaro:audit:verify` OK | push | — |

## 8. Expected Outcome

- **Direct effect:** an admin can see who accessed what and when.
- **Measurable effect:** 100 % of requests logged; verify passes on an untouched log.
- **Side effects:** a database write per request; disk usage bounded by 3-month retention.
- **Rollback:** remove the middleware; the audit database can be kept or deleted.

## 9. Additional Information

- **Rejected alternatives:** parsing the Rails text log (not structured, no user); a gem such as `audited` (covers model changes, not HTTP traffic).
- **Technical debt:** the hash chain detects tampering but cannot prevent someone with file access from rewriting the whole chain; protection against that needs an external copy. [TO BE DETERMINED]
- **Questions:**
  - Q1. Separate database `storage/audit.sqlite3`? *(proposal: yes)*
  - Q2. Fail open (serve requests, report logging errors) or fail closed? *(proposal: fail open)*
  - Q3. Body cap 10 KB? *(proposal: yes)*
