# 055 — opencode as an executor

Status: **closed** 2026-11-25 (owner: "Zamknij i buduj", Q1–Q3 as proposed); **implemented** 2026-11-25
Date: 2026-11-25
Depends on: [008](008-executors.md), [010](010-task-execution.md), [022](022-model-lists-and-check.md), [030](030-run-traces.md), [038](038-live-step-view.md), [044](044-director-on-a-local-model.md), [054](054-space-without-sandbox.md)

## 1. TL;DR

A new executor preset, "opencode", for the opencode command-line tool. With it, any agent can work on opencode's models, including the free `opencode/deepseek-v4.1-flash-free`: the director, the verifier and members doing steps. opencode has no sandbox of its own, and the owner chose to run it without one. Real runs on this computer confirm it.

## 2. Abstract

- **Current state:**
  - Executors are fixed presets (spec 008): Claude Code, Codex, Codex with a local model, Gemini, Grok, Ollama and LM Studio.
  - The command-line agents run in their tools' own sandboxes (specs 010, 018, 053), unless the space has none (spec 054).
- **Gap or problem:** the owner's words: "potrzebuję dodać opencode CLI do agentaro … chcę użyć free modeli deepseek v4 flash".
- **Checked on this computer (2026-11-25):**
  - opencode 2.4.1 comes with the desktop app. Its CLI is `~/Library/Application Support/ai.opencode.desktop/cli/2.4.1-arm64/opencode-cli`, which is not on `PATH`.
  - `opencode models` lists, among others:
    - free models such as `opencode/deepseek-v4.1-flash-free`, `opencode/big-pickle` and `opencode/mimo-v2.6-flash-free`;
    - the local Ollama models (`ollama/qwen3:8b`).
  - `opencode run --standalone --archived --format json -m opencode/deepseek-v4.1-flash-free`:
    - it reads the message from standard input;
    - it writes one JSON event per line (`step_start`, `text`, `step_finish` with tokens and cost);
    - "Reply with exactly: stdin-ok" was answered in a few seconds, at cost 0.
  - opencode keeps its sessions in `~/.local/share/opencode/opencode.db`.
- **Decision history:** the owner chose (2026-11-25):
  - no sandbox, always;
  - every role: steps, the verifier and the director;
  - Agentaro finds the CLI on `PATH`, then in the desktop app; `AGENTARO_OPENCODE_BIN` overrides both;
  - the model list is everything `opencode models` lists.

## 3. Objective

**Goals**
- G1. **The preset.** "opencode" (key `opencode`, command line), added by an admin like the other presets. Its default model is `opencode/deepseek-v4.1-flash-free`.
- G2. **Finding the CLI**, in this order:
  - `AGENTARO_OPENCODE_BIN`;
  - `opencode` on `PATH` and in the usual folders (spec 008);
  - the newest `opencode-cli` of the desktop app (`~/Library/Application Support/ai.opencode.desktop/cli/*/opencode-cli`).
  "Check" shows the version, as for the other presets.
- G3. **Models.** "Refresh models" reads `opencode models` (spec 022). Extra model names can be added by hand, with the usual rule for names. There are no effort levels (Q3).
- G4. **A run.** `opencode run --standalone --archived --auto --format json -m <model>`. Details:
  - the prompt goes on standard input;
  - it runs in the space's working folder for a step, and in the run's own empty folder otherwise (spec 010);
  - the answer is the text of the `text` events;
  - tokens and cost from `step_finish` go into the run trace (spec 030);
  - the live view shows the text and the tool calls as they come (spec 038);
  - time limits, stopping and the process tracker are as for every command-line run.
- G5. **No sandbox.** opencode always runs with the full rights of the computer's account, whatever the space's switch says. The Executors page, the executor's form and the director's context say so (R1).
- G6. **Every role.** An agent on opencode may be a member, the verifier, the director or the deputy:
  - the director's answers are held to the JSON shapes by Agentaro's checks (spec 011), not by a grammar: opencode takes no schema;
  - the short prompt for local models (spec 044) is not used.

**Out of scope**
- A sandbox for opencode.
- opencode's own agents, plugins, MCP servers and sessions: Agentaro runs one archived session per call and never continues one.
- Logging in to paid providers through opencode (`opencode auth`): the owner does that in opencode itself.

**Success criteria**
- S1. "Check" finds the CLI of the desktop app and shows "opencode v2.4.1".
- S2. "Refresh models" lists `opencode/deepseek-v4.1-flash-free`.
- S3. A real step on `opencode/deepseek-v4.1-flash-free` in a space's folder changes a file. The live view shows its progress, and the trace has its tokens.
- S4. A real director's chat reply on that model, with an action, is applied.
- S5. The other presets run exactly as before (tests).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `Executor::PRESETS`: `opencode`; finding the CLI (G2); its model list | to change |
| System | `AgentCall`: arguments, the JSON event reader (like `CodexStream`), usage | to change |
| System | The Executors page and the form: "no sandbox" said plainly; the director's context | to change |

## 5. Functional Domain Changes

- **Rules:**
  - R1. **The risk the owner accepts.** An agent on opencode can read and change everything the Mac account can: Agentaro's databases and secrets, SSH keys and other projects. It can also send them to the model's provider. The free models run on opencode's servers, so what the agent reads (its prompt, files, outputs) leaves this computer under opencode's terms (Q1).
  - R2. The model name is one argument and is checked by the rule of spec 022. The prompt never goes on the command line (standard input only).
  - R3. opencode's environment is the one other command-line runs get. No Agentaro secret goes through it.
- **Resilience:**
  - A failed or empty answer is a failed run, retried as other runs are (specs 032, 040).
  - A free model that is unavailable or rate-limited ends with opencode's error text in the run.
- **Data:** no migration (the preset is a key).

## 6. Critical Path

1. Tests: the arguments, the event reader (text, tools, usage, a split chunk), finding the CLI (S5).
2. The preset, the CLI and the model list (G1–G3).
3. The run (G4), the warnings (G5), the roles (G6).
4. Real runs on this computer (S1–S4), B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | arguments, reader, finding | model tests | commit | a model name starting with "-" is refused |
| Integration | executor form, check, models | request tests | commit | other presets unchanged |
| E2E | S1–S4 | real runs on this computer (demo data) | release | — |

## 8. Expected Outcome

- **Direct effect:** agents can work on free opencode models, without a Claude or Codex subscription.
- **Side effects:** R1. A weaker free model may plan or answer worse; Agentaro's checks still apply.
- **Rollback:** delete the executor, or revert the code.

## 9. Additional Information

- **Rejected alternatives:**
  - `sandbox-exec` around opencode, as for CI. Rejected by the owner: no sandbox.
  - Using opencode's background service instead of `--standalone`. The service is shared with the desktop app and with the owner's own sessions. A private server per run is slower to start but separate.
- **External dependencies:** opencode CLI 2.4.1 (`run`, `models`, `--format json`), and opencode's free models (availability and limits set by opencode).
- **Questions:**
  - Q1. Free models on opencode's servers may log or use what they are sent. Is that acceptable for every role, including the director, which sees the whole work list and conversation? Proposed: yes, as the owner's choice (R1); the Executors page says it.
  - Q2. `--auto` approves every tool opencode asks for (shell, edits, web). Without it, a run stops at the first question and ends at its time limit. Proposed: `--auto`.
  - Q3. opencode takes model variants (`provider/model#variant`) instead of efforts. Proposed: none for now. The rule for model names (spec 022) does not allow "#", so a variant cannot be written by hand either.
- **Implementation (2026-11-25):**
  - `Executor::PRESETS`: `opencode` (command line, program `opencode`). The default model `opencode/deepseek-v4.1-flash-free` is set when none is chosen; `Executor#unsandboxed?`.
  - `ExecutorCheck.locate("opencode")` looks in this order: `AGENTARO_OPENCODE_BIN` (a wrong value finds nothing, it is not silently replaced), the path and the usual folders, then the desktop app's `cli/*/opencode-cli` with the highest version number. "Check", "Refresh models" and runs all use it.
  - `ModelList`: `opencode models`, one name per line, with the rule for names (spec 022). It gets 30 seconds, because opencode first reads its providers' lists.
  - `AgentCall`: `run --standalone --archived --auto --format json -m <model>`, the prompt on standard input. `OpencodeStream` reads the events:
    - the text of the last step that wrote any is the answer;
    - tools become `tool_use` and `tool_result` for the live view and the trace;
    - tokens and cost are summed over steps;
    - an `error` event becomes the run's error, and an empty answer is a failed run;
    - lines are cut from bytes, as in the fix of 2026-11-24.
  - The Executors page shows a warning once an opencode executor exists. The executor's form says it in its hint, and the director's list of members says "on opencode with <model>: files, commands and the web, no sandbox".
  - Tests: `opencode_executor_test.rb` (8) and one in `executors_test.rb`. In `executor_test.rb` the list of preset programs now includes opencode.
  - Real runs on this computer (demo data, deleted afterwards), with opencode 2.4.1 found in the desktop app and `opencode/deepseek-v4.1-flash-free`:
    - S1: "Check" showed "opencode v2.4.1".
    - S2: "Refresh models" listed 12 models, the free DeepSeek among them.
    - S3: a step fixed `calc.py` in a space's folder (`a - b` → `a + b`) and checked it with `python3`; the trace has 7753/361 tokens, 4 turns and 7 events.
    - S4: the director on opencode answered "Dopisałem mnożenie do listy…", and "Added to the list: Dodać mnożenie" was applied.
- **Security analysis (B20, after specs 001–055 and 050):**
  - Accepted by the owner (R1, Q1): an agent on opencode has the account's full rights in every space, including sandboxed ones. It can read Agentaro's storage and change it, for example turn other spaces' sandbox off. A web page or file it reads can steer it (prompt injection) with those rights. Its prompts and what it reads go to opencode's servers for free models, and opencode keeps the archived sessions in `~/.local/share/opencode/opencode.db`. Agentaro says this on the Executors page and on the form.
  - Unchanged for the other presets: their arguments and sandboxes are as before (tests).
  - R2 holds: the model name is checked and passed as one argument, the prompt goes only on standard input, and the arguments are fixed in code.
  - The CLI found in the desktop app's folder is trusted like any program on the path: the folder belongs to the same account.
  - Brakeman 0 warnings; bundle-audit: no vulnerabilities.

