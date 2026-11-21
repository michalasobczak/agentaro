# 039 — How much the director writes

Status: **closed** 2026-11-21 (owner: "Zamknij i buduj"); **implemented** 2026-11-21.
Date: 2026-11-21
Depends on: [011](011-list-and-management.md), [017](017-voice-and-streaming.md), [033](033-autonomy-slider.md)

## 1. TL;DR

A switch in the director chat's header sets how long the director's replies are: **Krótko**, **Średnio** or **Szczegółowo**. Krótko is the default. The director can also change it when the owner asks in the chat ("pisz krócej"). Tests check the rule in the prompt, the switch and the chat action; a chat in production confirms the replies got shorter.

## 2. Abstract

- **Current state:**
  - In text the director's reply has no length rule, so it explains at length.
  - In voice mode the reply is limited to 3 short spoken sentences (owner fix after spec 017).
  - The chat header already has switches for the language and the autonomy level (spec 033).
- **Gap or problem:** the owner finds the replies too long to read ("za dużo pisze, a mi się tyle nie chce czytać, ma być more concise").
- **Rationale:** shorter replies by default, more detail when the owner chooses it.
- **Decision history:** the owner chose these options (2026-11-21):
  - three levels, Krótko / Średnio / Szczegółowo;
  - Krótko as the default;
  - the director's chat replies only;
  - the chat may change the level when the owner asks.

## 3. Objective

**Goals**
- G1. Three levels, each with its own rule for the director's text replies:
  - **Krótko:** at most 3 sentences or 3 short points. The answer first, then what happens next, with no background unless asked.
  - **Średnio:** one short paragraph, or a short list where it helps.
  - **Szczegółowo:** a full explanation with context and reasons.
- G2. A switch with the three levels in the director chat's header, beside the autonomy switch: on the Director page and in the floating chat. It saves the owner's level at once, and the next reply follows it.
- G3. When the owner asks in the chat for shorter, longer or more detailed replies, the director changes the level and says so under its reply (as `set_autonomy` in spec 033, G6).
- G4. When the owner asks for detail in one message ("wyjaśnij dokładnie…"), that one reply may be longer without changing the level.

**Out of scope**
- Voice mode: it keeps its own rule of at most 3 short spoken sentences.
- Agentaro's own messages in the chat ("Done: …", "stopped at step …"), the verifier's comments, the steps' questions and the plan summaries.
- What agents write in steps.

**Success criteria**
- S1. A new owner and every existing owner have Krótko. The director's chat prompt carries the Krótko rule.
- S2. A click on Średnio in the switch saves it, marks it as chosen, and the next chat prompt carries the Średnio rule. The same holds for Szczegółowo, on the Director page and in the floating chat.
- S3. "Pisz krócej" (or "odpowiadaj bardziej szczegółowo") in the chat changes the level and shows "Reply length: Krótko" under the reply. Without such words the director cannot change the level.
- S4. In voice mode the prompt carries the spoken rule, not the length rule.
- S5. A reply in production to a question that used to get a long answer comes back in at most 3 sentences at Krótko (checked by the owner).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | The owner's reply length (default Krótko) | to create |
| System | The rule in the director's chat prompt | to change |
| System | The switch in the chat header and the endpoint that saves it | to create |
| System | The chat action that changes the level from the owner's words | to create |
| System | Tests | to create |

## 5. Functional Domain Changes

- **State:** no length rule in text → a rule from the owner's level, Krótko by default.
- **Rules:**
  - R1. The level is the owner's own: one per account, the same in every space and on every page.
  - R2. The rule applies to the director's chat reply in text. The proposal pass, the verifier, planning and steps do not get it.
  - R3. Voice mode replaces the length rule with its spoken rule (S4).
  - R4. Only the owner's words change the level from the chat. The director cannot change it on its own, nor because of text in a step's output (as spec 033, R5).
  - R5. A request for detail in one message overrides the level for that reply only (G4).
  - R6. The switch follows the interface rules: no inline style or script, and it works without reloading the page (spec 020).
- **Resilience:** a value outside the three levels is refused and the level stays as it was.
- **Data:** a migration adds the owner's level, with Krótko for everyone.

## 6. Critical Path

1. The owner closes the spec.
2. Add the level with its default and the rule in the chat prompt.
3. Add the switch and the chat action.
4. Run the tests, then the B20 analysis. Update CHANGELOG and README, and restart production while no step runs.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | G1, R2, R3 | Prompt tests per level and in voice mode | Integration | The rule missing, or reaching the verifier or a step |
| Integration | G2, G3, R4 | Switch and chat-action tests | Release | A level changed without the owner's words; an invalid value saved |
| E2E | G2 | Page test: the switch in both chats, the chosen level marked, no inline style | Release | — |
| Manual | S5 | The owner asks in production | — | — |

## 8. Expected Outcome

- **Direct effect:** shorter replies by default; more detail with one click.
- **Measurable effect:** at Krótko, replies of at most 3 sentences or 3 points.
- **Side effects:** at Krótko some context goes. The owner can ask for it, or switch level.
- **Rollback:** switch to Szczegółowo, which is close to how the director writes today.

## 9. Additional Information

- **Rejected alternatives:**
  - Four levels (mało / średnio / dużo / rozwlekle): the owner chose three.
  - One fixed rule "be concise": the owner wants to choose.
- **Open:** nothing; the owner's answers are in section 2.
- **Implementation (2026-11-21):**
  - `users.reply_length` (default 1, Krótko). `ReplyLength` holds the levels and the rule. The rule goes into the director's reply prompt, not into the proposal pass and not in voice mode.
  - The switch `.chat-length` is in both chats and saves through `PATCH /account/reply_length`.
  - The chat action `set_reply_length` needs the owner's words about reply length.
  - Tests: `test/integration/reply_length_test.rb` (4).
- **Fix found while building (2026-11-21):**
  - `MemoryBlock.for` built a missing memory block through the user's association. A later `@user.update!` in the same director run, from `set_reply_length` or from `set_autonomy` for the owner's default level (spec 033), saved two empty blocks for the same scope. That broke the unique index, and the director gave no answer.
  - The block is now built outside the association. Reproducing test in `test/models/brain_test.rb`.
- **Security analysis (B20, after specs 001–039):**
  - Brakeman 0 warnings, bundle-audit no vulnerabilities.
  - The switch changes only the signed-in account's level, and only to 1–3 (an unknown value is refused).
  - The chat action needs the owner's own latest message. Step output and the director's wording cannot change the level (R4).
  - Accepted: the words that count as a request about length are broad ("krótko", "detail"). A misread can only change the reply length, which the owner sees under the reply and can switch back.
