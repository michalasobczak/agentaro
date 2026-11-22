# 049 — Codex with a local model

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [008](008-executors.md), [018](018-working-folders.md), [022](022-model-lists-and-check.md), [038](038-live-step-view.md), [044](044-director-on-a-local-model.md)

## 1. TL;DR

A new executor preset, **Codex (local model)**, runs Codex with a model from the local Ollama (`--oss --local-provider ollama`). A local agent then gets tools (files, commands) from Codex's own loop and sandbox. "Lokalny inżynier" moves to it. Tests and a real step on this computer confirm it.

## 2. Abstract

- **Current state:**
  - An agent on Ollama (API) gets one chat request: text in, text out, with no tools.
  - On 2026-11-22 "Lokalny inżynier" (mimo-v2.6) was asked to read README.md. It answered only with a request for a `Read` tool that nobody ran. Since then, such a step fails with that reason.
  - Codex (codex-cli 0.170.0) already runs agents with tools in a sandbox (spec 018). It can use a local model with `--oss --local-provider ollama -m <model>`.
- **Checked on this computer (2026-11-22):**
  - `codex exec --oss --local-provider ollama -m mimo-v2.6 --json --sandbox read-only` was asked for the first line and the line count of a README.
  - It ran `ls` and `sed`/`wc` itself, answered from the results, and took 2 min 50 s.
  - It logged harmless errors about refreshing its model list.
- **Gap or problem:** the owner asked why a local model has no tools while Claude has. The tools belong to the agent program around the model, not to the model.
- **Decision history:** the owner chose (2026-11-22):
  - only "Lokalny inżynier" moves; the deputy director stays on Ollama (API), because it needs no tools and answers in seconds;
  - network as for Codex;
  - time limits from the plan, as now.

## 3. Objective

**Goals**
- G1. **The preset.** A new preset `codex_local`, "Codex (local model)":
  - the program is `codex`, the same one as the Codex preset;
  - the model is chosen from the local Ollama models, with mimo-v2.6 as the executor's default;
  - the executor check verifies the Codex version and that the model is present in Ollama.
- G2. **The call.**
  - The same arguments as the Codex preset (`exec`, `--skip-git-repo-check`, `--sandbox workspace-write`, `--ephemeral`, `-C <folder>`, `-o <answer>`, `--json`) plus `--oss --local-provider ollama -m <model>`.
  - Network only in a space with a working folder, as for Codex (spec 018, Q5).
  - No `--search`, because a local model has no web search.
  - No effort levels.
- G3. **Everything else as for Codex:**
  - the live step view and the trace (`CodexStream`, spec 038);
  - processes are followed and stopped (spec 040);
  - Stop works (spec 025).
  - There is no subscription limit to read (spec 043 skips it), and Codex's log lines about its model list are not errors of the step.
- G4. **The director knows the member.**
  - The team list says "on Codex (local model): files and commands, slower — give it time" instead of "text only".
  - The time limit is still the director's estimate in the plan.
- G5. **Production.**
  - A new executor "Codex lokalny" on this preset.
  - "Lokalny inżynier" moves to it with mimo-v2.6.
  - The deputy director stays on "Ollama na Mac Mini".

**Out of scope**
- A tool loop of Agentaro's own for Ollama (API).
- LM Studio as the local provider (Codex supports it; it can be added later the same way).
- Making local models faster.

**Success criteria**
- S1. A test with a stand-in `codex` checks the arguments:
  - `--oss --local-provider ollama -m mimo-v2.6`;
  - no `--search`;
  - the sandbox and `-C` as for Codex.
- S2. A real step on this computer: "Lokalny inżynier" reads a file in a space's working folder and gives its first line and line count. The step succeeds with the right answer, and its commands show in the live step view.
- S3. A step on this preset that hits a missing model fails with a plain reason ("the model mimo-v2.6 is not in the local Ollama").

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `Executor::PRESETS`: `codex_local` | to create |
| System | `AgentCall#cli_call` for `codex_local`; stream and process handling as for Codex | to change |
| System | executor check and model list from Ollama | to change |
| System | the director's member line (G4) | to change |
| Data | production executor "Codex lokalny"; "Lokalny inżynier" moved | to change (data, no migration) |

## 5. Functional Domain Changes

- **State:** a local agent is text only → a local agent on Codex has files and commands in Codex's sandbox.
- **Rules:**
  - R1. The model name passes the existing rule for model names (spec 022, R1) and goes to Codex as one argument.
  - R2. The sandbox and the denied folders are the Codex preset's (spec 018). Nothing is wider than for Codex.
  - R3. Codex's own configuration is not changed; everything is passed as arguments.
- **Resilience:**
  - Ollama not running: the step fails with Codex's error, cut to the reason.
  - A model Codex pulls on first use is pulled by Ollama itself (seen in the check). Agentaro does not pull models.
- **Data:** none in the schema.

## 6. Critical Path

1. A test with a stand-in `codex` (S1).
2. The preset, the call, the check and the model list.
3. The director's line (G4).
4. A real step on demo data (S2), then the production executor and agent (G5).
5. B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | S1, S3 | tests with a stand-in program | commit | no `--search`, and no wider sandbox than Codex |
| E2E | S2 | a real step with mimo-v2.6 on demo data | release | — |

## 8. Expected Outcome

- **Direct effect:** a local agent can read, change and test files in a working folder.
- **Side effects:**
  - local steps take minutes, even for small things;
  - a small model may lose its way in long tasks.
- **Rollback:** move the agent back; the preset stays unused.

## 9. Additional Information

- **Rejected alternatives:** Agentaro's own tool loop for Ollama. It would mean much code and a new security surface, for what Codex already does.
- **External dependencies:** codex-cli 0.170.0 (`--oss`, `--local-provider`), Ollama 0.40.15.
- **Sources and questions:** none open.
- **Implementation (2026-11-22):**
  - Preset `codex_local` runs `codex exec --json --oss --local-provider ollama … -m <model> -`. Its stream, live log, trace and process handling are Codex's.
  - `LocalModels` reads the local Ollama's `/api/tags` (`AGENTARO_OLLAMA_URL`, default 127.0.0.1:11434). It gives the model list, and it checks before a step that the model is there: Codex would otherwise start pulling it by itself (seen in the check).
  - The director's member line and the step review's list say "files and commands, but slower". The step view shows the log as for Codex.
  - Tests: `codex_local_test.rb` (5); `executor_test.rb` adapted (two presets run `codex`).
  - The real step found a fault the first tests missed: in a working-folder space the network option went between `--sandbox` and its value. Fixed, with a test.
  - Real step (S2) on demo data: "Lokalny inżynier" read README.md in the space's folder and answered "# Projekt Zielony" and 6 lines, both right, in 2 min 47 s. Its commands are in the trace.
  - Production: executor "Codex lokalny" (check OK, models from Ollama). "Lokalny inżynier" is on it with mimo-v2.6; the deputy director stays on "Ollama na Mac Mini".
- **Security analysis (B20, after specs 001–049):**
  - The sandbox and the network rule are Codex's (spec 018), with nothing wider; reads outside the folder are as for Codex (F17, accepted).
  - The model name passes the model-name rule and goes as one argument.
  - A missing model is refused before Codex runs, so no step can start an unplanned download of gigabytes.
  - Brakeman 0 warnings.

