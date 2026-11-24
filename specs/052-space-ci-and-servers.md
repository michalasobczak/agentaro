# 052 — CI and servers of a space

Status: **closed** 2026-11-23 (owner: "Commit, zamknij 052"); **implemented** 2026-11-23.
Date: 2026-11-23
Depends on: [018](018-working-folders.md), [027](027-work-panel-beside-chat.md), [040](040-director-controls-failed-and-hung-steps.md), [045](045-epic-summary-in-chat.md), [051](051-space-groups.md)

## 1. TL;DR

A space with a working folder can describe in its repository how to build it, test it and run its server, in a file `agentaro.yml`. Agentaro runs those commands in the step sandbox: on a button, after a step that changed files, when an epic ends, or on the owner's words. It keeps the server running and shows its state, so the owner no longer needs a terminal tab per project. Tests and a real project (Gra Słodziaki) confirm it.

## 2. Abstract

- **Current state:**
  - Agents build and test inside their steps, and nothing stays running after a step: spec 040 stops whatever a step left behind.
  - To try a game the owner starts its server in a terminal tab, one tab per project.
- **Gap or problem:**
  - The owner's words: "chcę mieć opcję CI na danym space, głównie po to, żeby projekt mógł definiować swój krok build i uruchomienia serwera, jeśli takowy udostępnia … interesuje mnie też info o statusie takiego serwera … chcę uniknąć trzymania N zakładek w terminalu".
- **Decision history:** the owner chose (2026-11-23):
  - the commands live in a file in the repository;
  - CI runs on a button, after a step that changed files, when an epic ends, and on the owner's words;
  - Agentaro keeps the server alive;
  - the state is seen on the space's card, in the work panel and by the director;
  - the commands run in the same sandbox as steps.

## 3. Objective

**Goals**
- G1. **The file.** `agentaro.yml` in the space's working folder, for example:
  ```yaml
  build: npm run build          # optional
  test: npm test                # optional
  serve: npx http-server dist -p 8080   # optional: a command that keeps running
  url: http://localhost:8080    # optional: where the server answers
  ```
  - Every key is optional; without the file the space has no CI.
  - Agents may create and change it like any other file.
  - Agentaro reads it again before each run. A broken file shows its error and runs nothing.
- G2. **CI runs** (build, then test) start:
  - (a) on the Build button on the space's page and card;
  - (b) after a step of an epic in that space whose run changed files in the folder;
  - (c) when an epic of that space ends;
  - (d) on the owner's words in the chat (`run_ci`).
  - One CI run per space at a time. A new trigger while one runs queues at most one more.
  - A CI run never runs while a step of that space is running, so they do not change the same files at once.
- G3. **Results.**
  - Each CI run is a run of Agentaro (state, time, the end of its log).
  - The space keeps the last result: OK, failed at build or failed at test, with the time.
  - A failed run's log end (last 50 lines) is shown on the space's page.
  - The epic summary (spec 045) mentions the result of (c).
- G4. **The server.**
  - `serve` runs as a process kept by Agentaro: start, stop and restart on the space's page, and by words (`server_action`).
  - After a successful build the server is restarted.
  - Every 10 seconds its `url` is checked. The state is starting, up, down (the process ended or the address does not answer for 30 s) or stopped.
  - A server that ended by itself is started again at most 3 times in 10 minutes, then left down with its log.
  - The last 200 lines of its log are kept and shown.
  - After Agentaro restarts, servers that were running are started again.
- G5. **Seen everywhere:**
  - the space's card on the Spaces page and the space's page: the last CI result and the server's state with its link;
  - the work panel: a small dot per space for the server and the last CI;
  - the director: each space's CI and server state; the actions `run_ci` and `server_action` (start, stop, restart) on the owner's words (spec 047 agreement included).
- G6. **The sandbox.**
  - Build, test and serve run as macOS `sandbox-exec` with the rules of a step in a working folder (spec 018): writes only in the folder and temporary folders, no reads of Agentaro's storage or other spaces' folders, network and the Docker socket allowed.
  - The time limit for build and test is 15 minutes each.

**Out of scope**
- A page listing all servers (the owner did not choose it).
- CI for spaces without a working folder.
- Remote CI services, deployments, secrets in the file.

**Success criteria**
- S1. With `agentaro.yml` holding only `build` and `serve`, the Build button builds, and the server starts and shows "up" with its link.
- S2. A step that changes a file triggers one CI run after it; a step that changes nothing triggers none.
- S3. A command in the file that writes outside the folder, or reads Agentaro's storage, is refused by the sandbox, and the CI run shows the error.
- S4. A server that crashes is started again, at most 3 times in 10 minutes, and then shown down with its log.
- S5. After an Agentaro restart, a server that was up is up again.
- S6. "zrestartuj serwer Słodziaków" in the chat restarts it.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `space_services` or columns on spaces: last CI result, server state, desired state | to create |
| System | `agentaro.yml` reader (YAML safe load, four keys, length limits) | to create |
| System | CI runner (purpose `ci`); sandbox-exec profile from spec 018's rules | to create |
| System | server keeper: start, watch, restart, log tail, recovery after restart | to create |
| System | triggers: after a step that changed files, epic end, button, chat | to create |
| System | space card and page, work panel, director's list and actions | to change |

## 5. Functional Domain Changes

- **State:** builds and servers by hand in terminal tabs → described in the repository and kept by Agentaro.
- **Rules:**
  - R1. The file is data. Only its four keys are read; a value is one command line, at most 1000 characters. The command runs through `/bin/sh -c` inside the sandbox; nothing in it is trusted more than an agent's command.
  - R2. "Changed files" means the folder's state differs after the step: `git status`, or a content hash of tracked files when it is not a git repository.
  - R3. Only the owner's own spaces; the buttons and actions check it.
  - R4. A server's port is the project's business. Two servers on one port: the second shows down with the port error from its log.
  - R5. Stopping or archiving a space stops its server. Deleting the space stops it first (spec 025).
- **Resilience:**
  - A server that will not start never blocks steps or the chat.
  - CI failures are results, not errors of Agentaro.
- **Data:** a migration for the CI and server state. Back up production first.

## 6. Critical Path

1. The file reader and the sandbox profile, with tests (S3).
2. The CI runner and the button (S1, build part).
3. The server keeper with its watch, restarts and recovery (S1, S4, S5).
4. The triggers (S2) and the epic summary line.
5. The views, the work panel, the director (S6).
6. A real run on Gra Słodziaki, B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | file reading, the trigger rule, restart limits | model tests | commit | an unknown key or an overlong value runs nothing |
| Integration | buttons, actions, views; sandbox refusals (S3) | request tests and a real sandbox-exec run | commit | another user's space cannot be built or served |
| E2E | S1, S4, S5 on a small test project; then Gra Słodziaki | real runs on this computer | release | — |

## 8. Expected Outcome

- **Direct effect:** one place shows whether each project builds and whether its server is up, with no terminal tabs.
- **Side effects:**
  - more processes on the computer (one server per space that has one);
  - CI after every step that changes files costs time.
- **Rollback:** revert the code; servers are stopped on the way out.

## 9. Additional Information

- **Rejected alternatives:**
  - commands typed on the space's form: the owner wants the project to describe itself;
  - running without a sandbox: an agent could put anything in the file.
- **External dependencies:** macOS `sandbox-exec` (deprecated by Apple but working, as used by Claude Code's own sandbox), Docker through Colima for projects that need it.
- **Sources and questions:**
  - Q1. Should a server also be started for a space while none of its epics runs, for example at Agentaro's start, if it was never started by hand? Proposed: no — only servers that were running are started again (G4). Accepted with the spec's closing (2026-11-23).
- **Implementation (2026-11-23):**
  - Migration `20261123110000`: the CI and server columns on `spaces`, and `task_runs.space_id`.
  - `Ci::Config` (safe YAML, four keys), `Ci::Sandbox` (sandbox-exec profile from spec 018's rules), `Ci.queue!` / `Ci.after_step` / `Ci.fingerprint`, `Ci::Runner` (purpose `ci`), `Ci::Server` (start, stop, check every 10 s in its own thread, restarts, recovery at start).
  - The scheduler runs a CI run only when no step or CI works in the folder, and a step waits while CI runs there.
  - After a step that changed files, CI is queued before the next step, so it runs between them.
  - Server logs are in `var/servers/<env>/<space>/server.log`. The sandbox hides `var/servers` except the space's own folder: a server's process must read the file its output goes to (found while testing — under a denied folder the server answered nothing).
  - Deviation from G3: an automatic CI run reports its result as one line in the chat ("CI of …: build and tests passed."), not inside the epic summary, which is written before the CI run ends.
  - Tests:
    - `ci_config_test.rb` (6) and `ci_runner_test.rb` (7), on the real sandbox, real processes and a real `python3 -m http.server`;
    - `space_ci_test.rb` (5).
  - Real run on a copy of Gra Słodziaki with `build: node build/build.mjs`, `test: node --test tests/` and `serve: node scripts/serve.mjs --port 8091`:
    - CI ok in 10 s (301 tests);
    - the server up, the page answered 200;
    - Stop stopped it.
    - The owner's repository was not changed; it has no `agentaro.yml` yet.
- **Security analysis (B20, after specs 001–052):**
  - Found and fixed, each with a test:
    - the folder check ran `git status` outside the sandbox, and a planted `core.fsmonitor` in `.git/config` ran a command (confirmed). Git now runs in the space's sandbox with fsmonitor and hooks off;
    - `url` could name any address, probed every 10 seconds and shown as a link. It must now be this computer.
  - Commands run with the minimal environment (no Agentaro secrets).
  - Every endpoint and action reaches only the owner's own spaces (404 tested).
  - Logs are shown escaped, with secrets replaced.
  - Archiving or deleting a space stops its server.
  - Brakeman 0 warnings.
- **Owner change (2026-11-23), G5:**
  - The owner's words: "dodaj jeszcze na karcie space, czy katalog ma Git i gdzie jest zdalne repo i czy worktree jest czysty, czy wymaga commita".
  - The space's card and page show, for a working folder:
    - "no Git", or the branch;
    - the remote (as host/owner/repo, never a login or token);
    - "clean", or "N to commit";
    - "N to push" and "N behind" when there is an upstream.
  - `Ci::Git` reads `git status --porcelain=v2 --branch` and the remote's address in the space's sandbox, with fsmonitor and hooks off (B20), cached for 30 seconds.
  - Test `space_git_test.rb` (3) on real repositories, including a planted fsmonitor and a token in the remote.

- **Owner change (2026-11-24), G4 — a server Agentaro lost:**
  - What happened: a step's final check stalled for 45 minutes. Its port was held by a server of the space that Agentaro had started itself the evening before but no longer tracked; every later start failed with "address in use" and was counted as a server that ended by itself (208 starts in the log).
  - Cause: two starts of one space in the same second. The restart after a good build and the 10-second check each read the space, each saw no live server and each spawned one; the record kept only the second pid, so the first was never stopped.
  - The owner's words: "Yes, fix it".
  - Rules:
    - R6. Starting, stopping and checking one space's server happen one at a time, on the space as it is saved now, not as a caller read it earlier.
    - R7. Agentaro remembers every server process it started for a space (its pid and start time) until it has seen that process end. Stopping or starting stops all of them, each only while its pid and start time still match (pids are reused). A server lost in any other way can no longer hold the port after the next start.
  - Data: a migration adds `spaces.server_processes` (the list of R7). Back up production first.
  - Rejected: a lock file in the space's log folder (the server's own sandbox may read that folder and could hold the lock); finding strays by folder or command (it could stop an agent's own test server in the same folder).
  - Gates: a test reproduces the double start with a stale copy of the space (fails before the fix: the first server outlives a stop); a test shows that a server process missing from the record is still stopped by the next start.
  - Implementation (2026-11-24):
    - `Ci::Server.locked` serializes `start!`, `stop!`, `check!` and `recover!` per space (a re-entrant `Monitor`) and reloads the space inside the lock.
    - `start!` appends each spawned process to `server_processes`; `stop_process` stops every listed process still matching its pid and start time (with its group), then clears the list.
    - Tests in `ci_runner_test.rb` (2); both failed before the fix (the second server replaced the first; the lost one survived the next start). 649 tests pass.
  - Security analysis (B20, after specs 001–053 and this change): the list lives in the database, which no sandbox can read or write, so a server cannot add a pid for Agentaro to stop; only processes whose pid and start time both match are signalled; no lock is shared with a sandboxed process. Brakeman 0 warnings; bundle-audit clean. No new findings.
