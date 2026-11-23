# 053 — A relaxed sandbox: web, local ports and Git

Status: **closed** 2026-11-23 (owner: "Zamknij i buduj"); **implemented** 2026-11-23.
Date: 2026-11-23
Depends on: [010](010-task-execution.md), [018](018-working-folders.md), [019](019-verifier.md), [052](052-space-ci-and-servers.md)

## 1. TL;DR

One setting on the Executors page, "Relaxed sandbox", on by default. With it on, command-line agents (Claude Code, Codex, Codex lokalny) keep their sandbox, but every run can:
- open any web page;
- open a local port, so an agent can start and check its own server;
- work with Git in a space's folder that had none: Agentaro creates the repository before the step.

Reads of Agentaro's storage, other spaces' folders and other runs stay denied. Tests and real runs on this computer confirm it.

## 2. Abstract

- **Current state** (checked on this computer, 2026-11-23):
  - Claude Code steps in a folder: the web works; opening a port fails ("Operation not permitted"); `git init` fails, and so does a commit in a `.git` made during the same run.
  - Claude Code outside a folder (director, verifier, steps without a folder): WebFetch works, but commands get no network.
  - Codex outside a folder (the verifier "Skeptic Agent"): no network for its commands, so it could not open workwithrondo.com.
  - Codex in a folder: the web, ports and `git init` all work.
  - CI and servers (spec 052): their own sandbox profile already allows the network, ports and writes in the folder.
- **Gap or problem:**
  - The owner's words: "chciałbym, żeby CLI działały poza sandboxem, bo nie mogą wchodzić na strony ani robić git init, bez sensu".
  - Production cases: an engineer could not check `/api/health` of its own server ("sandbox nie pozwala otworzyć portu"); the director and the verifier could not read workwithrondo.com.
- **Decision history:** the owner chose (2026-11-23):
  - relax the sandbox, do not turn it off;
  - for epic steps, the director and the verifier, and CI and servers;
  - one setting, on the Executors page, on by default;
  - Agentaro creates the Git repository before a step, when the folder has none.

## 3. Objective

**Goals**
- G1. **The setting.** "Relaxed sandbox" on the Executors page, saved on the owner's account, on by default. It applies to every command-line run of that account. When it is off, everything works as before this spec.
- G2. **The web.** With the setting on, every run of Claude Code, Codex and Codex lokalny may reach any host:
  - Claude Code: the sandbox's network allows all domains also outside a folder;
  - Codex and Codex lokalny: network access in the workspace sandbox also outside a folder.
- G3. **Local ports.** With the setting on, Claude Code's sandbox allows opening a local port (`allowLocalBinding`). Codex already allows it with network access.
- G4. **Git.**
  - With the setting on, before a step of an epic runs in a space's working folder that is not inside a Git repository, Agentaro runs `git init` there, outside the agent's sandbox, with an empty template (no hooks).
  - The step's prompt says the repository was just created.
  - A folder that is already inside a repository is left as it is.
  - It happens once per folder. If `git init` fails, the step still runs and its prompt says why there is no Git.
- G5. **What stays denied** (unchanged from specs 010 and 018):
  - reads of Agentaro's storage (databases, secrets), other spaces' folders and other runs (Claude Code);
  - writes outside the run's folder or the space's folder and temporary folders;
  - Codex still cannot limit reads (F17, accepted in spec 018).
- G6. **CI and servers.** Nothing to change: spec 052's profile already allows the network, ports and writes in the folder. A test keeps it that way.
- G7. **Seen.** The Executors page says what the setting allows and what stays denied. The director knows the setting's state, so it does not tell the owner a page "cannot be opened" because of the sandbox.

**Out of scope**
- Turning the sandbox off.
- `git push` credentials: an agent uses what the host's Git already has; nothing new is stored.
- Per-space or per-executor switches.

**Success criteria**
- S1. With the setting on, a Claude Code step in a folder starts a server on a local port and gets an answer from it.
- S2. With the setting on, the verifier on Codex opens a web page from a command (`curl`).
- S3. A step in a folder without Git commits its change; the folder now has a repository with no hooks.
- S4. With the setting on, a step still cannot read Agentaro's storage or another space's folder.
- S5. With the setting off, the run settings are exactly as before (tests).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `users.relaxed_sandbox` (boolean, default true) | to create |
| System | `AgentCall`: Claude Code settings (all domains, local binding), Codex network access, per the setting | to change |
| System | Git before a step: `git init --template=` outside the sandbox, the prompt note | to create |
| System | Executors page: the switch and its explanation; the director's context | to change |

## 5. Functional Domain Changes

- **State:** agents could not open pages, ports or new repositories → they can, inside the same sandbox for files.
- **Rules:**
  - R1. Only the network, local ports and the creation of a repository are relaxed. File rules do not change.
  - R2. `git init` is run by Agentaro, not by the agent: with an empty template (no hooks), in the space's folder only, the folder checked as in spec 018, and with Git's environment cleared (no `GIT_DIR`, no global hooks path).
  - R3. Only the owner of the account changes the setting; it is recorded in the data changelog (spec 004).
  - R4. Network access means an agent may send what it can read (its folder, its prompt) to any host. This is the risk the owner accepts with this setting; Agentaro's secrets stay unreadable (G5).
- **Resilience:** a failed `git init` never blocks a step. The setting cannot weaken CI (G6).
- **Data:** one migration. Back up production first.

## 6. Critical Path

1. Tests of the run settings with the setting on and off (S5, S4).
2. The settings in `AgentCall` (G2, G3).
3. Git before a step (G4, S3).
4. The Executors page and the director's context (G1, G7).
5. Real runs on this computer (S1–S4), B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | run settings per setting; git init rule | model tests | commit | storage and other folders always denied |
| Integration | the switch, ownership, the prompt note | request and runner tests | commit | another user cannot change it |
| E2E | S1–S4 | real Claude Code and Codex runs on this computer | release | a read of storage fails with the setting on |

## 8. Expected Outcome

- **Direct effect:** agents can check their own servers, read pages they are asked about, and commit in new projects.
- **Side effects:** more network traffic from agents; a new `.git` in spaces' folders that had none.
- **Rollback:** turn the setting off; or revert the code.

## 9. Additional Information

- **Rejected alternatives:**
  - turning the sandbox off: agents could read Agentaro's secrets, SSH keys and other projects;
  - excluding `git` from Claude Code's sandbox (`excludedCommands`): checked on this computer, Claude Code still denies writes inside a `.git` made during the run, so a commit after it fails; excluding all of `git` would also let hooks run outside the sandbox.
- **External dependencies:** Claude Code's sandbox (`network.allowedDomains`, `network.allowLocalBinding`), Codex's `sandbox_workspace_write.network_access`.
- **Sources and questions:**
  - Checks on this computer (2026-11-23), Claude Code 2.1.327 and Codex 0.170.0, with a probe script (git init, opening a port, curl):
    - Claude Code in a folder: git init fails, port fails, curl 200; with `allowLocalBinding` the port works;
    - Codex workspace-write with network access: all three work; without it, the port and curl fail.
  - Q1. Should Agentaro also create Git for a step whose plan does not mention Git? Proposed: yes, every step in a folder without Git (the owner chose "before a step"). Accepted with the spec's closing (2026-11-23).
- **Implementation (2026-11-23):**
  - Migration `20261123150000`: `users.relaxed_sandbox` (default true). Production backed up first.
  - `AgentCall`: with the setting on, Claude Code's sandbox gets `allowedDomains: ["*"]` and `allowLocalBinding: true` in every run (in a folder: the local binding added); Codex and Codex lokalny get `sandbox_workspace_write.network_access=true` in every run. File rules unchanged.
  - `WorkingGit.prepare` before each step: when the folder (or a folder above it) has no `.git`, `git init --quiet --template=` runs outside the agent's sandbox with Git's environment cleared (`HostProcess`); the step's prompt gets one line about it. No Git command runs in a folder that already has a repository (detection reads the disk only).
  - The Executors page has the switch (`PATCH /account/relaxed_sandbox`); the director's and the verifier's context says the sandbox's state (G7).
  - Tests: `relaxed_sandbox_test.rb` (8), `relaxed_sandbox_switch_test.rb` (2); `codex_local_test.rb` and `working_folder_test.rb` keep their old checks with the setting off and check the network with it on.
  - Real runs on this computer (demo data, deleted afterwards):
    - a Claude Code step in a folder without Git: commit in the new repository (no hooks), its own server on a local port answered 200, `curl` of workwithrondo.com 200, `ls` of Agentaro's storage "Operation not permitted" (S1, S3, S4);
    - Codex as a verifier, outside a folder: `curl` of workwithrondo.com 200 (S2).
- **Security analysis (B20, after specs 001–053):**
  - Found and fixed, with a test: the real Claude Code step above left its server running after the step ended (port 8797). It was started with `&` and its shell ended between two polls of the process tracker (spec 040), so it had no parent and a group of its own. At the end of a step, orphans of the same user started during the step whose working directory is in the step's folder are now stopped too. Test `detached_process_test.rb` (fails without the fix; a process working in another folder is left alone).
  - `git init` runs outside the sandbox but cannot run hooks or a planted configuration: it runs only where no repository exists, with an empty template and a cleared environment; the folder is a validated space folder (spec 018).
  - Accepted by the owner (R4): an agent with network access can send what it can read (its folder, its prompt) to any host. Agentaro's storage stays unreadable for Claude Code; Codex reads are not limited (F17, unchanged).
  - A local port opened by an agent is the project's business (as for CI servers, spec 052, R4); a server left behind is stopped at the end of the step.
  - The switch is behind sign-in and CSRF, changes only the signed-in account, and is recorded in the data changelog.
  - Brakeman 0 warnings; bundle-audit: no vulnerabilities.
