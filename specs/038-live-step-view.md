# 038 — Live view of a step beside the work panel

Status: **closed** 2026-11-21 (owner: "Zamknij i buduj"; Codex and Ollama added: "Tak, dodaj"); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [016](016-sequential-steps.md), [020](020-pages-without-reloading.md), [027](027-work-panel-beside-chat.md), [030](030-run-traces.md), [036](036-parallel-agent-tasks.md)

## 1. TL;DR

On the Director page, clicking a step or an epic in the work panel opens a third panel to its right. It shows what the agent is doing right now, live: what it writes and each action it takes (reads a file, runs a command, edits a file, searches the web), without their results (R2). For a finished step it shows the same log and the final answer. Tests and a browser check with a running step confirm it.

## 2. Abstract

- **Current state:**
  - The work panel (spec 027) lists each space's epics and their steps with their states, redrawn every 5 seconds. A running step blinks, but its content is not shown.
  - Claude Code streams its work (spec 030, G2): texts, tool calls and their results. These are kept in memory while the step runs and saved to the run's trace only when it ends.
  - Codex is called without its event stream: Agentaro reads only its last message, so its trace has no actions. Ollama and LM Studio stream their text over the API, which only the chat uses (spec 017). Started from the command line, they print the text as they write it.
  - The trace of a finished run is on the run's page (spec 030), several clicks away from the chat.
- **Gap or problem:** while a step runs for 10–30 minutes, the owner cannot see what it does: whether it makes progress, is stuck in a loop, or waits on a test, as with the Docker container in Słodziaki.
- **Rationale:** the owner wants an overview of the work without leaving the chat ("chcę mieć pogląd").
- **Decision history:** the owner chose these options (2026-11-21):
  - the live log, not the text alone or the full trace;
  - a click on a step or an epic, and the view follows the epic to its next step;
  - a log and the answer for finished steps;
  - view only, with no Stop button;
  - Codex's actions and the text of Ollama and LM Studio as well ("Tak, dodaj").

## 3. Objective

**Goals**
- G1. A click on a step in the work panel opens the step view beside it. A click on an epic opens its running step, or else its latest step that has started.
- G2. While the step runs, the view shows its live log and how long it has run. The log covers the agent's texts and its actions (name and a short description, no results: R2), and shows the newest entries at the bottom.
- G3. For a step that ended, the view shows the same log from the trace and the final answer, error or question (spec 033). For a step that has not started, it shows its description, its agent, and what it waits for (an earlier step, an answer, a retry time, another epic of the space under spec 037).
- G4. Opened from an epic, the view follows the epic: when a step ends and the next starts, it moves to the next one.
- G5. The view closes with a Close button or Esc, and leaves the chat and the work panel as they were.
- G6. Codex steps stream their events (`codex exec --json`, checked on codex-cli 0.170.0): commands with their output, file changes, web searches and the agent's messages. They go to the live log and to the trace (spec 030), with tokens. The answer is still read from Codex's last message.
- G7. Ollama and LM Studio steps show their text live as it is written, over the API or from the command line. They have no tools, so there are no actions to show.

**Out of scope**
- Stopping, retrying or answering from the view. Stopping stays where it is today; answers on the epic's page or in the chat.
- Live logs from Gemini CLI and Grok CLI, which are not installed here and were not checked. For them the view shows the running time and "this executor reports when it ends", then the answer.
- Calendar tasks (spec 010) and the director's own runs (chat, planning, verification).
- Reading the log aloud in voice mode.

**Success criteria**
- S1. On the Director page at 1440 px, a click on a running step shows the view to the right of the work panel within 1 second. A new action of the agent (stand-in executor) appears in the view within 3 seconds.
- S2. A click on an epic with a running step shows that step. When it ends and the next one starts, the view shows the next one within 3 seconds, without a click.
- S3. A succeeded step shows its log and its answer; a failed one shows its error; a waiting one shows its question; a pending one shows what it waits for.
- S4. A Claude Code step and a Codex step each show a live log of their actions; an Ollama or LM Studio step shows its text growing. An executor without a stream shows the running time and the note, then the answer. A Codex step's trace lists its commands and its tokens.
- S5. Another account's step, a calendar task's run, or a step of an epic not in the user's work cannot be opened (not found).
- S6. Secrets in the log are replaced as in the trace (spec 030). Agent text and tool results are shown as text only, never as markup.
- S7. On a phone or a narrow window, the view covers the work panel with Close, with no horizontal scroll.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | Live log of a running step (Claude Code and Codex events, Ollama and LM Studio text), readable while it runs | to create |
| System | Codex called with `--json`; its events read like Claude Code's | to change |
| System | Endpoint for one step's view (state, log, answer), the owner's own only | to create |
| System | The third panel on the Director page, opened from the work panel, refreshed while open | to create |
| System | Work panel: steps and epics become clickable | to change |
| System | Tests: endpoint, access, redaction, page; browser check | to create |

## 5. Functional Domain Changes

- **State:** a running step is a blinking line → a clickable line that opens its live log.
- **Rules:**
  - R1. **Own work only.** Only the signed-in user's own epics and their current-plan steps can be viewed (spec 027, R1 and R2). The runs of a shared agent for other accounts are never shown, nor counted in the view.
  - R2. **What a log entry is.** A log entry is one of:
    - the agent's text;
    - a tool call: its name and its main argument (the file path, the command, the search query or the address), on one grey line cut to 80 characters, marked "failed" when the tool failed.

    Owner change (2026-11-21): "nie chcę oglądać środka". Tool results are not shown: no command output and no file contents. They stay in the trace on the run's page.
  - R3. **Entry limits.** Each text entry is cut to 300 characters in the view, with a mark that it was cut. The view shows the latest 200 entries; earlier ones are counted ("120 earlier entries").
  - R4. **Same source as the trace.** The live log and the finished log come from the same events (spec 030). The view never shows more than the trace keeps.
  - R5. **Secrets and markup.** Secrets are replaced before anything is shown, as in the trace. Everything is drawn with `textContent`; tool results from the web keep their source mark ("web").
  - R6. **Refresh.** While the view is open it refreshes every 2 seconds, and only for a step that runs or an epic that is followed. A closed view or a hidden tab asks for nothing.
  - R7. **Panels.** From 1500 px wide the view is a third column to the right of the work panel, and the work panel narrows so the chat keeps its room. Below that it covers the work panel. It works in voice mode too (spec 027, R6). (Changed from the proposed 1200 px after the browser check: at 1440 px three columns left the chat a narrow strip.)
  - R8. **Interface rules.** There is no inline style or script, and the view's script is a first-party file. Reduced motion stops the live mark from blinking.
- **Resilience:**
  - A restart interrupts the step (spec 036, R5). Its log so far stays readable, and the view shows it as interrupted.
  - A failed refresh keeps the last log on screen with a note "not refreshed since HH:MM:SS".
- **Data:**
  - The live log of a running step is a file in the run's own folder. It is removed when the step ends and its trace is saved; from then on the trace (spec 030) is the record.
  - An interrupted step keeps its file, so its log stays readable.
  - No database change.

## 6. Critical Path

1. The owner closes the spec.
2. Make the running step's events readable while it runs (R2–R5), with tests for access and redaction.
3. Add the step view endpoint and the third panel, opened from the work panel (G1–G5, R6–R8).
4. Run the tests and a browser check with a stand-in executor that writes slowly, at 1440 px and on a phone. Then run the B20 analysis and update CHANGELOG and README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | R2–R5 | Log entries from stream events: cut, counted, secrets replaced | Integration | A secret or more than 300 characters shown |
| Integration | S3–S5 | Endpoint tests for each step state, executor and owner | Release | Another account's or a calendar run's log returned |
| Contract | R4 | The finished view equals the trace's events | Release | The view shows what the trace does not keep |
| E2E | S1, S2, S6, S7 | Page test plus a browser check with a slow stand-in executor | Release | No update within 3 s; markup rendered; horizontal scroll on a phone |
| Manual | The owner follows a real step in production | Owner | — | — |

## 8. Expected Outcome

- **Direct effect:** the owner sees what each agent does without leaving the chat.
- **Measurable effect:** an action of the agent shows in the view within 3 seconds.
- **Side effects:** one small request every 2 seconds while the view is open. More of the agents' work is visible, cut and with secrets replaced.
- **Rollback:** remove the click and the panel. The trace and the run page stay as they are.

## 9. Additional Information

- **Rejected alternatives:**
  - A link to the run page: it is far from the chat and shows only finished runs.
  - The full trace with 8 KB results: too much to follow live; it stays on the run page.
  - A Stop button: the owner chose view only.
- **Open:** nothing; the owner's answers are in section 2. The 1500 px and 2-second values are proposals the owner can change.
- **Implementation (2026-11-21):**
  - `LiveLog` writes a running step's events (`live.jsonl`) and text (`live.txt`) to the run's own folder, with secrets replaced. The files are removed once the trace is saved.
  - `CodexStream` reads `codex exec --json` into the trace's event kinds. `ClaudeStream` passes each event on as it arrives. Ollama and LM Studio text reaches the live log over the API (now streamed for steps) and from the command line.
  - `StepView` and `GET /director/live?step=…|epic=…` build the view.
  - `step_view.js` draws it with `textContent`. Steps and epics in the work panel open it; a plain click on an epic title opens the view instead of the epic page, and a modifier click still opens the page.
  - Tests: `test/models/step_view_test.rb` (8) and `test/integration/step_view_test.rb` (3). Two older tests now expect `--json` for Codex and the hidden view in the Director layout (intended changes).
- **Browser check (2026-11-21, demo data, deleted afterwards):**
  - At 1440 px the view covers the work panel and the chat keeps its width. At 1680 px it is the third column.
  - New entries showed within 2 seconds. Agent text containing `<b>` showed as text.
  - Esc closed the view. An epic followed moved to the next step within 3.5 seconds.
  - On a phone the view covered the page without horizontal scroll, and a finished step showed its log from the trace and its answer.
- **Security analysis (B20, after specs 001–038):**
  - Brakeman 0 warnings, bundle-audit no vulnerabilities.
  - Access: own epics and current-plan steps only (tested, 404 otherwise).
  - Secrets replaced on write and again on display. Everything is drawn as text.
  - Finding, fixed: the live log's files followed links. A link planted in the run's folder could have sent Agentaro's appends to another file, or shown another file in the view. Agents cannot write there today: their writes are limited to `work/` or the space's folder, and `var/runs` is denied. Now writes use `O_NOFOLLOW` and fresh temporary files, and reads skip anything that is not a regular file (test "B20: a link planted…").
  - Accepted:
    - an interrupted step's live log stays in its run folder like the rest of that folder;
    - one small request every 2 seconds while the view is open, reading at most 1000 entries.
