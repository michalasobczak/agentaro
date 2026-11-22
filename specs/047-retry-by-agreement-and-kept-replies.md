# 047 — Retry by agreement, and replies kept when an action is refused

Status: **closed** 2026-11-22 (owner's answers: "Zgoda na jego propozycję", "Pokaż odpowiedź"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [011](011-list-and-management.md), [021](021-director-sees-step-output.md)

## 1. TL;DR

Two changes to the director chat:
- The director may run a failed step again when the owner agrees to its offer, or names the epic or its space with words that start it.
- When an action is refused twice, the director's reply is still shown and spoken. The valid actions are made, and the refused ones are noted under the reply.

## 2. Abstract

- **Current state (spec 021):**
  - `retry_step` needs the owner's latest message to be exactly a retry request, such as "ponów krok 2 w World review".
  - When an answer is refused twice, the whole reply is lost and the chat says "No answer from the director: …".
- **Gap or problem:** on production, 2026-11-22 15:29–15:31:
  - The director asked: "Chcesz, żebym jeszcze raz puścił wodę w Słodziakach, a Auta i Psi Patrol zostawił na później?"
  - The owner answered by voice: "Tak, najpierw robimy featurey z gry słodziaki…".
  - The owner got "No answer from the director: … retry_step: admin has not asked in their message to retry step 1 …" twice.
- **Decision history:** the owner chose both proposals (2026-11-22).

## 3. Objective

**Goals**
- G1. `retry_step` is accepted for an epic when any of these holds:
  - (a) the strict request of spec 021;
  - (b) the owner's latest words start with agreement ("tak", "dobra", "jasne", "zgoda", "dawaj"…) and the director's previous message offered to run this epic again, naming its title or its space;
  - (c) the owner's latest words name the epic or its space, with a word that starts it ("najpierw", "zacznijmy", "puść", "ponów", "jeszcze raz"…).
  - Never when the words say not to ("nie puszczaj…").
  - Names also match inflected ("Słodziakach" for "Słodziaki").
- G2. **Refused twice.**
  - The reply stays and is spoken.
  - Each action is checked on its own: the valid ones are made, and the refused ones are noted under the reply as "Not done: … (reason)".
  - A retry still goes alone in a reply. Other changes are decided only by the proposal pass, which needs the owner's request.

**Out of scope**
- Moving several epics with one sentence in the same reply as a retry. The other changes are noted as "say them again".

**Success criteria**
- S1. The production conversation, replayed: "Tak, najpierw robimy featurey z gry słodziaki…" after the offer runs the water epic again. The cars epic stays blocked.
- S2. A reply with a refused action stays in the chat, with "Not done: …", and there is no "No answer from the director".

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `ManagementRunner#requested_retry?`, `agreed_retry?`, `names_epic?` | to change / to create |
| System | `ManagementRunner#apply_chat!` (lenient second attempt) | to change |

## 5. Functional Domain Changes

- **Rules:**
  - R1. The step must still be eligible (spec 021, R5): a failed step of a blocked epic, its latest attempt, the earlier steps done.
  - R2. Only the owner's own messages count, never the verifier's or Agentaro's (spec 021).
  - R3. B20: in the lenient path the reply pass may carry only a retry. Every other change is refused there, because only the proposal pass, with the owner's request, decides changes.
- **Data:** none.

## 6. Critical Path

1. Reproduce the conversation in a test.
2. Fix it.
3. Adapt the tests of the old behaviour.
4. B20, CHANGELOG, README, restart.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | S1, S2, G1 (b) and (c) | `retry_by_agreement_test.rb` | commit | a negation, or an epic neither offered nor named, is refused; no change slips through without the owner's request |

## 8. Expected Outcome

- **Direct effect:** a natural "tak" runs the offered epic. A refused action never costs the owner the reply.
- **Side effects:** a reply can now carry a partly done set of changes; the note says which were not made.
- **Rollback:** revert the code.

## 9. Additional Information

- **Implementation (2026-11-22):**
  - New: `retry_by_agreement_test.rb` (6). Without the fix, 4 of its tests fail.
  - Adapted to G2:
    - two spec 021 tests in `director_chat_test.rb` (the reason is now under the reply);
    - "one bad action applies none" in `management_runner_test.rb` (now the valid one is made);
    - the spec 043 refusal test.
- **Security analysis (B20, after specs 001–047):**
  - The first version of the lenient path would have made work-list changes from the reply pass without the owner's request. Fixed (R3) with a test that fails without the fix.
  - Accepted: a "tak" right after the director's offer runs that epic. The offer is the director's own words, which the owner has just read or heard.
