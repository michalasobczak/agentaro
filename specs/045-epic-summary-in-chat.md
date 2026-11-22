# 045 — A short human summary when an epic ends

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [016](016-sequential-steps.md), [041](041-chat-settings-panel-style-and-tempo.md), [043](043-usage-limits-and-deputy-director.md)

## 1. TL;DR

When an epic ends with every step done, the director writes the owner a short summary in the chat. The summary has 2–4 sentences in plain words and the owner's chosen style: what was done, what came out, and what needs the owner's attention. The technical results stay on the epic's page.

## 2. Abstract

- **Current state:** at the end of an epic the chat gets one system line: "Done: "X" — all 3 steps finished. The results are on the epic's page." The agents' results are technical and long.
- **Gap or problem:** the owner's words: "po zakończeniu epiku ma powstawać automatyczne podsumowanie normalnym głosem bez rozwlekłego pieprzenia … surowym technicznym tekstem to może być, ale musi być też ludzkie krótkie podsumowanie".
- **Decision history:** the owner chose the chat as the only place for the summary (2026-11-22).

## 3. Objective

**Goals**
- G1. When an epic becomes done, Agentaro asks the director (or the deputy, spec 043) for a summary. The summary goes into the chat as the director's message, in the owner's language, style (spec 041) and conversation mode (spec 046).
- G2. **The summary.**
  - 2–4 sentences, at most 600 characters.
  - It says what was done and what came out, in the owner's words, not the agents'. It names where the result is when that matters (a file, a page).
  - It mentions what needs the owner: assumptions made, anything left undone.
  - No lists, no logs, no step numbers.
- G3. The system line "Done: …" stays as it is, above the summary.
- G4. In a voice conversation the summary is read aloud like any message of the director.

**Out of scope**
- Summaries of blocked or cancelled epics.
- Quiet runs of recurring orders (`report: attention`, spec 034); they stay quiet.
- A summary on the epic's page.

**Success criteria**
- S1. An epic whose last step succeeds gets the "Done" line and then the director's summary of at most 600 characters.
- S2. The summary call gets the epic title, the plan summary, each step's title and result (cut), and the assumptions. All of it is marked as data, not instructions.
- S3. If the director cannot answer (a limit with no deputy, an error), the epic stays done, the "Done" line stays, and no error is posted.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `StepChain.finish!`: queue the summary | to change |
| System | summary run (purpose `summary`) in `ManagementRunner` | to create |
| System | chat: the summary as a director message | exists |

## 5. Functional Domain Changes

- **State:** a technical "Done" line → that line plus a short human summary.
- **Rules:**
  - R1. One summary per finished epic. An epic done again later (steps added and done) gets a new one.
  - R2. The input is limited:
    - each step's result is cut to 1 500 characters;
    - the whole input is cut to 8 000 characters, and the last steps are kept.
  - R3. The answer is the JSON `{"summary": "..."}`. Any action in it is ignored.
  - R4. The summary run does not count as the owner's message and changes nothing on the work list.
- **Resilience:** a failed or skipped summary run leaves only a record in the run list.
- **Data:** none beyond the run and the chat message.

## 6. Critical Path

1. A test: an epic finishes, so a summary run is queued; the fake director answers, so the chat holds the "Done" line and the summary.
2. The summary prompt and the run.
3. The failure cases (S3).
4. A B20 analysis, then CHANGELOG and README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | S1, S2, S3 | runner tests with a fake executor | commit | a quiet recurring run gets no summary; actions in the answer change nothing |
| Manual | a real epic on production ends with a readable summary | the owner | — | — |

## 8. Expected Outcome

- **Direct effect:** the owner hears or reads in a few words what an epic achieved.
- **Side effects:** one more director call per finished epic.
- **Rollback:** revert the code.

## 9. Additional Information

- **Rejected alternatives:** a summary built from fixed templates without a model, because it would not say what came out.
- **Sources and questions:** none open.

- **Implementation (2026-11-22):** `StepChain.finish!` queues a run with purpose `summary` after the Done line, once the transaction commits. `ManagementRunner#summary!` asks the director (or the deputy) with the epic, its plan, the steps' results (1 500 characters each, 8 000 in all, the last steps kept, quoted, secrets replaced) and the assumptions. Only `summary` is read from the answer, cut to 600 characters. In voice mode a summary that arrives while the voice listens is read aloud. Tests: `epic_summary_test.rb` (4) and a JS scenario; `recurring_order_test.rb` adapted (the summary prompt now comes after the step's).
