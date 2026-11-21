# 035 — Mute the microphone in voice mode

Status: **implemented** (2026-11-21, epic step 2, on the proposals for Q1–Q4; owner to confirm). Behaviour of S1–S3, S5 and R9 tested automatically (step 3); the walkthrough with a real microphone is still pending
Date: 2026-11-21
Depends on: [017](017-voice-and-streaming.md), [019](019-verifier.md), [020](020-pages-without-reloading.md), [024](024-conversation-fixes.md)

## 1. TL;DR

In voice mode, the user gets a **Mute** toggle for the microphone. While muted, nothing they say is recorded, recognised or sent to the director, so they can speak to someone in the room. Clicking again resumes listening, and the conversation carries on without being restarted. A recording in progress when the user mutes is thrown away. Integration tests check the markup and accessibility. A browser walkthrough with a real microphone checks that nothing reaches `/director/voice/transcribe` while muted.

## 2. Abstract

- **Current state (code read 2026-11-21, `app/assets/javascripts/chat.js`, function `voice`, spec 017):**
  - The voice button (`[data-voice-start]`) calls `begin()`. That function opens an `AudioContext` and gets the microphone with `navigator.mediaDevices.getUserMedia({ audio: { echoCancellation, noiseSuppression, autoGainControl } })`. It then connects the stream to a `ScriptProcessorNode` (4096 samples, mono). There is no `MediaRecorder` and no VAD library.
  - Every audio block goes to `onAudio(samples)`. This is energy-based voice activity detection:
    - The RMS level is compared with a learnt noise floor (threshold `max(0.015, floor × 4)`).
    - 150 ms above the threshold switches **listening → hearing**. The recording keeps up to 3 blocks of preroll.
    - 1 s of quiet ends the utterance (`SILENCE_MS`), and so does reaching 30 s (`MAX_SPEECH_MS`). Utterances shorter than 600 ms are dropped (`MIN_SPEECH_MS`).
    - Samples are kept in `chunks` (the utterance), `preroll` and `heard` (everything since listening began, up to 30 s, for the **Done** button).
  - `transcribe(parts)` turns the samples into a 16 kHz mono WAV and makes one `POST /director/voice/transcribe` request (`ChatMessagesController#transcribe`). On the server, `Voice.transcribe` (whisper.cpp) produces text. A non-empty text is saved at once as a user `ChatMessage` with `spoken: true`, and `ManagementRunner.chat!` queues the director's answer. **Recognition and sending to the director happen in that one request**; the browser does not send the text separately.
  - Answer: the streamed reply is cut into sentences. `say()` asks `POST /director/voice/speak` (Piper) for each one and plays it on the same `AudioContext`. While it plays, the state is **speaking**, `onAudio` ignores the microphone (spec 024, "nie róbmy przerywania"), and typed messages wait (`chat.hold`). After the last sentence, `afterSpeech()` returns to **listening**.
  - States: `off`, `listening`, `hearing`, `transcribing`, `thinking`, `speaking`, `error`. The panel (`[data-voice-panel]` in `app/views/directors/_chat.html.erb`) shows dots, a state label, a note, the speed switch, the verifier button, **Done** and **End voice mode**. One partial serves the Director page and the floating chat. On the Director page, voice runs in the floating chat (spec 020), which survives Turbo visits.
  - The only way to stop listening is **End voice mode** (`end()`). It stops the microphone tracks, closes the `AudioContext` and hides the panel.
- **Gap:** the user cannot pause the microphone for a moment. To speak with someone else they must end voice mode and start it again, or the conversation is recorded and sent to the director.
- **Rationale:** the epic "Wyciszanie mikrofonu w trybie rozmowy głosowej" (2026-11-21) asks for this: "Gdy mikrofon jest wyciszony, nic z tego, co mówi użytkownik, nie trafia do rozpoznawania mowy ani do dyrektora, żeby mógł porozmawiać z kimś innym. Stan wyciszenia ma być wyraźnie widoczny, a ponowne kliknięcie przywraca nasłuch."
- **Decision history:**
  - Spec 017 Q3: hands-free conversation.
  - Spec 024: no interrupting; the microphone waits while the director speaks.
  - Spec 019 G6: the voice panel's verifier button is a toggle with `aria-pressed`. The mute toggle follows the same pattern.

## 3. Objective

**Goals**
- G1. A **Mute** toggle in the voice panel, available in every voice state (listening, hearing, transcribing, thinking, speaking, error).
- G2. While muted, no microphone samples are kept, no `POST /director/voice/transcribe` is made, and no spoken message reaches the director.
- G3. Muting discards a recording in progress (states listening and hearing): the utterance, the preroll and the buffer behind **Done**.
- G4. Unmuting resumes listening on the same microphone stream and `AudioContext`. There is no new `getUserMedia` call, no new voice session, and the conversation and the director's state are kept.
- G5. The muted state is clearly visible and accessible. The button has a crossed-out microphone icon, a visible label and `aria-pressed="true"`, and the panel is marked as muted. Screen readers hear the change.
- G6. The director's speech is not affected by muting (proposal, Q2).

**Out of scope**
- A keyboard shortcut for muting (a possible later fix).
- Muting the director's voice, which would be a speaker mute.
- Changes to the server, Whisper, Piper or the database.
- Remembering the mute between voice sessions or devices (Q3).
- Withdrawing a recording that was already sent before the user muted (Q1).

**Success criteria**
- S1. With the microphone muted for 60 s while the user speaks aloud, the browser's network panel shows **zero** requests to `/director/voice/transcribe`, and the chat gains no user message.
- S2. A user who starts speaking (state "Listening…" with green dots) and mutes before the pause produces no request to `/director/voice/transcribe`. After unmuting, the next utterance is transcribed **without** the words spoken before or during the mute.
- S3. After unmuting, the next utterance is transcribed and answered as before (text in the chat, spoken answer). This works without clicking the voice button again and without a new microphone permission prompt.
- S4. The mute button is in the voice panel on the Director page and in the floating chat. It is a `<button type="button">` with a constant accessible name and `aria-pressed` that matches the state. The muted panel shows "Microphone muted" and a different icon and colour. A screen reader announces "Microphone muted" or "Microphone on" when the state changes.
- S5. A director's answer that is being read aloud when the user mutes keeps playing to the end. After it ends, the panel stays muted and does not switch to listening.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `app/views/directors/_chat.html.erb`: a `[data-voice-mute]` button in `[data-voice-panel]` (`type="button"`, `aria-pressed="false"`, `aria-label="Mute microphone"`, icon plus a visible label), and a visually hidden `role="status"` region `[data-voice-mute-status]` | to change |
| System | `app/assets/javascripts/chat.js`, function `voice`: a `muted` flag; `mute()` and `unmute()`; an early return in `onAudio` when muted; clearing `chunks`, `preroll`, `heard`; `track.enabled`; the label and note in `setState`; **Done** hidden while muted; `end()` and `begin()` reset the flag | to change |
| System | `app/helpers/application_helper.rb`: icons `mic` and `mic_off` (inline SVG paths, like the existing ones) | to change |
| System | `app/assets/stylesheets/application.css`: `.voice-mute`, `.voice-mute.is-on`, `.voice-panel[data-muted="true"]` (still grey dots, its own background, `prefers-reduced-motion` respected); no inline styles | to change |
| System | `test/integration/director_chat_test.rb` (or `test/integration/voice_test.rb`): markup and accessibility of the toggle on both chats; it is absent when voice is not set up | to change |
| System | Server: `ChatMessagesController#transcribe`, `VoicesController`, `Voice`, routes | no change |
| Data | Database, migrations | no change |
| Organization | `README.md` (Director and verifier: muting in voice mode; spec list), `CHANGELOG.md` | to change |

## 5. Functional Domain Changes

- **State:** voice mode can only be ended → voice mode can also be **muted** without ending. Muted is a flag alongside the state, not a new state. The director's work (thinking, speaking, the verifier) goes on while muted.
- **Rules:**
  - R1. **Placement:** the toggle is in the voice panel, right after the state text (`.voice-info`) and before the speed switch. It is the first control after the state, so it is easy to find, and it stays separate from **End voice mode** so the two are not mixed up. On narrow chats it wraps with the panel (existing `@container` rule).
  - R2. **Not muted:** microphone icon, label "Mute", `aria-pressed="false"`, the panel's normal look.
  - R3. **Muted:**
    - The button: crossed-out microphone icon, label "Muted", filled with the warning colour (`--warn`), `aria-pressed="true"`, `title` "Microphone muted — click to listen again".
    - The panel: `data-muted="true"`, still grey dots, `--warn-soft` background.
    - The state label: "Microphone muted" while the state would be listening or hearing. While thinking or speaking, the label stays ("Thinking…", "Speaking…") and the note says "Microphone muted — nothing you say is sent."
    - The accessible name stays "Mute microphone" in both states. Only `aria-pressed` changes, as for the verifier toggle.
    - `[data-voice-mute-status]` announces "Microphone muted" or "Microphone on" once per change.
  - R4. **What muting stops:**
    - At once, `onAudio` stops keeping samples: it returns before any buffering and does not learn the noise floor.
    - `chunks`, `preroll` and `heard` are cleared, along with the counters `loudMs`, `quietMs`, `speechMs`, `heardMs` and `peak`.
    - The microphone tracks get `enabled = false`, so the browser delivers silence.
    - The state hearing changes to listening (shown as muted). **Done** is hidden.
    - No path while muted can call `transcribe`: not the pause, not the 30 s limit, not **Done**.
  - R5. **A recording in progress is discarded:** speech captured in listening or hearing before the mute is not sent and does not join the next utterance.
  - R6. **A recording already sent** (state transcribing) when the user mutes is not withdrawn. It was spoken before the mute and has already left the browser, and the server saves it with its recognition. Its answer comes as usual (proposal, Q1).
  - R7. **Unmuting:**
    - The tracks get `enabled = true` and the buffers start empty.
    - In listening or hearing, the panel shows "Listening…" with the note "Speak; I send when you pause." In thinking or speaking, listening comes back as today, after the director (and the verifier) finish.
    - There is no new `getUserMedia`, no new `AudioContext`, and no change to `generation`, `askedId` or waiting messages.
  - R8. **The director's voice** is not affected: sentences already queued and later ones are spoken while muted (proposal, Q2). After speech, `afterSpeech()` goes to listening, which shows as muted while the flag is on.
  - R9. **End voice mode** clears the mute. Each new voice session starts unmuted (proposal, Q3). The mute survives Turbo visits along with the floating chat (spec 020).
  - R10. Typed messages, the verifier toggle and the speed switch work the same while muted.
  - R11. An error (state error) while muted: the panel shows the error. The automatic return to listening after 2.5 s keeps the mute.
  - R12. The toggle works with the keyboard: Tab, then Space or Enter, as a native `<button>`.
- **Resilience:** muting depends on no server or network. If `track.enabled` cannot be set (a missing track), the early return in `onAudio` alone guarantees R4. A response from an earlier transcription that arrives after unmuting is handled as today (`generation`).
- **Data:** no change.

## 6. Critical Path

1. Owner closes Q1–Q4.
2. Integration test for the toggle's markup and accessibility on both chats; it fails before the change.
3. `mic` and `mic_off` icons; the button and status region in `_chat.html.erb`; CSS for both states.
4. In `chat.js`: the `muted` flag, `mute()` and `unmute()`, the guard in `onAudio`, clearing the buffers, `track.enabled`, labels, Done hidden, reset in `begin()` and `end()`.
5. `bin/rails test` green; CSP test green (no inline style or script).
6. Browser walkthrough with a real microphone on a demo instance (AGENTS.md), with the network panel open: S1–S5.
7. README, CHANGELOG, restart of the owner's instance, B20 security analysis.

Completion: all gates below pass, and the owner has done the walkthrough or accepted it.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit (behaviour) | The real `voice()` from `chat.js`, run in JavaScriptCore with a fake panel, microphone, `AudioContext` and `fetch`: S1 (60 s of speech while muted, pauses and Done → 0 requests to `/director/voice/transcribe`, 0 messages), S2/S3 (mute while hearing → discarded; after unmuting the next utterance is sent alone, holds no sample from before or during the mute, is answered and spoken, and the next one is sent too; one `getUserMedia`, one `AudioContext`), S5 (the director's speech is not stopped; the panel stays muted after it), R9, and no mute while off. `aria-pressed`, label, `is-on`, `data-muted`, note, Done, `track.enabled` and the announcement are checked in each | `bin/rails test` (`test/javascript/voice_mute_test.rb`); skipped with a message when `jsc` is missing (`AGENTARO_JSC` sets the path) | merge | The scenarios fail on `chat.js` before spec 035; removing the guard in `onAudio` or in `transcribe()` makes them fail |
| Integration | Both chats (`.content .director-layout > .chat-app` and the floating chat) have one `[data-voice-panel] button[type=button][data-voice-mute][aria-pressed=false][aria-label="Mute microphone"]` with an `svg.icon`, and one `[data-voice-mute-status][role=status]` | `bin/rails test` (`director_chat_test.rb`) | merge | With voice not set up (`data-voice="missing"`), voice mode cannot start, so the toggle cannot be used. The layout test finds no inline `style=` or `<script>` |
| Contract | The server API is unchanged: `POST /director/voice/transcribe` and `/speak` behave as in specs 017 and 024 | the existing tests in `voice_test.rb` and `director_chat_test.rb` stay green, with expected results unchanged | merge | A silent recording still creates no message and no run |
| E2E | — (no browser automation in the project; Q4) | — | — | — |
| Manual | S1–S5 on a demo instance with a real microphone. In addition: Tab reaches the toggle, Space toggles it; VoiceOver reads "Mute microphone, toggle button, not pressed" and announces "Microphone muted"; the dark theme looks right | browser walkthrough with DevTools → Network filtered to `transcribe`; `ChatMessage` count before and after; screenshots of both states | release (README status "implemented") | Muted with speech → 0 requests and 0 new messages. Mute while hearing → 0 requests. After unmuting, the transcript holds no words from before or during the mute. No microphone prompt after unmuting |

## 8. Expected Outcome

- **Direct effect:** the user can pause the microphone in voice mode with one click and resume with another, without losing the conversation.
- **Measurable effect:** 0 requests to `/director/voice/transcribe` and 0 spoken messages while muted (S1, S2). Listening returns within one audio block (about 0.1 s) after unmuting, with no permission prompt (S3).
- **Side effects:**
  - The operating system's microphone indicator may stay on while muted. The stream stays open, and the browser delivers silence (`track.enabled = false`). The panel says clearly that nothing is sent.
  - One more button in the voice panel. On narrow chats the panel wraps.
- **Rollback:** revert the commit. There are no data or server changes.

## 9. Additional Information

- **Rejected alternatives:**
  - Stopping the tracks with `track.stop()` and calling `getUserMedia` again to unmute. Safari may ask for permission again, echo cancellation would have to settle again, and the epic asks for unmuting without restarting.
  - Suspending the `AudioContext`. That would also stop the director's voice, which plays on the same context, against R8.
  - A new state `muted` in the state machine. Muting is independent of the director's states (thinking, speaking), and a flag keeps those flows unchanged.
  - Muting only on the server (rejecting transcriptions). The audio would still leave the browser, against G2.
- **Technical debt:** the rest of `chat.js` (spec 017 and later) still has no behaviour tests. The voice harness (`test/javascript/voice_harness.js`) can carry them. It runs only on macOS (`jsc` is part of the system) and cuts `voice()` out of `chat.js` by its indentation.
- **External dependencies:** none new. The browser's `MediaStreamTrack.enabled` is supported by Safari, Chrome and Firefox.
- **Sources and questions:**
  - Q1. A recording that was already sent (state transcribing) when the user mutes: let it go through (proposal; it was spoken before the mute and the server has already saved it), or ignore its answer in voice mode? `[TO BE DETERMINED]`
  - Q2. The director's speech while the microphone is muted: keep playing (proposal; muting is about what the user says, and **End voice mode** stops everything), or pause or stop it? `[TO BE DETERMINED]`
  - Q3. Should the mute survive ending and restarting voice mode? Proposal: no, every voice session starts unmuted, so the user is never silently not heard. `[TO BE DETERMINED]`
  - Q4. Behaviour gates are manual, as in spec 017. Should we now add a JavaScript test runner or browser automation so G2–G4 can be tested automatically? Proposal: not in this spec; a separate spec for testing `chat.js`. `[TO BE DETERMINED]`
  - Source: epic "Wyciszanie mikrofonu w trybie rozmowy głosowej" (director, space Agentaro, 2026-11-21), step 1 of 3.

## Implementation notes (2026-11-21)

- Q1–Q4 were implemented on the proposals (director's epic step 2): a recording already sent goes through; the director keeps speaking while muted; every voice session starts unmuted; no JavaScript test runner in this spec. The owner can reopen any of them.
- `chat.js`: `muted` flag; `setMuted()` clears `chunks`, `preroll`, `heard` and the counters (`forget()`), sets `track.enabled` on the audio tracks, turns hearing into listening; `showMute()` drives the button (`is-on`, `aria-pressed`, title, label "Mute"/"Muted"), the panel (`data-muted`), the label "Microphone muted", the note and Done. Guards against sending while muted: the first line of `onAudio`, `done()`, and `transcribe()`. `begin()` and `end()` call `resetMute()` (R9); `end()` also clears the buffers.
- Markup: both icons (`mic`, `mic_off`) are in the button and CSS shows one, so no SVG is built in JavaScript. The `role="status"` region is the last child of the panel, so the toggle is directly followed by the speed switch.
- CSS: muted fill `--warn` with `--surface` text (white on dark orange in the light theme, dark on light orange in the dark theme); the panel gets `--warn-soft`, a `--warn` left edge and still grey dots.
- Tests: `director_chat_test.rb` "spec 035" (markup, accessibility, placement, CSP). Full suite on HEAD + this change: 411 runs, 0 failures; 4 errors only in the agent sandbox (tests that bind a local port), not related. Brakeman 0 warnings.
- **Security analysis (B20), spec 035 and earlier:** no server, route, data or dependency change; no new endpoint or parameter. No `innerHTML`, no inline `style=` or `<script>` (`textContent`, `classList`, `setAttribute` only; the CSP test is green). Privacy improves: while muted the browser delivers silence (`track.enabled = false`) and `onAudio` keeps nothing, so no audio can leave the browser; a flag reset on `begin()`/`end()` means no hidden muted state across sessions, and `pagehide` still ends everything. Residual: the OS microphone indicator stays on while muted (the stream stays open, as spec section 8 says). No regressions found in specs 017, 019, 020, 024 (voice endpoints, verifier, Turbo dock and no-interrupting tests unchanged and green).

## Verification (2026-11-21, epic step 3)

- **Automatic behaviour tests** (`test/javascript/voice_mute_test.rb`, 6 tests): the real `voice()` cut out of `chat.js` runs in JavaScriptCore (`/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc`, part of macOS) with fakes from `test/javascript/voice_harness.js`; scenarios in `voice_mute_scenarios.js`. No gem, npm package or browser; Q4 stays open for a general runner or browser automation. Speech before and during the mute is fed at one level and speech after unmuting at another, so the test reads the sent WAV and proves no earlier sample is in it. The fake microphone keeps sending sound while muted, so the guard in `onAudio` is tested on its own, not only `track.enabled`.
- **Negative checks:** all scenarios except "off" fail on `chat.js` from the commit before spec 035. Without the early return in `onAudio`, S1 fails; without the guard in `transcribe()`, S1, S2 and S5 fail (the recording would be sent). Removing `forget()` from `setMuted()` changes nothing, because `listen()` clears the buffers too.
- **Full suite** (temporary copy of the folder, `PARALLEL_WORKERS=1`, because the agent sandbox blocks `storage/` and DRb sockets): 437 runs, 3444 assertions, 0 failures, 4 errors. The errors are the 4 tests that open a local port (executor and task-run API checks), which the sandbox forbids; they are not related.
- **Not checked:** a real browser and microphone. The agent sandbox cannot bind a port for a server and has no microphone. Still to do by the owner (spec section 7, Manual): S1–S5 with DevTools → Network filtered to `transcribe`, the look in both themes, VoiceOver and the keyboard.
- **Limits of the automatic tests:** the fakes stand in for the Web Audio API, so they do not prove that a real browser delivers silence for `enabled = false` (Safari, Chrome and Firefox document it), nor how the button looks. The cut of `voice()` relies on its indentation in `chat.js`; a test fails if the cut breaks.
- **Security analysis (B20) for this step:** tests only; no application code, route, data or dependency changed. The harness runs local files with the system `jsc` and no network. Earlier conclusions stand.
