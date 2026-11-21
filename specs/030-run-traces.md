# 030 — Run traces: keep every prompt and answer in a form fit for learning

Status: **closed** 2026-11-21 (the owner's go-ahead with the proposed answers to Q1–Q3); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [004](004-data-changelog.md), [010](010-task-execution.md), [016](016-sequential-steps.md), [017](017-voice-and-streaming.md)

## 1. TL;DR

Every model call is kept as a structured trace. The trace holds:
- the prompt's parts, with repeated parts stored once;
- the answer;
- the tool events of the run;
- tokens, cost and time;
- links to the epic, step, chat message and memory versions it used.

Nothing is ever pruned automatically, except what the user deletes. This comes first, because data not recorded today cannot be used by the brain and learning later (specs 031 and 100–104). Tests and a week of real use confirm complete traces.

## 2. Abstract

- **Current state:** `task_runs` keeps each call's full prompt as one joined text (14 KB on average) and the answer up to 200 KB, with no pruning. In numbers:
  - 299 calls on the owner's instance since 2026-11-19;
  - about 4.2 MB of prompts and 0.5 MB of answers.
  - Claude Code's stream-json events (tool use, usage, cost) are read only for chat streaming and then dropped.
  - Steps run with plain text output.
  - Calls of the local model, planned in spec 031, would not be recorded at all.
- **Gap or problem:**
  - Learning needs to know what the model saw and did, not only the joined text and the final answer:
    - which master prompt, playbook and memory facts;
    - which tools it used;
    - what it cost;
    - which result the owner later rated.
  - Repeating the whole context in every row also wastes space.
- **Rationale:**
  - The owner asked: "czy powinniśmy przechowywać wszystkie prompty i odpowiedzi?" Yes, and in a structured form.
  - Every day without it is lost training data.
- **Decision history:**
  - The owner chose to give this its own spec and number the brain and learning specs after it (2026-11-21).
  - Data stays on this Mac (spec 031).

## 3. Objective

**Goals**
- G1. **Prompt parts.**
  - Each call stores the ordered list of its prompt parts: master prompt, playbook, memory section, space and team context, conversation, task or user message.
  - Each part has a kind and a content hash, and each distinct content is stored once.
  - The joined prompt can be rebuilt exactly.
- G2. **Answer and events.**
  - The answer is stored as today, up to 200 KB.
  - For Claude Code, steps also run with stream-json, and the event list is kept (tool calls with their names, arguments and results, truncated). Codex and API presets keep what they return.
- G3. **Numbers.** Per call:
  - input and output tokens;
  - cost when the tool reports it;
  - duration;
  - model, effort, executor and preset;
  - exit state.
- G4. **Links.**
  - Each trace points to its run, user, space, epic, step, chat message and agent.
  - Once specs 031, 100 and 101 exist, it also points to the versions of the memory blocks and playbooks it used, so a later reward reaches the right call.
- G5. **Local model calls.** Calls the brain makes to the local model (extraction, sentiment, judge) are traces too, with their job name and validated result. The user's corrections of their results can then become training data (spec 104).
- G6. **Keep, compress, forget.**
  - Traces are kept without a time limit.
  - Event lists older than 90 days are compressed.
  - Traces linked to a rating are never compressed.
  - When the user deletes a chat message, a fact or a space (spec 025), the related trace content is deleted too.
- G7. **A trace view.**
  - From an epic step and from the run page, the user can open the trace: parts with their kinds, the events and the numbers.
  - The view is admin-styled and `desktop-only`.

**Out of scope**
- Using traces for memory, rewards or training: specs 031 and 100–104.
- Exporting traces outside the Mac.
- Changing what the models are told. Only recording changes.

**Success criteria**
- S1. After a week of use, every director, step, verifier and chat call has a trace with parts, numbers and links. Claude Code step traces include tool events.
- S2. The joined prompt rebuilt from parts equals the prompt actually sent, for every call in the tests.
- S3. Storage per call falls compared with today's joined prompts, because repeated parts are stored once.
- S4. Deleting a space removes its traces' content.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `trace_parts` (digest, content, bytes): each distinct text once (migration `20261121130000`) | to create |
| Data | `model_calls`: one row per call of a run, with pass, agent, preset, model, effort, state, duration, tokens (in, out, cache read and write), cost, turns, joiner, answer (a part), error, redacted flag, events (JSON or deflated) | to create |
| Data | `model_call_parts` (call, position, section, kind, part) | to create |
| System | `AgentCall::Prompt` built from named sections; `with` changes sections only | to change |
| System | `RunTrace` (record, redact, rebuild, backfill, compress), `TracePart`, `ModelCall`, `ModelCallPart` | to create |
| System | `HostProcess`: every output chunk reaches the stream reader | to change |
| System | data changelog: trace tables skipped (`changelog_skipped`) | to change |
| System | `agentaro:traces:backfill` for runs from before traces | to create |
| System | `AgentCall`: stream-json for Claude Code steps; usage, cost and events kept | to change |
| System | `ClaudeStream`: collect tool events and the result line's usage and cost | to change |
| System | `Space#purge!`, chat deletion: remove trace content | to change |
| System | trace view on the run page | to create |
| System | nightly compression of old events | to create |

## 5. Functional Domain Changes

- **State:** joined prompt and final answer → structured, linked, complete traces.
- **Rules:**
  - R1. **Exactly what was sent.** Parts are recorded from the same objects that build the prompt, never reconstructed afterwards. A test checks equality (S2).
  - R2. **No secrets.**
    - Before storing, parts and events pass the secret filter: things that look like keys, tokens, passwords or private keys are replaced with a marker.
    - Environment values and credentials are never recorded.
  - R3. **Outside content is marked.** Tool results that come from the web or from files carry their kind, so later specs never use them as targets or as facts about the user (specs 031 R1, 104 R1).
  - R4. **The user's data only.** Traces are per user. The trace view gives 404 for other users' runs.
  - R5. **Deletion is real.** Deleting removes the content, not just the link. Shared parts are deleted when no trace uses them.
  - R6. **Never committed.** Traces live in the SQLite database in `storage/`, which is not tracked.
  - R7. **Recording never breaks a run.** If storing a trace fails, the run goes on and the failure is logged.
- **Resilience:** a tool that does not report tokens or cost leaves those fields empty.
- **Data:**
  - Three new tables and new columns on `task_runs`.
  - Existing runs keep their joined prompt and get a trace with a single "legacy" part.
  - Rollback drops the new tables and columns. The joined prompt stays as today until a later spec removes it.

## 6. Critical Path

1. Named prompt parts in `AgentPrompt`.
2. Parts tables and the equality test.
3. Numbers and links on `task_runs`.
4. stream-json for Claude Code steps; events.
5. Secret filter; deletion; compression.
6. Trace view.
7. Backup and migration of the owner's data (legacy parts).
8. Tests, a week of use (S1), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | parts rebuild the exact prompt; duplicate parts stored once; secret filter; event truncation | `test/models/run_trace_test.rb` | merge | a fake key in a prompt never reaches the database |
| Integration | director, step, verifier and chat calls each leave a complete trace; space deletion removes content; trace view only for the owner | `test/integration/run_traces_test.rb` | merge | 404 for others; no inline style or script |
| Contract | Claude Code stream-json: tool events, usage and cost parsed from recorded samples | fixture streams | merge | an unknown event never breaks the run |
| Manual | S1 after a week; size per call compared with today (S3) | owner + query | release | — |

## 8. Expected Outcome

- **Direct effect:** a complete, private record of every model call, ready for memory, rewards and training.
- **Measurable effect:**
  - share of calls with a complete trace (target 100%);
  - bytes per call compared with today.
- **Side effects:**
  - Steps switch to stream-json, which gives the same final answer and more events.
  - The database grows with the number of events, which stays small: about 1 GB a year at heavy use.
- **Rollback:** stop recording; drop the new tables. Runs work as before.

## 9. Additional Information

- **Rejected alternatives:**
  - Joined prompts only, as today: not enough for learning, and wasteful.
  - Files per run in `var/runs`: harder to link, query and delete.
  - An external tracing service (Langfuse, LangSmith): the data would leave the Mac or need another server.
- **Technical debt:** the joined `prompt` column stays for now, duplicating the parts. Remove it after a release.
- **External dependencies:** none new.
- **Sources and questions:**
  - Q1. Tool calls, tool results and texts inside events: up to 8 KB each. (Owner, 2026-11-21: as proposed.)
  - Q2. Compress events after 90 days. (Owner: as proposed.)
  - Q3. The trace view is desktop only. (Owner: as proposed.)

## Implementation notes (2026-11-21)

- **One trace per call, not per run.** A chat run makes two calls (the reply and the proposal pass), so tokens, cost and parts live on `model_calls`, linked to the run. G3's columns on `task_runs` became these columns.
- **Parts.**
  - Section 0 is the master prompt; then come the prompt's named sections:
    - director and verifier: `context`, `instructions`, and `rejection` on a retry;
    - steps: `task`, `epic`, `workspace`, `earlier_answers`, `instructions`;
    - calendar tasks: `task`, `epic`, `instructions`.
  - Each section is stored in blank-line chunks, so a repeated block (rules, team, spaces) is one row for every call.
  - `ModelCall#prompt_text` rebuilds the text sent; tests check it equals the prompt for every builder.
- **A bug found on the way.** A retry after a rejected answer appended its note with `prompt.with(user: …)`. With named sections this would have dropped the note. The retry now adds a `rejection` section, and changing `user` alone raises an error.
- **Claude Code.**
  - All calls run with `--output-format stream-json --verbose`; partial messages are added only when the chat streams.
  - The final answer is the result line, as before.
  - `HostProcess` now passes every chunk to the reader, also beyond the output limit, so large tool results cannot hide the result line (test).
- **Sources of tool results:** `web` (WebFetch, WebSearch), `file` (Read, Grep, Glob, LS), `command` (Bash), `agent` (Edit, Write, Task, Agent), `other`.
- **Local APIs:** Ollama's `prompt_eval_count`/`eval_count` and OpenAI-compatible `usage` give the tokens.
- **Data changelog.** Trace rows are not written to it (`changelog_skipped`): they are derived from runs, which are recorded, and would only repeat their text.
- **Deletion and maintenance.**
  - Deleting a space removes its runs' traces and the text no other call uses.
  - Chat messages cannot be deleted today (only archived), so there is nothing to remove there yet.
  - Once a day the scheduler compresses events older than 90 days and deletes unused parts.
- **Checks.**
  - Tests: `test/models/run_trace_test.rb` (14) and `test/integration/run_traces_test.rb` (3); full suite 370 runs, 0 failures.
  - A real Claude Code step on demo data (haiku, "fetch example.com") gave the right answer, 7 events, tokens and a cost of $0.008, and a prompt rebuilt equal to the one sent.
  - The run page at 719 px had no horizontal scroll.
- **Found by the first real trace.** Claude Code answered WebFetch with "No such tool available… use the Agent tool with subagent_type web-fetch", and the step finished through a sub-agent. The step worked, but web tools may not be directly available in print mode. This is worth its own check outside this spec.

## Security analysis (B20), after spec 030

- **New data at rest.**
  - Traces hold prompts, answers and tool results, which can include file contents and web pages.
  - They stay in the SQLite database in `storage/`, which is never committed and is unreadable to agents (spec 010 R4, spec 018).
- **Secrets (R2).**
  - Before storing, every part, answer, error and event string passes a filter. It covers private keys, Anthropic/OpenAI/GitHub/GitLab/Slack/AWS/Google keys, bearer and basic tokens, JWTs, and `password:`/`api_key=`-style values.
  - Tests check that none reaches the database. The filter is high precision, so some unusual secrets may still pass.
  - The run's joined `prompt` column (from spec 010) is still stored unfiltered; this is recorded as technical debt.
- **Access (R4).**
  - The trace view uses the run page's rule (`TaskRun.visible_to`): another user's run is 404 (test).
  - Runs of system-wide calendar tasks were already visible with their full prompt to whoever sees the task; traces show nothing beyond that.
- **Rendering.**
  - Everything is printed through ERB escaping (a test shows `<script>` in an event is escaped).
  - There is no new script and no inline style.
  - Event JSON is parsed on the server only.
- **Outside content (R3).** Tool results carry their source, so specs 031 and 100–104 can exclude web and file content from facts and training targets.
- **Availability (R7).**
  - Recording errors are logged and never fail a run (test).
  - Claude Code's stdout is now read to the end; the buffer stays bounded by the existing limit, and the line buffer is dropped above 4 MB.
- **Earlier specs.**
  - Spec 004: trace rows bypass the data changelog by design, but writes go through callbacks (the no-bulk-writes test passes).
  - Spec 025: space deletion now also removes traces.
  - No regressions found.
- **Tools.** Brakeman: 0 warnings. No new gems.

