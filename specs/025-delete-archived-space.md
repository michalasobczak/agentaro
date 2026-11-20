# 025 — Delete an archived space

Status: **closed** 2026-11-20 (the owner's decisions Q1–Q3 in the chat); **implemented** 2026-11-20.
Date: 2026-11-20
Depends on: [013](013-projects.md), [016](016-sequential-steps.md), [018](018-working-folders.md)

## 1. TL;DR

An archived space can be deleted together with its epics, their steps, calendar entries and runs. A confirmation shows what will go. Steps still running in it are stopped first. Tests and a browser check confirm it.

## 2. Abstract

- **Current state:**
  - Only an empty space can be deleted. Others can only be archived (spec 013, R5, Q6).
  - An archived space keeps its epics forever.
  - Archiving stops nothing that already runs (spec 013, R4).
  - Nothing can stop a step's agent once it has started: cancelling an epic lets a running step finish.
- **Gap or problem:** the owner's archived spaces fill the space list and the database with work they no longer want ("powinno dać się skasować space po archiwizacji, po pytaniu, czy na pewno").
- **Rationale:** archiving was meant as a step before removal, but there is no removal.
- **Decision history:** spec 013 Q6 chose "only when empty; otherwise archive". This spec lifts that rule for archived spaces only. Active spaces keep it.

## 3. Objective

**Goals**
- G1. **Delete button for archived spaces.** An archived space's page has **Delete**, whatever it holds.
- G2. **Confirmation.** A browser dialog names the space and counts what goes. It also says how many steps are running and will be stopped, and that this cannot be undone. One OK confirms (Q2).
- G3. **What is deleted** (Q1): the space, its epics, their steps, calendar entries, runs and the runs' folders on disk.
- G4. **Running steps are stopped** (Q3): queued steps are skipped, and the agent processes of running steps are stopped. Deletion then goes ahead.
- G5. **Active spaces keep spec 013 R5.** They can be deleted only when empty; otherwise they are archived first.

**Out of scope**
- An undo or a trash bin.
- Deleting a space's working folder (spec 018): it is the user's own folder and is never touched.
- Stopping a step on its own (a "Stop" button on a running step). The mechanism exists after this spec; the button would be a new spec.

**Success criteria**
- S1. Deleting the owner's archived "General" space (12 epics) leaves no epic, step, calendar entry, run or run folder of it.
- S2. A step running in the space is stopped within seconds, and the space is deleted.
- S3. Other spaces, other users' data and the chat history are unchanged. A director answer that was linked to a deleted run keeps its text.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `Space#purge!`: stop, skip, delete in order, remove run folders | to create |
| System | `RunControl`: running agent processes by run id; `stop!` | to create |
| System | `HostProcess.run(on_spawn:)`; `AgentCall` registers its process | to change |
| System | `SpacesController#destroy`; space page button and confirmation | to change |
| Data | rows deleted through callbacks (data changelog records each); no schema change | — |

## 5. Functional Domain Changes

- **State:** an archived space with epics can be deleted (it could only be archived before).
- **Rules:**
  - R1. **Only the owner, only archived spaces.**
    - Only the space's owner can delete it (others get 404, as with every space action).
    - An archived space is deleted with everything in it. An active one still only when empty (spec 013, R5).
  - R2. **Confirmation text.** "Delete <name> with N epics, their steps and runs? M running steps will be stopped. This cannot be undone." The running part appears only when M > 0.
  - R3. **Stopping.**
    - Queued runs of the space's epics become skipped ("The space was deleted.").
    - Running runs are stopped: the agent's whole process group is killed.
    - Deletion waits up to 10 seconds for them to end. A run that does not end in time (a model reached over HTTP) is marked failed and deleted anyway. Its late answer is dropped.
  - R4. **Order, in one transaction.**
    1. Chat messages linked to the runs lose the link and keep their text.
    2. The runs are deleted.
    3. The epics' calendar entries are deleted.
    4. The epics are deleted, with their steps.
    5. The space is deleted.

    Each row goes through the model's callbacks, so the data changelog (spec 004) records it.
  - R5. **Run folders.**
    - After the commit, each deleted run's folder `<runs dir>/<run id>` is removed.
    - Only that exact path is removed: a number under Agentaro's runs folder.
    - The space's working folder is never touched.
- **Resilience:**
  - If the deletion fails, the transaction rolls back and nothing is deleted. Steps already stopped stay stopped, and the page says so.
  - A step's worker that ends after the deletion finds no records; it writes nothing and only logs.
- **Data:** no migration.

## 6. Critical Path

1. `RunControl` and `HostProcess(on_spawn:)`.
2. `Space#purge!`.
3. Controller and page.
4. Tests (model, integration, stopping a real process).
5. A browser check on demo data.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | purge deletes epics, steps, tasks, runs, folders; keeps chat text; other spaces untouched; a running stand-in agent is killed and deleted | `test/models/space_purge_test.rb` | merge | an active space with epics is refused; nothing outside the runs folder is removed |
| Integration | Delete shown on archived spaces with the counted confirmation; other users get 404; active non-empty still refused | `test/integration/spaces_test.rb` | merge | no inline `style=` |
| E2E | delete an archived space with epics on demo data | browser, demo | release | — |

## 8. Expected Outcome

- **Direct effect:** archived spaces can be removed with everything in them.
- **Measurable effect:** no rows left with that space's epics' ids.
- **Side effects:** run pages of deleted runs return 404, and links from the chat to them disappear.
- **Rollback:** revert the code. Deleted data comes back only from a database backup.

## 9. Additional Information

- **Rejected alternatives:**
  - Keeping the runs as history (Q1: delete them).
  - Typing the space's name to confirm (Q2: a dialog with counts).
  - Refusing while a step runs (Q3: stop it and delete).
- **Technical debt:** a model reached over HTTP cannot be interrupted mid-answer; its run is deleted and its late answer is dropped (R3).
- **External dependencies:** none.
- **Sources and questions (answered by the owner on 2026-11-20):**
  - Q1. Epics of the space? Deleted with it, runs included.
  - Q2. Confirmation? A dialog with counts.
  - Q3. A step still running? Stop it and delete.

## Security analysis (B20), after spec 025

- **Who can delete.** Only the owner: the controller loads the space from the user's own spaces, so other users get 404 (test).
- **Active spaces.** They still cannot lose epics; `purge!` refuses one (test).
- **Stopping.**
  - `RunControl` kills only process groups that Agentaro started itself and registered by run id. Nothing from a request names a process.
  - Model checks (spec 022) register too, under their stand-in run, and are not touched by deletion.
- **Files.**
  - Only `<runs dir>/<integer id>` is removed, after checking that its parent is the runs folder and that it is a directory, not a symlink.
  - A space's working folder is never touched.
- **Audit.** Rows are destroyed one by one through callbacks, so the data changelog records each deletion. No bulk writes (`test/no_bulk_writes_test.rb` passes).
- **Denial of service.**
  - Deleting waits at most 10 s for stopped steps, inside one request; with 3 Puma threads this is accepted for a rare, owner-only action.
  - A model reached over HTTP is not interrupted. Its late answer finds no records and is dropped (technical debt, §9).
- **Tools.** Brakeman: 0 warnings. No new gems.
