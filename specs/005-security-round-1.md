# 005 — Security analysis after specs 001–004 (round 1)

Status: **implemented** 2026-11-19 (owner: "Accept, fix F1–F3", then "Include timing difference on failed sign-ins" — F4 fixed instead of accepted)
Date: 2026-11-19
Depends on: [001](001-initial-structure.md), [002](002-authentication-roles.md), [003](003-http-audit-log.md), [004](004-data-changelog.md)

## 1. TL;DR

Security analysis (Rondo B20) after implementing specs 002–004 found two medium gaps in how the app is run behind the HTTPS proxy — cookies are not marked secure and detailed error pages are shown to remote users — plus smaller items. This spec records every finding and the proposed fix; each fix is confirmed by a test or a check of the running app.

## 2. Abstract

**Current state.** Specs 002–004 are implemented and tested (58 tests). The app runs in development mode on localhost and is published over HTTPS by a TLS-terminating proxy (`tailscale serve`, see MANIFESTO).

**Method.** Review of specs 001–004 against the code; scanners `bundle-audit` (no known vulnerable gems) and Brakeman (one weak warning, F8); inspection of the running app through the proxy (response headers, cookie attributes, audit rows); a browser walk-through of sign-in, TOTP, user creation, password-change link and authorization on a throwaway test instance.

**Gap.** The specs assumed "secure cookies in production". In practice the app is reached through an HTTPS proxy while Rails sees plain HTTP, and it runs in development mode.

## 3. Objective

**Goals** — one per finding:

| # | Severity | Finding | Proposed fix |
|---|---|---|---|
| F1 | medium | Behind the HTTPS proxy, Rails sees HTTP: session cookies lack `Secure`, no HSTS header (spec 002, R7). | Setting `AGENTARO_HTTPS_PROXY=1` turns on `assume_ssl` and `force_ssl` (Secure cookies, HSTS). Documented in README. |
| F2 | medium | The app runs in development mode for remote users: an error shows a full debug page (stack trace, request details) to anyone who can reach it. | Run the server in production mode for real use (`bin/start`), development mode only on localhost for development. |
| F3 | low | Audit retention (3 months) is not enforced automatically — `agentaro:audit:prune` must be run by hand (specs 003 G4, 004 G4). | Prune automatically once a day from the running app. |
| F4 | low | A failed sign-in for an existing user writes to the database (failed-attempt counter, changelog); for an unknown user it does not. The timing difference could reveal that an account exists (spec 002, S6). | Fix (owner): failed attempts are counted per typed username in `sign_in_throttles`, whether or not the account exists; every failure does one bcrypt comparison and one throttle write. Unknown names are locked out like real ones. Stale counters are removed by the daily prune. |
| F5 | low | `storage/secrets.yml` holds the encryption keys of TOTP secrets; losing it makes all authenticators unusable. | Document backup of `storage/` (both databases and `secrets.yml`) in README. |
| F6 | info | Rate limits live in process memory and reset on restart. | Accept for a single-process, small installation. |
| F7 | info | The hash chains detect edits but someone with file access can rewrite a whole chain (already technical debt in spec 003). | Accept for now. |
| F8 | info | Brakeman: `HEAD` requests do not store the return-to page. | No impact; accept. |

**Out of scope:** penetration testing; TLS configuration of the proxy itself.

**Success criteria**
- S1. With `AGENTARO_HTTPS_PROXY=1`, every `Set-Cookie` carries `Secure` and responses carry `Strict-Transport-Security` (F1).
- S2. In the way the app is started for real use, an exception shows the generic error page, not a stack trace (F2).
- S3. Rows older than 3 months disappear without manual action and the chains still verify (F3).
- S4. A failed sign-in issues the same database writes for an existing and an unknown username (F4).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `config/application.rb` — proxy switch (F1) | to change |
| System | `bin/start` — production-mode start script (F2) | to create |
| System | automatic daily prune (F3) | to create |
| Data | `sign_in_throttles` (username, failed_attempts, locked_until); `users.failed_attempts` and `users.locked_until` removed (F4) | to create / to remove |
| Organization | README (running for real use, backups), MANIFESTO | to change |

## 5. Functional Domain Changes

- **Rules:** R1. Without `AGENTARO_HTTPS_PROXY`, behaviour is unchanged (local development over plain HTTP keeps working).
- **Resilience:** pruning failures are logged and retried the next day.
- **Data:** none.

## 6. Critical Path

F1 switch + test → F2 start script + check of the error page through the proxy → F3 daily prune + test → README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | 0 failures | `bin/rails test` (F1 cookie flags and HSTS, F3 prune) | commit | a cookie without `Secure` when the switch is on |
| Manual | headers and error page | `curl` through the proxy | push | stack trace visible remotely |

## 8. Expected Outcome

- **Direct effect:** sessions cannot leak over plain HTTP; remote users never see internals; logs stay within 3 months.
- **Side effects:** production mode needs precompiled assets (`bin/start` does it).
- **Rollback:** unset the switch; start with `bin/dev` again.

## 9. Additional Information

- **Questions:** Q1. Accept fixes F1–F3 and the acceptance of F4–F8? *(accepted: yes; F4 changed to a fix by the owner)*
- **Results (2026-11-19):** F1 — `Secure` on every cookie and HSTS, checked through the proxy and by `HttpsProxyTest`. F2 — `bin/start` runs production mode; an unknown path through the proxy shows the generic 404 page; requests for other hostnames get 403. F3 — `Agentaro::AuditRetention` prunes once a day in a background thread (`AuditRetentionTest`). F4 — equal writes for known and unknown usernames (`UserTest`), measured 0.94 ms vs 0.93 ms per failed sign-in at test bcrypt cost. While testing F1, the test setup itself was wrong: `bin/rails test` boots the app before `test_helper.rb`, so proxy mode is now set in `config/environments/test.rb`.
