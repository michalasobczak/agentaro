# 018 — A working folder for a space

Status: **implemented** 2026-11-20, F17 and F18 accepted by the owner (closed by owner: Q5 "Codex też", Q6 "Docker teraz"; other Q6 proposals accepted)
Date: 2026-11-20
Depends on: [010](010-task-execution.md), [014](014-spaces.md), [016](016-sequential-steps.md)

## 1. TL;DR

A space can have a **working folder** on the host, e.g. the folder with Agentaro's code. Every step of every epic in that space runs **in that folder**. There agents work like a developer:
- they edit files directly;
- they run system tools (git with commit, push and merge, Docker, a browser, other command-line tools);
- they use the network: HTTP, APIs and package managers.

Agentaro enforces one limit: an agent **cannot read the working folders of other spaces**, nor Agentaro's own `storage/`. Confirmed by tests and by real runs on the host.

## 2. Abstract

**Current state (spec 010).** Every step runs in its own empty folder (`var/runs/<env>/<id>/work`). Claude Code may write only there; Codex writes only there and has no network for commands. Agents cannot work on an existing project.

**Need (owner, 2026-11-20).**
- "interesuje mnie, żebym dla projektu mógł wskazać katalog roboczy, np. katalog z kodem agentaro"
- On access: "bezpośrednia edycja, ale nie może zaglądać do innych projektów; może uruchamiać narzędzia systemowe, np. docker, przeglądarkę, ale nie może czytać cudzych projektów plików"
- On results: "model / agent ma robić to, co mu powiem, tj. commit, push, merge, CLI, API, HTTP, cokolwiek, bez szczególnych ograniczeń"
- On scope: "folder jest dla przestrzeni, tam można po prostu na niej pracować"

**Owner decisions.**
- Q1: agents edit the folder directly.
- Q2: any user may set any folder.
- Q3: agents do whatever the step asks, without special limits, except the read limit below.
- Q4: the folder belongs to the space, and every step of the space works in it.
- Read limit (Q1): no reading other spaces' folders ("cudzych projektów").

## 3. Objective

**Goals**
- G1. A space has an optional **working folder**: an absolute path to an existing directory on the host, set on the space form (and by the director with `update_space`). The space page shows it.
- G2. Every step of an epic in that space runs with that folder as its working directory, on Claude Code or Codex. Ollama and LM Studio answer text only, as before.
- G3. **Freedom inside** (Q3):
  - agents read and write anything in the folder;
  - they run any command, including git (commit, push, merge), Docker, a browser and package managers;
  - they reach any network host.
- G4. **Read limit** (enforced by the executor's sandbox, not by asking the model): no reading of
  - the working folders of other spaces (of all users);
  - Agentaro's `storage/` (databases, secrets, voice models);
  - the run folders of other runs.

  Writes outside the working folder and the temporary folders are refused.
- G5. Spaces without a folder work as today (an empty run folder, spec 010).
- G6. The step prompt states the working folder and that the agent may change it, run tools and use the network.
- G7. The space page and the epic page show the working folder; the step's prompt names it.

**Out of scope**
- Copies per epic (git worktree), automatic branches or pull requests: the owner wants the agent to do what the step says (Q3).
- Shared spaces.

**Success criteria**
- S1. A step in a space with a folder edits a file in it, commits with git and runs a Docker or network command (real run on the host).
- S2. The same step cannot read a file in another space's folder or in Agentaro's `storage/` (real run: the read is refused) — for each executor where it can be enforced (Q5).
- S3. Spaces without a folder behave as before (tests).
- S4. A folder that does not exist, is not absolute or is inside Agentaro's `storage/` is refused (tests).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `spaces.working_dir` (absolute path, optional) | to create |
| System | `AgentCall`: working directory per step; Claude Code sandbox settings per run (write: folder + temp; read denied: other folders + storage; network open; Docker socket allowed); Codex sandbox per run | to change |
| System | Space form and page; director's `update_space`; step prompt; epic page | to change |

## 5. Functional Domain Changes

**Rules**
- R1. The folder must be an absolute path to an existing directory. It is stored resolved (no symlinks or `..`), and it may not be `/`, Agentaro's `storage/` or a folder inside it.
- R2. Two spaces may share a folder. Their steps then run in the same place. The steps of one epic still run one at a time (spec 016), but epics of different spaces may run at the same time in a shared folder.
- R3. The read limit covers every other space's folder at the time of the run, of all users.
- R4. Running the app's own code folder is allowed (owner). Edits there change the code of the running instance; they take effect only after a restart.

**Resilience:** if the folder disappears, the step fails with "Working folder not found" and the epic is blocked (spec 016).

**Data:** one nullable column.

## 6. Critical Path

Column and validation → sandbox settings per run (Claude Code, Codex) → working directory per step → prompt and pages → real runs on the host: edit, commit, network, Docker; refused reads → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | folder validation; sandbox settings per run contain the right allow and deny lists | `test/models/space_test.rb`, `agent_call_test.rb` | merge | storage and other folders always denied |
| Integration | space form, epic page | `test/integration/spaces_test.rb` | merge | other users' spaces 404 |
| E2E | real steps: edit + commit + network + Docker; reads of another folder and storage refused | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** agents can work on real projects, such as Agentaro itself.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** agents can change code, push to remote repositories, run containers and spend network and machine resources on the owner's behalf.
- **Rollback:** clear the folders; steps run in empty folders again.

## 9. Additional Information

- **Rejected alternatives:**
  - git worktree per epic (the owner: direct editing);
  - read-only folders (the owner: direct editing);
  - an admin allow-list of folders (the owner: any user, any path);
  - branches or pull requests made by Agentaro (the owner: the agent does what it is told).
- **Technical debt:** see Q5.
- **External dependencies:** Claude Code and Codex sandboxes.
- **Questions:**
  - Q1–Q4 answered by the owner (see Abstract).
  - Q5. **Executors in a space with a folder.** Checked on the host (2026-11-20) with Claude Code, its sandbox and a test folder:
    - **reads of a denied folder are refused** for the Read tool, for `cat` and for a Python script ("Operation not permitted");
    - **writes outside the folder** (e.g. the home folder) are refused;
    - **network is open** with `allowedDomains: ["*"]`: `curl` and `git ls-remote https://github.com/...` worked. This is not documented but verified;
    - **git commit works** once `Bash` is allowed (commands stay inside the sandbox).

    Codex's sandbox cannot deny reads of chosen folders. **Owner: Codex works in folders too** ("Codex też"). It writes only in the folder and has the network, but **it can read other projects**: accepted risk for Codex steps (F17).
  - Q6. **Limits that remain.**
    - Claude Code always protects `.git/config` and `.git/hooks` from writes, so agents cannot add remotes or change git settings. Set remotes yourself; push and pull to existing remotes work over HTTPS. SSH remotes are not yet checked.
    - **Owner: Docker now** ("Docker teraz"). Installed as Colima (a headless Docker VM, MIT) and the docker CLI from Homebrew. Steps may use it. Containers can mount any folder of the host, which **bypasses the read limit**: accepted by the owner (F18).
    - Writes outside the folder and the temp folders are refused, so e.g. global package installs fail: **accepted**.
    - `.git/config` and `.git/hooks` stay protected: **accepted**.

## Owner fix after release (2026-11-20)

- "daj dynamiczny podgląd ścieżek podczas pisania w Working folder… nie znam dokładnej nazwy katalogu": while typing, a list under the field shows matching folders (case-insensitive prefix; `~` is the home folder). Arrows with Enter or Tab, or a click, take a folder and show its subfolders. A note says whether the typed folder exists. The list shows folder names only, never files. Hidden folders appear only when the typed name starts with a dot. Nothing inside Agentaro's `storage/` and runs, or inside other users' space folders, is listed (G4). Endpoint `GET /spaces/folders?path=…`, signed-in users only, at most 300 requests a minute.

## Security analysis (B20), after spec 018

Scope: this spec and specs 001–017.

- **Verified on the host** (Claude Code, real step in a space with a folder, another user's space with a folder holding a secret): the step edited a file, committed with git, ran a Docker container and reached `https://example.com`; reading the other folder was refused for both `cat` and the Read tool, and the secret did not appear in the answer.
- **Read limit (G4).** For Claude Code: OS-level sandbox `denyRead` plus `Read`/`Edit` deny rules for every other space's folder (all users), Agentaro's `storage/` and the runs folder (tests check the settings of each run). `failIfUnavailable` stops a run rather than running it without the sandbox; no unsandboxed retries.
- **F12 → owner's decision.** Any user may point a space at any folder (Q2) and agents act freely there (Q3). An Agentaro account therefore means access to the host account's files, apart from other spaces' folders and Agentaro's storage. README says: give accounts only to people you trust with your Mac account.
- **F17 (accepted by the owner, Q5).** Codex steps in a folder can read other projects; Codex's sandbox cannot deny chosen folders.
- **F18 (accepted by the owner, Q6).** Docker is open to steps. A container can mount any folder of the host, so a step can bypass the read limit through Docker.
- **Prompt injection.** An agent with network, git push and Docker that reads hostile text can act on it within its folder and the network; nothing in Agentaro can stop that, only the read limit keeps other projects and Agentaro's secrets out.
- **Validation (R1).** Folders are resolved (no symlink tricks) and may not be `/`, `storage/` or the runs folder (tests). The director can set a folder with `update_space`, with the same checks.
- **Host setup.** Colima (Docker VM: 2 CPUs, 4 GB, 30 GB) was installed and started with the owner's consent; it does not start by itself after a reboot unless enabled (`brew services start colima`).
- **Folder suggestions.** They reveal folder names on the host to signed-in users. This follows from Q2 (any user, any path) and is no more than the folder field already allows. Contents of protected folders and of other users' space folders are not listed (test).
- **Regressions in 001–017.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities. Spaces without a folder run exactly as before (test).
