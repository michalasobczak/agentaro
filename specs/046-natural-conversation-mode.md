# 046 — Natural conversation mode

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [017](017-voice-and-streaming.md), [039](039-reply-length-switch.md), [041](041-chat-settings-panel-style-and-tempo.md)

## 1. TL;DR

A new switch in the chat settings panel, **Rozmowa: Zwykła / Naturalna**. Naturalna makes the director talk like a person in a conversation: short turns, no lists or ids, said the way people say it. The voice gets livelier intonation and pauses, a short "już sprawdzam" fills a long silence, and system lines are not read aloud.

## 2. Abstract

- **Current state:**
  - The director's replies follow the reply length (spec 039) and the style (spec 041), but they read like reports: lists, quoted titles, ids, times written "15:10".
  - Piper reads them with its default intonation and fixed pauses.
  - While the director thinks, the voice is silent.
- **Gap or problem:** the owner's words: "potrzebuję bardziej naturalnej rozmowy, i głos i styl, może jakiś przełącznik konfiguracyjny".
- **Decision history:** the owner chose all four parts of the proposal, "wszystko po trochu" (2026-11-22): how the director talks, a livelier voice, a short acknowledgement, and not reading system lines aloud.

## 3. Objective

**Goals**
- G1. **The switch.**
  - "Rozmowa" with two options, Zwykła and Naturalna, is set on the account and shown in the chat settings panel. The default is Naturalna.
  - The owner can change it with words in the chat, through a `set_conversation` action, like the style.
- G2. **How the director talks (Naturalna).**
  - Turns of 1–3 sentences, unless the reply length is Szczegółowo or the owner asks for detail.
  - The director refers to what it just heard.
  - No lists, headings, ids or quoted titles unless the owner asks or the matter needs them.
  - At most one question, at the end.
  - No empty praise ("Świetne pytanie!").
  - Varied openings.
  - The style (Dziecko / Dorosły / Inżynier) still sets the words.
- G3. **A livelier voice (Naturalna).**
  - Piper speaks with more varied intonation and a short natural pause between sentences. The values are chosen by listening on this computer and fixed in code.
  - Before speaking, times, dates and numbers become words ("15:10" → "piętnasta dziesięć").
  - Ids, paths and links are left out, and markdown signs are removed.
- G4. **A short acknowledgement (Naturalna, voice on).**
  - When the director has not started its reply about 2 seconds after the owner's spoken message, the voice says one short phrase in the owner's language: "Już sprawdzam.", "Chwilka.", "Moment, patrzę.".
  - The phrases come from a fixed list. Their sound is made once and kept, so no model call is made.
  - At most one per message.
- G5. **What is read aloud (Naturalna).** The director's own words are read aloud. System lines are shown but not read aloud. These include what Agentaro applied under a reply and the "Done" line.

**Out of scope**
- Interrupting the director while it speaks (the owner rejected it in spec 024).
- Another speech engine or new voices.
- How the agents write their step results.

**Success criteria**
- S1.
  - With Naturalna, the director's prompt carries the conversation rule. With Zwykła it does not.
  - The rule sits together with the style and length rules.
- S2. Text prepared for speaking: "Krok 2 skończy się o 15:10, plik /tmp/a.md" becomes "Krok drugi skończy się o piętnastej dziesięć, plik", or similar. A unit test checks the times, numbers and paths.
- S3. In voice mode with Naturalna:
  - a 2-second wait before the reply plays one acknowledgement;
  - a reply that starts sooner plays none.
- S4. In voice mode with Naturalna, an "applied" line and the "Done" line are not sent to the speech engine. With Zwykła the reading is unchanged.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `users.conversation_mode` (1 Zwykła, 2 Naturalna) | to create |
| System | `ConversationMode` rule, `set_conversation` action | to create |
| System | `Voice`: Piper settings and speech text for Naturalna | to change |
| System | acknowledgement phrases (made once, kept in `storage/voice/`) | to create |
| System | `chat.js`: acknowledgement timer, what is read aloud | to change |
| System | chat settings panel: the Rozmowa switch | to change |

## 5. Functional Domain Changes

- **State:** a report-like director and a flat voice → a conversational director and a livelier voice, when the owner chooses it.
- **Rules:**
  - R1. Naturalna changes how things are said, never what is done. Actions and their checks are unchanged.
  - R2. Speech text conversion runs on the server before Piper, for Polish and English. Unknown forms are left as they are.
  - R3. The acknowledgement is not a message: it is not saved in the chat and not sent to the director.
- **Resilience:** without Piper, G3–G5 do nothing, and the text rules (G2) still apply.
- **Data:** a migration adds `users.conversation_mode`, not null, default 2.

## 6. Critical Path

1. The switch and the rule (G1, G2), with tests.
2. The speech text conversion (G3), with unit tests. Choose the Piper settings by listening.
3. The acknowledgement and what is read aloud (G4, G5), with JS tests.
4. A browser check with voice on the demo data, a B20 analysis, then CHANGELOG and README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | S1, S2 | model tests | commit | Zwykła leaves the prompt and the speech text unchanged |
| Integration | the switch saves, and `set_conversation` changes it only on request | request and runner tests | commit | — |
| JS | S3, S4 | `test/javascript` | commit | no acknowledgement in text-only chat |
| Manual | the owner talks with the director in Naturalna | the owner, on the phone and on the computer | — | — |

## 8. Expected Outcome

- **Direct effect:** the conversation sounds and reads more like talking to a person.
- **Side effects:**
  - in Naturalna, shorter replies give fewer details unless the owner asks;
  - the system lines must be read on the screen.
- **Rollback:** switch to Zwykła, or revert the code. The column stays unused.

## 9. Additional Information

- **Rejected alternatives:** a fourth style level instead of a switch. Rejected because style (which words) and conversation (how it flows) are separate choices.
- **Sources and questions:** none open.

- **Implementation (2026-11-22):**
  - `users.conversation_mode` (default 2, Naturalna). `ConversationMode` holds the rule, the hints and the acknowledgement phrases. `set_conversation` needs the owner's words.
  - `SpeechText` turns times, dates, numbers and percent into Polish or English words and drops links, paths and ids.
  - Piper in Naturalna runs with `--noise-scale 0.667 --noise-w-scale 0.8 --sentence-silence 0.25`. These are Piper's general defaults; the Polish voices ship flatter (0.5 and 0.333). The values have not yet been chosen by listening (G3): the owner should listen and say if they want them changed.
  - Acknowledgement sounds are kept in `tmp/voice/` (not tracked), not `storage/voice/`. Only the fixed phrases are kept.
  - G5 was already true: system lines and the "applied" notes were never spoken. Tests cover it.
  - Tests: `speech_text_test.rb` (5), `conversation_mode_test.rb` (3), `voice_natural_test.rb` (4 JS scenarios). The spec 041 panel test was adapted to 7 settings.
