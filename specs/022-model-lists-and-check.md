# 022 — Model lists, effort and a "Check model" button

Status: **implemented** 2026-11-20 (closed by owner: "Akceptuję, buduj" — Q1–Q4 proposals accepted)
Date: 2026-11-20
Depends on: [008](008-executors.md), [009](009-agents.md), [010](010-task-execution.md)

## 1. TL;DR

Picking a model no longer means remembering its exact name. The agent and executor forms offer a list of the models each tool reports, plus "other…" for any name. A **Check model** button sends one tiny question to the chosen model and shows whether it answered. Confirmed by tests and by checks on the owner's tools.

## 2. Abstract

- **Current state:** an agent's Model and an executor's Default model are free-text fields. The name is passed to the tool unchanged (Claude Code `--model`, Codex `-m`, Ollama and LM Studio by name). A wrong name shows up only when a step fails, with the tool's error (visible since the error-tail fix of 2026-11-20). The executor check (spec 008) shows only the tool's version, or the API's model list as plain text.
- **Gap:** the owner does not know which names exist or whether their account can use a given one. Nothing checks the name before work depends on it.
- **Need (owner, 2026-11-20):** "chcę móc podawać, konkretnie które modele są używane przez który executor"; "jeśli CLI zwracają listę dostępnych modeli, to chcę, żeby można było z listy wybrać"; "przycisk Sprawdź model będzie ok".
- **Found while writing this spec:** the model name is not checked for its form. A name that starts with `-` is passed as a separate argument to the tool (`ollama run <model>`, `lms chat <model>`), where it can be read as an option. Any user can set it on their private agent. R1 closes this.

## 3. Objective

**Goals**
- G1. **Model list per executor**, from the best source each tool has:
  - Ollama (CLI and API) and LM Studio (CLI and API): the tool's own list (`/api/tags`, `/v1/models`; `ollama list`, `lms ls`);
  - Codex: `~/.codex/models_cache.json`, the tool's own cache (unofficial, so a missing or changed file means an empty list, not an error);
  - Claude Code: the aliases `opus`, `sonnet` and `haiku` (the CLI has no list);
  - OpenAI-compatible servers: `/models`;
  - **plus names an admin adds** to the executor (e.g. a full Claude model name).
- G2. **A select in the forms**: the agent's Model and the executor's Default model offer "default" (agent only: the executor's default), the listed names and "other…" (a text field as today). A saved name that is not on the list stays as it is and is shown as "other".
- G3. **Refresh the list** with a button on the executor's page; the list and its time are stored on the executor, so forms do not call the tools.
- G5. **Effort** (owner, 2026-11-20: "a czy można podać effort?"): an optional Effort field next to Model on the agent and a default on the executor, passed only to tools that take it:
  - Claude Code: `--effort low|medium|high|xhigh|max`;
  - Codex: `-c model_reasoning_effort=<level>`, with the levels the model lists in Codex's cache (e.g. low … max, ultra);
  - other executors: the field is hidden.
  Empty means the tool's own default. Only listed values are accepted (no free text).
- G4. **Check model**: a button next to the Model field (agent form and executor form) runs one question ("Reply with the single word: ok") on that executor with that model. It shows ✓ with the answer time, or ✗ with the tool's error. The last result is kept on the agent or executor with its time, like the executor check.

**Out of scope**
- Prices, context sizes and other model details.
- Downloading models (`ollama pull`, LM Studio downloads).
- Checking models automatically on a schedule.

**Success criteria**
- S1. On the owner's Mac the forms list Codex models from its cache, Claude aliases, and Ollama or LM Studio models when installed (browser check).
- S2. Check model shows ✓ for `sonnet` on Claude Code and for a listed Codex model, and ✗ with the tool's message for a made-up name (manual check; tests with stubbed tools).
- S3. A model name starting with `-`, or with spaces or control characters, is refused on save (test).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `executors`: `models` (JSON list from the tool), `models_listed_at`, `extra_models` (admin's names) | to create |
| Data | `agents` and `executors`: `effort` (optional, from a fixed list per preset) | to create |
| Data | `agents` and `executors`: `model_checked_at`, `model_check_ok`, `model_check_output` | to create |
| System | `ModelList` (reads each tool's list, never raises) | to create |
| System | `ModelCheck` (one short call through the same path as steps, short timeout) | to create |
| System | Agent and executor forms: select with "default" / list / "other…"; Check model button | to change |
| System | Executor page: Refresh models button, extra names field | to change |
| System | Model name format rule (R1) on agents and executors | to create |

## 5. Functional Domain Changes

**Rules**
- R1. **Model name form:** letters, digits and `. _ : / @ -`, at most 200 characters, and not starting with `-`. Existing names that break this rule are reported on the edit form and do not run until fixed.
- R2. The list is only a help. Any name that passes R1 can be saved with "other…", because a tool may know models that it does not list.
- R3. **Check model** runs like a step (same program, same arguments, same minimal environment, its own temporary folder, no working folder, no web tools), with a 60-second timeout. It is not a task run and does not show on the calendar. The audit log records the request.
- R4. Who can check: whoever can edit the agent or executor (agents: owner or admin for shared; executors: admins). At most 10 checks per user per 10 minutes.
- R5. Reading a list runs only the preset's fixed program and arguments (spec 008, Q3), with a 10-second timeout. A tool that does not answer leaves the previous list in place, with an "out of date" note.

**Resilience:** a tool that is not installed or not running gives an empty list and an explanation. The forms still allow "other…".

**Data:** one migration adds the columns; all writes go through the data changelog.

## 6. Critical Path

R1 with tests → `ModelList` per preset (stubbed tools in tests) → columns and Refresh button → select in the forms → `ModelCheck` and its button → browser checks on the owner's tools → security analysis (B20).

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | each source parsed; missing or broken files give an empty list; R1 accepts real names and refuses `-x`, spaces, control characters | `test/models/*` | merge | no shell; no arguments from the web other than the model name |
| Integration | forms show the list; check shows ✓/✗; rate limit 429; a user cannot check someone else's private agent | `test/integration/*` | merge | no inline scripts (CSP) |
| Manual | S1, S2 on the owner's Mac | owner + browser | release | — |

## 8. Expected Outcome

- **Direct effect:** the owner chooses models from a list and knows before a step runs that the model answers.
- **Measurable effect:** S1–S3 pass.
- **Side effects:** each check uses one short request on the subscription; Codex's cache file may change format without notice.
- **Rollback:** remove the buttons and the select; the text field stays and works as today.

## 9. Additional Information

- **Rejected alternatives:** checking every name automatically on save (a slow save, and a cost on every edit); asking each CLI for its model list (Claude Code and Codex have no such command).
- **Technical debt:** the Codex list depends on an unofficial cache file.
- **External dependencies:** none new.
- **Questions:**
  - Q1. **Check on save for "other…"?** Proposal: no, only with the button; the form shows "not checked" next to a name typed by hand. **Accepted** (owner).
  - Q2. **Check model on the agent page too** (not only in the form), so a saved agent can be checked with one click? Proposal: yes, next to "Executor · model". **Accepted** (owner).
  - Q4. **Effort on a task step** as well (e.g. "high" for one hard step), or only on the agent and executor? Proposal: agent and executor only for now; a step that needs more effort gets an agent set up for it. **Accepted** (owner).
  - Q3. **Claude Code full names.** Proposal: the aliases only, plus whatever an admin adds on the executor; no list fetched from the internet. **Accepted** (owner).

## Implementation notes

- **Data.** `executors` gets `models` (JSON), `models_listed_at`, `models_note`, `extra_models`, `effort` and the last check (`model_checked_at`, `model_check_ok`, `model_check_output`); `agents` gets `effort` and the last check.
- **Lists.** `ModelList` reads each tool's list:
  - Codex: `~/.codex/models_cache.json` (`CODEX_HOME` honoured), hidden models left out, effort levels per model;
  - Ollama: `ollama list`; LM Studio: `lms ls --llm --json`; APIs: `ExecutorCheck#api_models`;
  - Claude Code lists nothing; `Executor#model_choices` adds the aliases and the admin's names.
- **Effort.** Only values in `Executor::EFFORTS` are stored and passed; `Agent#effective_effort` drops a level the current executor does not take.
- **Check model.** `ModelCheck` runs the question through `AgentCall` with a stand-in run (no task run, its folder removed afterwards). `ModelChecksController` answers JSON. The form's values are checked before they are saved; the result is kept on the saved agent or executor.
- **Forms.** `model_picker.js` turns the text field into a select ("Executor's default" / list / "Other…") and rebuilds it when the agent's executor changes. Effort shows only for Claude Code and Codex. Without JavaScript the text field and the effort select still work.
- **Q2.** Editors open an agent on its edit page, so Check model sits next to the model there. Read-only shared agents have no button (R4).
- **Executors.** The model picker, More model names and **Refresh models** appear on a saved executor's page. A new executor has the plain field.
- Checked on the owner's Mac (demo databases, deleted afterwards):
  - Codex listed 11 models with their levels;
  - `sonnet` with effort low answered in 3.6 s;
  - `gpt-6.1-terra` with effort low answered in 6.2 s;
  - `claude-made-up-9` showed Claude Code's own "doesn't recognize the model" error.

## Security analysis (Rondo B20) after spec 022

| # | Finding | Severity | Status |
|---|---|---|---|
| F-022-0 | **A model name could pass as an option.** Before this spec any user could save a model starting with `-` on a private agent. `ollama run <model>` and `lms chat <model>` would then read it as an option. | medium | **fixed:** rule R1 on save, a refusal at run time for older names, and tests. The owner's data had no such names. |
| F-022-1 | **Checks could block the server.** A check holds a server thread for up to 60 s, and the server has 3 threads, so three parallel checks would block the app, voice included. | medium | **fixed:** one check at a time (409 otherwise). Test added. |
| F-022-2 | **Any signed-in user can check any enabled executor.** This includes checks from the new-agent form, which run a fixed question. | low | **accepted:** the same as creating a private agent and running it. Limited to 10 per user in 10 minutes. |
| F-022-3 | **The Codex cache is an unofficial file.** It is read from the Agentaro account's home folder. | low | **accepted:** size limit 5 MB, parse errors give an empty list, names filtered by R1, levels filtered by `EFFORTS`. |

Specs 001–021 were re-read for regressions:
- the CSP and textContent rules hold (the list data is an escaped attribute; no inline script);
- the data changelog records the check results (`save!(validate: false)` runs callbacks; no bulk writes);
- executor programs keep fixed presets, a minimal environment and no shell.

Brakeman: no warnings. bundle-audit: no vulnerabilities.
