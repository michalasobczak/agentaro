# 054 — A space without a sandbox

Status: **closed** 2026-11-25 (owner: "Zamknij i buduj", Q1 and Q2 as proposed); **implemented** 2026-11-25
Date: 2026-11-25
Depends on: [010](010-task-execution.md), [018](018-working-folders.md), [052](052-space-ci-and-servers.md), [053](053-relaxed-sandbox.md)

## 1. TL;DR

A switch on a space's page, "No sandbox", off by default. When it is on, everything Agentaro runs for that space runs with the full rights of the Mac account: epic steps on Claude Code and Codex, CI commands and the space's server. The owner then no longer has to start anything by hand in a terminal. A real Codex call from the space's server confirms it.

## 2. Abstract

- **Current state:**
  - The space's server and CI (spec 052) run in `sandbox-exec`, which allows writes only in the working folder, the temporary folders and `/dev`.
  - Steps run in the sandboxes of Claude Code and Codex (specs 018, 053). Those sandboxes allow the network, local ports and Git, but writes stay in the folder.
- **Gap or problem:**
  - The space's server cannot run Codex, because Codex cannot write `~/.codex`. A program cannot open a sandbox of its own inside another one either.
    - Production case (2026-11-24/25): the server of a space on port 8765 logs "`codex` zakończył się kodem 1 … Operation not permitted". Claude in the same server gets an inherited token that expires (401).
  - The director's agents cannot restart such a server outside the sandbox. They ask the owner to do it in a terminal.
  - The owner's words: "dlaczego to ja musze cos zrobic?", "poproszę o poluzowanie max tych uprawnień, chcę żeby agent mógł sam działać".
- **Decision history:**
  - Spec 053 relaxed the sandbox and rejected turning it off, because agents could then read Agentaro's secrets.
  - The owner chose now (2026-11-25):
    - turn it off for everything: steps, CI and servers;
    - the switch is per space, not per account.

## 3. Objective

**Goals**
- G1. **The switch.** "No sandbox" on the space's page (`desktop-only`), off by default, stored on the space. Only the owner of the space changes it. Each change is recorded in the data changelog (spec 004). The page says plainly what the switch allows (R1).
- G2. **Steps.** With the switch on, an epic step of this space runs without a sandbox:
  - Claude Code: the sandbox is off and the permission mode allows every tool without asking (`bypassPermissions`);
  - Codex and Codex lokalny: `--sandbox danger-full-access`.
  The step still starts in the working folder, and the process tracker (spec 040) still stops it and the processes it leaves behind.
- G3. **CI and the server.** With the switch on, the CI commands and `serve` from `agentaro.yml` run without `sandbox-exec`. They start in the working folder, with the environment that the sandboxed run gets today. The server keeps its own process group and its tracking (spec 052, R6, R7).
- G4. **On a change of the switch.** A running server of the space is restarted under the new rules. A step that is already running keeps its rules until it ends.
- G5. **Context.** The director's context and the prompt of a step in this space say that the space has no sandbox. The director then does not ask the owner to start anything in a terminal "because of the sandbox".
- G6. **Off means as today.** With the switch off, steps, CI and servers run exactly as before this spec (tests).

**Out of scope**
- The director and the verifier. Their runs belong to no space, so they keep the sandbox of spec 053 (Q1).
- A switch on the account or on an executor.

**Success criteria**
- S1. With the switch on, the space's server starts Codex and Claude, and both answer.
- S2. With the switch on, a step writes a file outside its folder (in `~`), and Codex starts from a step command.
- S3. With the switch off, the run settings, the CI command and the server command are identical to today's (tests).
- S4. Another user cannot change the switch. The change is in the data changelog.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `spaces.no_sandbox` (boolean, default false) | to create |
| System | `AgentCall`: Claude Code and Codex arguments without a sandbox for a step of such a space | to change |
| System | `Ci::Server`, `Ci::Runner`: the command without `sandbox-exec` | to change |
| System | The space's page: the switch and its explanation; restart of the server (G4) | to change |
| System | The director's context and the step prompt (G5) | to change |

## 5. Functional Domain Changes

- **Rules:**
  - R1. **The risk the owner accepts.** With the switch on, an agent of the space and the space's code can read and change everything the Mac account can, and send it anywhere. That includes Agentaro's databases and secrets (`storage/`), SSH keys, other projects and the agents' own logins. A wrong or tricked step (for example, prompt injection from a web page) can do anything the owner could do.
  - R2. Only steps of epics in this space, its CI and its server lose the sandbox. Everything else keeps its rules.
  - R3. The switch applies at the start of a run. It never changes a run that is already going.
- **Resilience:** without `sandbox-exec`, CI and the server still need the working folder checked as in spec 018. A space without a valid folder runs nothing.
- **Data:** one migration. Back up production first.

## 6. Critical Path

1. Tests of the commands with the switch off (S3) and on.
2. `AgentCall` (G2), then `Ci::Server` and `Ci::Runner` (G3).
3. The switch, ownership, the changelog and the server restart (G1, G4, S4).
4. The context (G5).
5. Real runs on this computer (S1, S2), B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | commands per switch | model tests | commit | with the switch off, nothing changes |
| Integration | the switch, ownership, the changelog, the restart | request tests | commit | another user cannot change it |
| E2E | S1, S2 | a real server and step on this computer (demo data) | release | another space stays sandboxed |

## 8. Expected Outcome

- **Direct effect:** in a space with the switch on, agents start, restart and use tools such as Codex on their own. The owner no longer runs anything in a terminal.
- **Side effects:** R1. An agent's mistake in such a space can damage things outside the project.
- **Rollback:** turn the switch off (G4 restarts the server in the sandbox), or revert the code.

## 9. Additional Information

- **Rejected alternatives:**
  - Allowing only writes in `~` in the CI and server sandbox. Codex still could not open its own sandbox inside `sandbox-exec`, and the owner asked for the maximum.
  - A switch on the account. The owner chose per space.
- **External dependencies:** Claude Code `--permission-mode bypassPermissions` and `sandbox.enabled: false`; Codex `--sandbox danger-full-access`.
- **Questions:**
  - Q1. Should the director and the verifier also run without a sandbox? They are not in any space, so this would need a switch on the account. Proposed: no. The director restarts a server through Agentaro (G4), not by itself.
  - Q2. Should the first switch-on ask for a confirmation with R1 written out, as with deleting a space? Proposed: yes.
- **Implementation (2026-11-25):**
  - Migration `20261125090000`: `spaces.no_sandbox` (default false). Production backed up first.
  - `Ci::Sandbox.wrap` gives `/bin/sh -c` for a space without a sandbox, `sandbox-exec` otherwise. `Ci::Runner` and `Ci::Server` use it; `sandbox-exec` is required only for a sandboxed space. The server's log notes "no sandbox".
  - `AgentCall`: for a step of such a space (only steps carry a space), Claude Code gets `--permission-mode bypassPermissions` and `{"sandbox":{"enabled":false}}`, without `--allowedTools`; Codex and Codex lokalny get `--sandbox danger-full-access`.
  - `Space#set_no_sandbox!` saves the switch and restarts a wanted server. `PATCH /spaces/:id/sandbox` (only the owner's spaces; a space without a working folder is refused). The partial `spaces/_sandbox` with the confirmation (Q2: on every switch-on).
  - The step's prompt and the director's list of spaces say the space has no sandbox (G5).
  - Tests: `space_without_sandbox_test.rb` (9: commands with the switch off and on, the director keeps the sandbox, CI and the server write outside the folder only with it on, the restart, the prompt and the director's text); `space_sandbox_switch_test.rb` (4: the page and the confirmation, the data changelog, another user, a space without a folder, the form).
  - Real runs on this computer (demo data, deleted afterwards):
    - S1: a server running `codex exec` and `claude -p`. In the sandbox it failed with "failed to initialize in-process app-server client: Operation not permitted", as in production. Without the sandbox, both answered.
    - S2: a Claude Code step without the sandbox ran `codex exec` and wrote its answer to a file outside its folder.
- **Security analysis (B20, after specs 001–054):**
  - Who can turn it on: only the owner, on the space's page, after a confirmation. Behind sign-in and CSRF; another user gets 404. The space's form ignores the field (test). The director's `update_space` takes only kind, name, goal and description. Every change is in the data changelog.
  - Accepted (R1): an agent, CI command or server of such a space can read Agentaro's databases and secrets and change them. That includes turning the switch on for other spaces, or reading the audit chains. It can also detach processes that the end-of-step cleanup (spec 053) does not find. This is what "no sandbox" means. Other spaces stay sandboxed against their own agents.
  - Sandboxed spaces are unchanged: their commands are identical to before (tests). A sandboxed agent still cannot write Agentaro's storage, so it cannot turn its own sandbox off.
  - The environment of CI and the server is still only `PATH HOME USER LOGNAME LANG TMPDIR`. No Agentaro secret goes through the environment.
  - Brakeman 0 warnings; bundle-audit: no vulnerabilities.

