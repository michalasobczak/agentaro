# 004 — Data changelog

Status: **draft** — items marked *(proposal)* wait for the owner's acceptance
Date: 2026-11-19
Depends on: [002](002-authentication-roles.md), [003](003-http-audit-log.md)

## 1. TL;DR

Every change to application data is recorded as a delta: which record, which fields, the value before and after, when, and by whom — a person in the web interface or an operator on the command line. Rows are hash-chained and kept for 3 months. Confirmed by tests that creates, updates and deletes are recorded with the right author and that secrets never appear.

## 2. Abstract

**Current state.** After spec 003 we know which requests were made, but not what they changed in the data.

**Gap.** The owner wants to know what changed, when and by whom.

**Rationale.** Rondo E12 (record change deltas with actor and time, without secrets) and E08 (data integrity). ISO 27001 A.8.15 (logging), A.5.33 (protection of records).

**Decision history (owner, 2026-11-19).** A data changelog is required. Retention and tamper evidence follow spec 003: 3 months, hash chain.

## 3. Objective

**Goals**
- G1. For every create, update and delete of an Active Record model: model, record id, action, changed fields with before/after values, time, actor, and the request id that links to the audit log (spec 003).
- G2. Actor: the signed-in user for web requests; `cli:<operating-system user>` for command-line tasks and the console; `system` otherwise.
- G3. Sensitive fields (password digest, TOTP secret, token digests and any field matching the parameter filter) are recorded as changed, with values replaced by `[FILTERED]`.
- G4. Same hash chain, verification and 3-month pruning as spec 003, in the same audit database *(proposal)*.
- G5. Admins can see the history of a record and browse all changes (read-only).

**Out of scope**
- Restoring old versions (undo).
- Recording reads.

**Success criteria**
- S1. Create, update and delete each produce one row with correct before/after values and actor.
- S2. A change made by the command-line task `agentaro:admin:create` is attributed to `cli:<user>`.
- S3. No password digest, TOTP secret or token appears in any row.
- S4. Every changelog row from a web request carries a request id that exists in the audit log.
- S5. Tampering with a row breaks verification.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | table `data_changes` in `storage/audit.sqlite3` | to create |
| System | concern included in `ApplicationRecord` (after commit callbacks) | to create |
| System | `Current.actor` / request id propagation | to create |
| System | Admin page "Data changes" and per-record history | to create |
| System | Verify and prune tasks extended to `data_changes` | to change |

## 5. Functional Domain Changes

**State:** data changes leave no trace → every change recorded.

**Rules**
- R1. Rows are written after the transaction commits, so rolled-back changes are not recorded.
- R2. Bulk operations that skip callbacks (`update_all`, `delete_all`, `insert_all`) are not allowed in application code; a test fails if they appear outside migrations. *(proposal)*
- R3. Changelog rows are never edited or deleted by the application, except pruning.

**Resilience:** if writing the changelog fails after commit, the error goes to the Rails log and the audit log; the data change stays. [TO BE DETERMINED: accept this gap or write changes in the same database transaction?]

**Data:** shares the audit database and its 3-month retention.

## 6. Critical Path

Actor and request id in `Current` → concern recording deltas after commit → filtering of sensitive fields → hash chain shared with spec 003 → admin pages → tests S1–S5.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | 0 failures | `bin/rails test` (deltas, filtering, actor) | commit | a secret in a row; a rolled-back change recorded |
| Integration | 0 failures | `bin/rails test` (web change → row with request id; CLI change → `cli:` actor) | commit | regular user opens the changelog |
| Manual | history visible for a user record | admin page | push | — |

## 8. Expected Outcome

- **Direct effect:** for any record an admin sees what changed, when and by whom.
- **Measurable effect:** every create/update/delete has a matching row.
- **Side effects:** an extra write per change.
- **Rollback:** remove the concern; existing rows can stay.

## 9. Additional Information

- **Rejected alternatives:** PaperTrail / audited gems — they work, but add dependencies for something a small concern does (Rondo E04).
- **Technical debt:** see spec 003 — a hash chain detects but does not prevent rewriting by someone with file access.
- **Questions:**
  - Q1. Same audit database as spec 003? *(proposal: yes)*
  - Q2. Forbid bulk operations that skip callbacks (R2)? *(proposal: yes)*
  - Q3. Changelog written after commit, accepting a rare lost row on failure? *(proposal: yes)*
