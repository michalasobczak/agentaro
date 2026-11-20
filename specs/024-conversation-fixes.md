# 024 — Conversation fixes

Status: **implemented** 2026-11-20. The owner decided each point in the chat on 2026-11-20 (§9, Q1–Q6).
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [017](017-voice-and-streaming.md), [019](019-verifier.md), [021](021-director-sees-step-output.md), [023](023-agent-status.md)

## 1. TL;DR

A conversation with the director now works like other chats. Nobody interrupts anyone. While the director (or the verifier) writes or speaks, the user's messages wait in the chat. When it has finished, they go together and get one answer. The director reads the whole conversation, every message is seen, and the chat's team strip shows each member as initials whose colour says what it is doing. Model and integration tests and a browser check on demo data confirm it.

## 2. Abstract

- **Current state (before this spec):**
  - If the user wrote while the director was answering, the answer was dropped and written again (owner fix after spec 017, earlier the same day).
  - Voice mode stopped the director when the user spoke over it (spec 017, G6).
  - The work-list proposal pass of spec 021 saw only the latest user message.
  - The chat strip of spec 023 showed names and "free" or "busy …" in words.
- **Gap or problem.** The owner reported the following problems on 2026-11-20:
  - "wypowiedzi giną i wracają": replies vanished and came back.
  - "director nie wie, o czym mowa": the director lost track of the conversation.
  - Two similar greetings after "hi there" and "cześć".
  - "3 kropki falują": the typing dots kept moving after the answer.
  - "nie róbmy przerywania, że ja ważniejszy jestem".
  - "nazwy agentów tylko inicjałami… kolorami co się z nimi dzieje".
- **Rationale:** the conversation is the main way to use Agentaro, by text and by voice. A dropped answer, an interruption or a missed message breaks it.
- **Decision history:**
  - In the morning, answers were dropped and rewritten when the user wrote again. It was meant to keep answers current, but it made replies vanish and reappear.
  - The check for a newer message also read a cached database answer in background runs, so it did not work in production (R5).
  - The owner then chose waiting over interrupting (Q1–Q3).

## 3. Objective

**Goals**
- G1. **Messages wait for the speaker.**
  - While the director or the verifier writes, or voice mode reads the answer aloud, what the user sends waits in the chat, marked "Waiting for the director to finish…".
  - When they have finished, everything waiting is sent at once.
- G2. **One answer to everything that waited.** The director answers it once, and the proposal pass reads all of it as the request.
- G3. **No interruptions.**
  - An answer is never dropped or rewritten because the user wrote again.
  - Voice mode no longer stops the director when the user speaks.
  - The microphone listens only after the director has finished.
- G4. **The director keeps the conversation.**
  - The answer posted is the one written with the whole conversation, the same one shown and spoken while it streams.
  - The proposal pass sees the earlier conversation and only decides the changes.
  - What was really applied is noted under the answer.
- G5. **Every message is seen.** Runs read the database without the query cache.
- G6. **Speech recognition hint.** Whisper gets Agentaro's words and the team's names.
- G7. **Team strip as initials with colours.**
  - In the chat, each member is shown by up to two initials.
  - Green means free; amber, pulsing, means busy.
  - The name and the state stay in the tooltip and for screen readers.

**Out of scope**
- A bigger Whisper model (owner: not now).
- Interrupting on purpose (a "stop" button for the director).
- The Team page keeps names and words.

**Success criteria**
- S1. In the owner's flow ("hi there", then "cześć" while it writes), the chat shows: "hi there" → answer → "cześć" → answer. Nothing appears twice, and nothing vanishes and comes back.
- S2. Two or three messages sent while the director writes get one answer, in order.
- S3. A short answer ("q4 zajęty") to the director's question is understood in context.
- S4. The typing dots disappear when the director has finished.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `app/assets/javascripts/chat.js`: waiting queue, sending in batches, voice without barge-in, listeners tied to the chat's lifetime, day separator | to change |
| System | `ChatMessagesController#create`: `chat_message[contents][]` (up to 10) | to change |
| System | `ManagementRunner`: no fresh starts; first answer posted; proposal pass with conversation and all waiting messages; `perform!` without query cache | to change |
| System | `Agentaro::TaskScheduler` worker without query cache | to change |
| System | `Voice.transcribe`: `--prompt` hint, `Voice.names_for`, `Voice.hint` | to change |
| System | `_chat.html.erb` team strip, `app.js` status apply, `application.css` | to change |
| Data | none (no migration) | — |

## 5. Functional Domain Changes

- **State:**
  - Before: "the latest message wins" (answers dropped).
  - After: "turns" (messages wait; every answer is kept).
- **Rules:**
  - R1. **When the chat is busy.**
    - The chat is busy while the server says the director or the verifier is writing, while voice mode is speaking, or while a send is on its way.
    - Messages sent while the chat is busy wait, in order, below the reply being written.
    - They are kept in the tab's session storage, so a reload does not lose them.
  - R2. **Sending what waited.**
    - When the chat stops being busy, up to 10 waiting messages are sent in one request.
    - The server saves them in order in one transaction and queues one chat run.
    - A refused batch saves nothing. The text goes back to the input field.
  - R3. **Answers are always posted.**
    - The director's answer is always posted. It records the message it answers (`reply_to_id`).
    - A message that still arrives meanwhile, for example from another tab, gets the next answer.
    - The chat marks an answer written before the user's latest message ("Answer to an earlier message"). Voice does not read it.
  - R4. **The proposal pass.**
    - The answer from the first pass is posted.
    - When that answer proposes work-list or space changes, a second pass is called. It is not streamed, and it decides the actions.
    - The second pass gets:
      - the earlier user and director messages (up to 30) as context only;
      - all user messages since the director's last answer as the request.
    - It does not get step output or verifier comments.
    - What was applied, or "No changes were made to the work list or spaces.", is shown under the answer.
  - R5. **No query cache in runs.** Director, verifier, epic-step and task runs read the database without the query cache. A run lasts seconds to minutes and must see what other requests save (a newer message, a cancelled epic).
  - R6. **Voice mode.**
    - The microphone ignores sound while the director speaks.
    - Voice mode started while the director writes waits ("The director is finishing…") and starts listening when it has finished.
    - Typed messages wait while an answer is read aloud.
  - R7. **Speech hint.**
    - Whisper's `--prompt` carries a fixed sentence of Agentaro's words and the names of the user's team, without control characters, at most 400 characters.
    - A transcript that is only the hint counts as silence.
  - R8. **The team strip.**
    - Each member's icon shows its initials (spec 023 owner fix: up to two).
    - The icon's colour is the state, updated live with the strip.
    - Name and state are in `title` and in visually hidden text. Spec 023 R11 asks for text, never colour alone; the visually hidden text and the tooltip meet it.
    - Phones show the same single row.
  - R9. **A chat replaced by a Turbo visit stops listening.** Its form, input, buttons and voice controls are tied to its lifetime, so one Enter never sends twice. Its waiting bubbles are removed; the messages stay stored for the new chat.
- **Resilience:**
  - Offline or a failed send: the waiting bubbles show the error, and the text returns to the input field.
  - A server restart: waiting messages are still in the tab.
- **Data:** no schema change.

## 6. Critical Path

1. Server: no fresh starts, batches in `create`, proposal pass inputs, no query cache.
2. Chat: waiting queue, flush when no one is speaking, voice without barge-in, listeners tied to the chat's lifetime.
3. Strip: initials and colours.
4. Tests, then a browser check on demo data with a slow stand-in director.

Done when all tests pass and S1–S4 are seen in the browser.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | answer kept when a message arrives meanwhile; next answer queued; with the query cache on, a message saved by another connection is seen; several waiting messages → one answer, proposal reads all; short answer understood; hint passed and dropped when alone | `test/models/chat_order_test.rb`, `test/models/voice_test.rb` | merge | the query-cache test fails on the code before R5 |
| Integration | `contents[]` saves in order and queues one run; 11 or a blank one refused, nothing saved; strip chips carry `is-busy`/`is-free`, title and hidden text | `test/integration/director_chat_test.rb`, `test/integration/team_status_test.rb` | merge | no inline `style=`, no inline script |
| E2E (browser) | S1, S2, S4 and live strip colours on demo data with a slow stand-in director | demo server, 2026-11-20 | release | waiting messages restored after a reload are sent once, not twice |
| Manual | owner's real conversation by text and voice | owner | — | — |

## 8. Expected Outcome

- **Direct effect:**
  - Conversations keep their order.
  - Nothing vanishes and reappears.
  - No double answers.
  - The director remembers what the user answers to.
- **Measurable effect:** in production data, each director answer's `reply_to_id` is the newest user message before it, except when messages come from two tabs at once.
- **Side effects:**
  - A message sent while the director writes is answered later than before, after the current answer.
  - The phone strip no longer collapses.
- **Rollback:** revert the commit. There is no data change.

## 9. Additional Information

- **Rejected alternatives:**
  - Dropping and rewriting the answer (the morning fix). It made replies vanish, and with the query cache it did not even work.
  - Disabling Send while the director writes. The owner chose waiting messages instead (Q1).
- **Technical debt:**
  - Waiting messages live in one tab. Two tabs keep two queues, and the server then answers them in turns (R3).
  - The hidden "N of M busy" toggle is still in the markup.
- **External dependencies:** none.
- **Sources and questions (answered by the owner on 2026-11-20):**
  - Q1. Where does a message wait? In the chat, marked as waiting, sent when the director has finished (not a blocked Send button).
  - Q2. Several messages? One answer to all.
  - Q3. Voice? The microphone listens after the director has finished; no speaking over it.
  - Q4. The proposal pass? The first answer is posted; the second pass decides the changes and sees the conversation. F-021-OF1 is accepted (spec 021).
  - Q5. A bigger Whisper model? Not now; the hint only.
  - Q6. Strip? Initials only; colours instead of "free" and "busy".
- **Earlier owner fixes of the same day that this spec gathers** (described in their own specs):
  - the first answer is posted and the proposal pass gets context (spec 021);
  - the speech hint (spec 017);
  - no query cache in runs (spec 017).

## Security analysis (B20), after spec 024

- **Batches (`contents[]`).**
  - At most 10 messages per request.
  - Each must be non-empty and at most 5,000 characters, and they are saved in one transaction.
  - The per-user rate limit (20 requests in 10 minutes) still counts requests. A batch can therefore carry up to 10 messages per request.
  - Accepted: they still need a signed-in user and CSRF, and they start one run.
- **No query cache in runs.** It only makes reads fresher; there is no new data path.
- **Proposal pass.** F-021-OF1 still applies (accepted in spec 021). The waiting messages are the user's own words.
- **Speech hint.**
  - Agent names reach whisper as one argument, with no shell, cleaned of control characters and limited in length.
  - A hostile agent name can only bias the transcription of its owner's own speech.
- **Chat script.**
  - It still uses only `textContent`, and adds no inline style or script.
  - Waiting messages in `sessionStorage` stay in the tab and are the user's own text.
- **Strip.** Names are escaped by ERB and set with `textContent` by `app.js`.
- **Tools.**
  - Brakeman: 0 warnings.
  - No new gems.

## Owner fixes after release (2026-11-20)

- **"Poprosiłem directora o status i pisał dwie wiadomości jednocześnie."**
  - The database held one answer and one run. The server log showed several copies of the chat polling at once. Some of them kept asking for messages after an id they had already shown. That happens when two copies work on the same element: one draws the message, and the other sees it "already shown" and never moves on. Each copy draws its own reply being written, so two replies appeared at once.
  - The exact navigation that made the second copy was not reproduced: the browser pane was hidden during the check. The fix removes every way to get one:
    - the chat script runs once per tab;
    - a new chat on an element ends the one already there;
    - a chat whose element has been off the page for three polls ends itself;
    - ending a chat also removes its reply bubble.
  - Checked in the browser: loading the script a second time leaves the same two chats (page and floating).
- **"Model zwraca formatowanie **xxx**, ale czat tego nie formatuje."**
  - Messages show a small, safe part of Markdown: **bold**, *italic*, `code`, "- " and "1. " lists, and "# " headings.
  - The server (`ChatFormatHelper`) and `chat.js` build the same structure from tags whose text is escaped (`textContent`). Nothing from a message becomes HTML.
  - Voice still reads the plain text.
  - Tests: `test/helpers/chat_format_helper_test.rb`, including a script tag and lone stars.
