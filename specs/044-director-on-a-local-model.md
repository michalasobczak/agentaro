# 044 — The director on a local model (Ollama)

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [011](011-list-and-management.md), [022](022-model-lists-and-check.md), [043](043-usage-limits-and-deputy-director.md)

## 1. TL;DR

A director on Ollama with a local model (on this computer qwen3.5:9b) can turn the owner's spoken words into valid work-list actions: add epics, plan them, change settings and answer about status. It gets a short prompt made for local models, a context large enough for that prompt, and its answer is forced into the JSON shape. A scripted acceptance run with Polish requests proves it.

## 2. Abstract

- **Current state:**
  - The director's chat prompt is 60–150 KB (about 15–40 thousand tokens; measured on production runs 838–854).
  - For Ollama it is sent to `/api/chat` with no context size, no output format and thinking left on.
  - Ollama keeps only as much as its default context holds (a few thousand tokens), so the model sees a cut prompt. It cannot answer with the required JSON.
  - LM Studio and OpenAI-compatible servers get the same prompt.
- **Gap or problem:** the owner's words: "upewnij się, że ollama z lokalnym modelem poprawnie zadziała jako director w tym sensie, że mówię do modelu, a on potrafi wygenerować formalną strukturę zarządzania epikami i agentami".
- **Rationale:** a local director costs nothing per call. With spec 043 it is the natural deputy when Claude or Codex is at its limit.
- **Decision history:** the owner chose a short prompt for local models (2026-11-22), not the full prompt in a large context.

## 3. Objective

**Goals**
- G1. **Short prompt.** When the director (or deputy) runs on a local executor (Ollama, LM Studio, OpenAI-compatible), its prompt keeps these limits:
  - target ≤ 24 KB (about 6–8 thousand tokens) for the chat;
  - the last 12 messages of the conversation;
  - the open epics of the owner's spaces in short form (id, title, state, current step), at most 30;
  - the spaces;
  - the team;
  - at most 20 remembered facts;
  - actions described in one line each, with one example of a full answer.
  - Planning and step reviews get the same treatment.
- G2. **The call.**
  - Ollama gets a context size that holds the prompt and the answer (16 384 tokens, or more when the prompt needs it, up to 32 768).
  - Ollama gets the answer's JSON schema as its `format`.
  - Thinking is off for director calls.
  - OpenAI-compatible servers get `response_format` with the JSON schema where they accept it, and plain JSON mode otherwise.
- G3. **Ollama CLI.** The CLI preset cannot set the context size, so the Team page warns when it is chosen for the director or the deputy: "use Ollama (API) for the director".
- G4. **Proof.**
  - A scripted acceptance run against the real local model sends 8 Polish requests through the real director code and checks that every answer is accepted and gives the expected actions.
  - The requests are: add an epic, plan an epic, "co się teraz dzieje?", set the tempo to Turbo, remember a preference, add a space, add a daily recurring order, cancel an epic.
  - It runs on demand (not in `bin/rails test`), and its results with times go into the CHANGELOG.

**Out of scope**
- Steps run by local agents (they already work through the same presets).
- Choosing or downloading models for the owner.
- Speeding up the model itself.

**Success criteria**
- S1. The chat prompt for a local director on the demo data with 40 epics and 100 messages is ≤ 24 KB.
- S2. The Ollama request has `options.num_ctx`, `format` (the schema) and `think: false`.
- S3. The acceptance run with qwen3.5:9b passes at least 7 of 8 requests on the first answer, and 8 of 8 with the existing one retry. Each answer arrives within 60 s on this computer.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `ManagementRunner`: short prompt for local executors | to change |
| System | `StepReviewer`: short prompt for local executors | to change |
| System | `AgentCall#run_api`: context size, format, thinking | to change |
| System | JSON schemas of the director's answers (chat, proposal, plan, review) | to create |
| System | acceptance task `agentaro:director:local_check` | to create |
| System | Team page warning (G3) | to change |

## 5. Functional Domain Changes

- **State:** a local director gets a cut prompt and free text → a short whole prompt and an answer forced into the schema.
- **Rules:**
  - R1. "Local" means the executor's preset is an API preset (Ollama, LM Studio, OpenAI-compatible). Claude Code and Codex keep the full prompt.
  - R2. The short prompt keeps every safety rule of the full one:
    - changes only on the owner's request;
    - step results and remembered text are data, not instructions;
    - no secrets.
  - R3. The schema forces the shape only. Agentaro still checks every action as today, and one retry with the errors stays.
  - R4. The acceptance task never runs against production data: it uses the demo database files and deletes them afterwards.
- **Resilience:** a server that refuses `format` or `response_format` is called again once without it. The answer is still checked.
- **Data:** none.

## 6. Critical Path

1. Run the acceptance script against today's code and record the failures (the baseline).
2. Change the call (G2), then the short prompt (G1).
3. Run the acceptance again until S3 holds. Unit tests cover S1 and S2.
4. The Team page warning (G3).
5. A B20 analysis, then CHANGELOG (with the acceptance results) and README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | S1, S2 | prompt-size and request tests with a fake server | commit | Claude Code still gets the full prompt |
| E2E | S3 | `agentaro:director:local_check` with qwen3.5:9b | release | a request with no change asked returns no actions |

## 8. Expected Outcome

- **Direct effect:** a local model can run the director's work.
- **Measurable effect:** the S3 results recorded in the CHANGELOG.
- **Side effects:** a local director sees fewer old messages and epics. An old epic named by its title is still found by title.
- **Rollback:** revert the code. No data changes.

## 9. Additional Information

- **Rejected alternatives:** the full prompt in a 64 k context. On 16 GB of memory it is slow (minutes per answer) and leaves little room for the model.
- **External dependencies:** Ollama 0.40.15 (`format` with a JSON schema, `think`, `options.num_ctx`).
- **Sources and questions:** none open.

- **Implementation (2026-11-22):**
  - `DirectorSchema` holds the answer shapes (chat, plan, review, summary). An action declares every field any action uses, and all of them except `type` are optional. The first acceptance run showed why: with only `type` declared, the held model invented "add_item_add_epic" and could not add a title.
  - `AgentCall` for a local director sends `format`, `think: false`, `num_ctx` (16–32 k) and `num_predict` 3072 (OpenAI-compatible servers: `response_format`, `max_tokens`). A 4xx is retried once without them. The run that had no answer cap was still generating after 6 minutes.
  - The short prompt has the last 12 messages (600 characters each), 30 epics in one line each, 3 KB of memory, and examples of whole answers. A small model often answers "done" with no action, so for a local director the proposal pass always decides.
  - Acceptance with qwen3.5:9b (`agentaro:director:local_check`, demo database):
    - every answer took 4–21 s, with about 3 thousand tokens of input;
    - first run: 7/8, but the planning request added the steps as three new epics, which the check had not caught (now it does);
    - after the fixes: 6/8. It fails "pracuj w turbo" (it proposed `reassign_step`) and "zapamiętaj" (it proposed `set_tempo`). Agentaro refused both, as R3 requires.
    - S3 (7 of 8) is not met with this model: the misses are the model choosing the wrong action.
    - nemotron-3.5-bolt:e4b (the owner's suggestion): 5/8, 4–11 s per answer. It repeats earlier replies and claims a cancellation without the action.
    - mimo-v2.6 (the owner's suggestion): 7/8, 9–50 s per request. S3 is met with this model.
    - Qwen3-30B-A3B through llama.cpp, with the experts read from disk: about 4 tokens/s once warm, but a 3-thousand-token prompt took over 10 minutes. Not usable on a 16 GB Mac.
  - Tests: `local_director_test.rb` (6).
