# 050 — Does the reply match what was done?

Status: **closed** 2026-11-25 (owner: "Zamknij 050 i buduj"); **implemented** 2026-11-25
Date: 2026-11-22
Depends on: [011](011-list-and-management.md), [019](019-verifier.md), [040](040-director-controls-failed-and-hung-steps.md), [047](047-retry-by-agreement-and-kept-replies.md)

## 1. TL;DR

When the director's reply says it does something ("zatrzymuję", "anulowałem", "dodałem"…) and Agentaro did not do it, a check by the verifier finds the gap. It makes the missing action once, with the same checks as always, and says in the chat what was done or why not. Tests replay real cases from production.

## 2. Abstract

- **Current state:**
  - The director's reply is written in one pass and the changes are decided in another (spec 011).
  - Agentaro notes under the reply what it really applied.
  - Nothing compares the two.
- **Gap or problem:** in the last 3 days, 9 replies ended with "No changes were made", and at least 6 of them say something was done:
  - "Zatrzymuję oba jej procesy" (twice, the waiting loop of the cars step);
  - "Anuluję to zadanie";
  - "anulowałem i dopisałem od nowa";
  - "Usunięte, nie zapamiętam tego".
  - The owner then waits for something that never happens.
  - The causes found so far (fixed on 2026-11-22): the proposal pass did not see processes or steps; the owner's "tak" or "zajmij się tym" did not count as a request. More causes will come, so the gap needs a check, not only fixes.
  - 2026-11-25 (run 1564): the reply pass wrote "Zlecam więc małą poprawkę" with an `add_item`; the proposal pass took "no to chyba przepisy też wypadałoby kategoryzować" for a suggestion and added nothing. The reply stayed, with "No changes were made" under it.
  - Fixed on 2026-11-24: a director message from another run (a plan or an epic summary) posted while a reply was prepared counted as a changed request, so every change was refused ("Not done: all changes: your request changed…"). Five production replies, all of this kind; now only a newer message of the owner counts.
- **Decision history:** the owner chose (2026-11-22):
  - the verifier checks; with no verifier, the director's own model;
  - only replies that announce an action, or where actions were refused;
  - on a mismatch, Agentaro makes the missing action once and says so.

## 3. Objective

**Goals**
- G1. **When.** After a chat reply is posted, a check is queued when either holds:
  - (a) the reply announces an action in the first person (a fixed list of Polish and English verbs, such as zatrzymuję/zatrzymałem, anuluję/anulowałem, dodaję/dodałem, przesuwam, ponawiam, zapamiętam, usuwam, wstrzymuję, wznawiam, przekazuję, zlecam, stop, cancel, add, move), and Agentaro applied nothing, or less than the reply names;
  - (b) some actions were refused ("Not done: …", spec 047).
- G2. **Who.**
  - The verifier (team role, spec 019) checks. Without one, the director's agent checks.
  - The check runs after the reply, so the reply is never delayed.
- G3. **What it sees:**
  - the owner's latest messages;
  - the director's reply;
  - what Agentaro applied and what it refused, with the reasons;
  - the work list as the proposal pass sees it (steps, processes, questions);
  - the action list.
- G4. **What it answers** (JSON):
  - `consistent` (true or false);
  - the `missing` actions, at most 3: only those the reply announced and the owner asked for;
  - a `note` of one or two sentences in the owner's language.
- G5. **Repair, once.**
  - Each missing action goes through `check_action`, with the owner's-words rules (and agreement, spec 047) and the latest message. Nothing passes that the proposal pass would refuse.
  - The valid ones are made.
  - Then one chat message is posted from the checker (shown and spoken as the verifier, spec 019): what was done, or why not. Example: "Wcześniej napisałem, że zatrzymuję pętlę, ale nic nie zostało zatrzymane — teraz zatrzymane: sleep 20."
  - A consistent reply posts nothing.
- G6. **Limits:**
  - one check per reply, never a check of a check;
  - no check when the owner has written again meanwhile (the reply is stale);
  - no check of summaries (spec 045) or of plans.

**Out of scope**
- Checking replies that announce nothing.
- Changing the director's reply after it is posted. The correction is a new message.

**Success criteria**
- S1. Replays of the production replies 973/975 ("Zatrzymuję oba jej procesy", nothing stopped):
  - the check finds the gap;
  - the process is stopped;
  - one correction message is posted.
- S2. A reply that announces an action that was applied gets no check, and no call is made.
- S3. A missing action the owner never asked for is not made, even if the checker lists it. The note says why.
- S4. With the owner's newer message present, the check is skipped.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | the announcement rule (verbs) and the gap rule | to create |
| System | run purpose `consistency` and its runner | to create |
| System | repair through `check_action`; the correction message | to create |
| System | JSON schema of the check (spec 044, for a local checker) | to create |

## 5. Functional Domain Changes

- **State:** a reply can promise what was not done → a promise without its action is found, repaired once, and told.
- **Rules:**
  - R1. The checker cannot widen anything: a repaired action passes exactly the checks of the proposal pass, against the same owner message.
  - R2. The reply, the work list and step outputs reach the checker as data, not instructions (as in spec 021 and spec 040).
  - R3. Usage limits (spec 043): a checker at its limit is skipped, not waited for.
- **Resilience:** a failed or refused check leaves the chat as it was.
- **Data:** none beyond the run and the message.

## 6. Critical Path

1. Tests replaying replies 973/975 and a consistent reply (S1, S2).
2. The trigger rule.
3. The check run with its schema.
4. The repair through `check_action` and the message.
5. S3, S4, B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | the trigger rule on announcing and non-announcing replies | model tests | commit | "Zrobione." alone with an applied change triggers nothing |
| Integration | S1–S4 with a fake checker | runner tests | commit | a missing action without the owner's words is not made |
| Manual | a real mismatch on production is corrected | the owner | — | — |

## 8. Expected Outcome

- **Direct effect:** the owner is not left waiting for a promise nobody kept.
- **Measurable effect:** "announces an action, no changes" replies left uncorrected drop to zero.
- **Side effects:** one more model call for such replies only; a correction message now and then.
- **Rollback:** revert the code.

## 9. Additional Information

- **Rejected alternatives:**
  - checking every reply: it doubles the calls;
  - forbidding the director to announce actions: it would still slip, and the owner wants natural replies (spec 046).
- **Sources and questions:** none open.
- **Implementation (2026-11-25):**
  - Migration `20261125110000`: `task_runs.checked_message_id`; run purpose `consistency`.
  - `ManagementRunner.announces?`: a fixed list of Polish first-person verbs and participles (zatrzymuję, anulowałem, zlecam, zapamiętam, usunięte…), matched as whole words, and English "I'll / I've / I … stop, cancel, add, …" forms.
  - The trigger in `apply_chat!` (chat runs only, with a request of the owner): some changes refused, or nothing applied while the reply announces an action. "Less than the reply names" cannot be counted without a model: a reply with at least one applied change is not checked (S2).
  - `consistency!`:
    - It runs the verifier, or the director's agent without one, and is skipped at a usage limit (R3) or when the owner has written again, before and after the call (S4).
    - Its prompt is the proposal pass's prompt (work list with steps, processes and questions; the owner's latest message), plus the reply and what Agentaro did, quoted as data (R2), and the check's own answer format (`DirectorSchema::CONSISTENCY`).
    - At most 3 missing actions go through `check_action` in one transaction. `retry_step` is refused (a retry is decided with the reply). One message from the checker ("verifier", or "director" without one) carries the note and what was applied or refused. A consistent answer posts nothing.
  - Tests: `reply_consistency_test.rb` (9). They replay 973/975 (the process is stopped), run 1564 (the epic is added) and the announcement rule, and cover S2, S3, S4, a consistent answer, the director without a verifier and the refused retry.
  - Real runs on this computer (demo data, deleted afterwards; Claude Code as the verifier):
    - "Zlecam więc małą poprawkę…" after "no to chyba przepisy też wypadałoby kategoryzować": the epic was added. The verifier wrote that it had been promised and was ordered now.
    - "…zapamiętam, żeby potem sprawdzić przepisy" after "a co robi teraz inżynier?": nothing was made. The note said it was not asked for and the owner can ask.
- **Security analysis (B20, after specs 001–054 and this one):**
  - R1 holds: every repaired action passes `check_action` with the owner's message that the reply answered, including the owner's-words rules (stop a process, CI, settings). The check cannot retry a step, and it cannot make more than 3 actions.
  - The checked message is found only among the owner's own messages. The run carries only its id.
  - Prompt injection: the reply and what was done are quoted as data. Step outputs reach the checker only through the work list, as they reach the proposal pass.
  - Cost: at most one check per chat reply, and only for replies with a gap. A check never triggers another check.
  - Race: the owner's newer message is looked for before and after the call. The window between the last look and the commit is the same as the proposal pass has.
  - Brakeman 0 warnings; bundle-audit clean.

