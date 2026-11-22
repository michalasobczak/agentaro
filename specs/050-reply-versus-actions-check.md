# 050 — Does the reply match what was done?

Status: **draft**
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
