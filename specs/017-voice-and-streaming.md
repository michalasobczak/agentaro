# 017 — Talking to the director: voice and streamed answers

Status: **implemented** 2026-11-20, E2E with a real microphone pending the owner (closed by owner: Q1 "Whisper lokalnie", Q2 Piper, Q3 "Bez rąk", Q4 "Czat z dyrektorem", Q5 "Tak, instaluj")
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [015](015-new-conversation.md)

## 1. TL;DR

The user can **talk** to the director. A voice button starts a hands-free conversation, like the dots in ChatGPT:
- the browser listens and notices when the user stops speaking;
- **Whisper** on the host turns the speech into text, which is sent as a chat message;
- the director's answer **streams** into the chat word by word, and a natural **Piper** voice on the host reads it sentence by sentence;
- then the browser listens again.

Whisper and Piper run on the host. The recording flow is verified with stand-ins. The microphone walkthrough for the updated flow is pending.

## 2. Abstract

**Current state.** The user types to the director (spec 011), and the director's answer appears only when it is complete.

**Need (owner, 2026-11-20).**
- "chciałbym, żebyś dodał opcję whisper transkrypcji mojego głosu w rozmowie i żeby dyrektor też mówił… wciskam przycisk kropki rozmowy takiej jak na GPT i rozmawiam"
- "zrób tak też, żeby odpowiedź z LLM modelu była strumieniowana"
- The voice must be "w miarę sensowny głos, nie głos robota".

**Owner decisions.**
- Q1: speech recognition is **local Whisper** (whisper.cpp on the host); the browsers' own recognition would send audio to Apple or Google.
- Q2: the director's voice is **Piper**, a local neural voice in Polish.
- Q3: the conversation is **hands-free**: the end of speech is detected automatically, and the user can interrupt the director.
- Q4: streaming covers the **chat with the director**.
- Q5: Claude installs the tools on the host, with the owner's consent.

## 3. Objective

**Goals**
- G1. **Voice button** in the chat composer (Director page and floating chat). It starts and stops voice mode. Voice mode shows animated dots for its state: *listening*, *thinking*, *speaking*.
- G2. **Listening:** the browser records the microphone (with echo cancellation) and detects speech and the following silence (about 1 second). Each utterance (at most 30 seconds) is sent to Agentaro as 16 kHz mono WAV.
- G3. **Transcription:** Agentaro runs whisper.cpp on the audio, recognising the language, and saves the text as a spoken chat message in the same request. Chat validation applies to the transcript. Empty or noise-only recordings are dropped. Stopping voice mode ends listening and playback. An already submitted recording can finish processing.
- G4. **Streaming:** while the director answers, the text of its `reply` appears in a streaming bubble that grows word by word. The final message replaces the bubble, with its actions as before. Streaming is supported for Claude Code (stream-json), the Ollama API and OpenAI-compatible APIs; other executors answer at once at the end, as today.
- G5. **Speaking:** in voice mode, every complete sentence of the reply is turned into speech by Piper on the host and played in order, starting while the rest of the answer is still being written. When the director is done, listening starts again.
- G6. **Interrupting:** speaking while the director talks stops the audio and starts a new turn.
- G7. **Setup:** the tools and models live outside the repository, in `storage/voice/`, with their paths in settings. When a tool is missing, the voice button explains what to install; text chat keeps working.

**Out of scope**
- Voice for other agents or for step results; voice cloning (XTTS); wake words; continuous transcription while the user speaks; streaming of epic steps.

**Success criteria**
- S1. A spoken sentence becomes a chat message with its text, and the director's answer is heard, without touching the screen after starting voice mode (owner's Mac and iPhone).
- S2. The first words of a Claude answer appear in the chat before the whole answer is finished (stand-in test, and seen on the host).
- S3. No audio or text leaves the host. Audio is kept only as a temporary file, deleted after transcription (test).
- S4. Only signed-in users can transcribe and synthesize. Upload size, speech request size and synthesis rate are bounded. The tools run without a shell, with fixed arguments and a timeout (tests).
- S5. Text chat is unchanged when the voice tools are missing (test).
- S6. A signed-in user can submit and save 241 consecutive recordings in the same rate-limit window in which they exhaust the typed-chat quota (integration test).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Host | whisper.cpp (Homebrew), Whisper model, Piper (Python venv) with a Polish voice, in `storage/voice/` | to install |
| System | `Voice` (transcribe with whisper.cpp and speak with Piper using fixed arguments and timeouts); `POST /director/voice/transcribe` saves spoken chat messages, `POST /director/voice/speak` synthesizes replies | implemented |
| System | Streaming: `HostProcess` passes output as it arrives; `AgentCall` streams Claude (`ClaudeStream`), Ollama and OpenAI-compatible answers; the partial reply is kept in the server's memory (`ReplyStream`), not in the database (each write would add a data changelog entry); the chat poll returns it | to change |
| System | `chat.js` voice mode (recording, silence detection, WAV encoding, sentence queue, playback, interrupting) and streaming bubble | to change |

## 5. Functional Domain Changes

**Rules**
- R1. Audio upload: at most 2 MiB (about 60 s of 16 kHz WAV), WAV only. Transcription has a 60-second timeout. The number of recordings that can be transcribed and sent is unlimited.
- R2. Speech: at most 600 characters per request, plain text only. At most 300 requests per user per 10 minutes, with a 30-second timeout.
- R3. Temporary audio files are written to a private temp folder and deleted after use. Audio and transcripts are not logged; the chat message keeps the text, as typing would.
- R4. The partial reply lives only in the server's memory while the run lasts (the scheduler runs inside the web server), and is cleared when the run ends. Only the run's owner sees it.
- R5. Streaming never changes what is applied: the final answer is parsed and checked exactly as in spec 011.

**Resilience:** if whisper or Piper fails, voice mode shows the error and goes back to listening, and text chat keeps working. If streaming fails, the final answer still arrives.

**Data:** none (the partial reply is kept in memory).

## 6. Critical Path

Install tools → `Voice` with stand-in tests → endpoints → streaming in `HostProcess`/`AgentCall` → partial reply in the poll → voice mode and streaming bubble in `chat.js` → real conversation on the host (Mac, then phone through the HTTPS proxy) → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | transcribe/speak with stand-in programs; limits; partial reply extraction from streamed JSON | `test/models/voice_test.rb`, `agent_call_stream_test.rb` | merge | oversize or non-WAV audio refused; no shell; temp files removed |
| Integration | sign-in, invalid audio and owner-only reply polling in `director_chat_test.rb`; 241 sequential recordings with a live rate-limit store and silent audio handling in `voice_test.rb` | Rails integration tests | merge | typed-chat quota applies even with a client-supplied spoken flag; other users never see a partial reply |
| E2E | spoken conversation on the Mac and the iPhone | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** a spoken conversation with the director, hands-free, in a natural voice, all on the host.
- **Measurable effect:** S1–S5 pass.
- **Side effects:** about 1–2 GB of models on the host. Claude's start-up time (a few seconds) is the main delay before the first spoken words.
- **Rollback:** remove the voice button and endpoints; streaming falls back to complete answers.

## 9. Additional Information

- **Rejected alternatives:** the browsers' own speech recognition (sends audio to Apple or Google); system voices (sound robotic, as the owner said); XTTS-v2 (heavier and slower; its licence is non-commercial); cloud TTS and STT (keys, and data leaves the host).
- **Technical debt:** silence detection is energy-based (simple); a noisy room may need headphones.
- **External dependencies:** whisper.cpp (MIT) and a Whisper model (MIT); Piper (GPL, run as a separate program) and a Polish voice (see its model card).
- **Questions:** Q1–Q5 answered by the owner (see Abstract).

## Owner fixes after release (2026-11-20)

- "mówię po polsku, model odpowiada po angielsku; system czyta angielski, jakby to był polski": the director's prompt now names the reply language. Agentaro's own notes ("Planned…", "Question about…") go under the message instead of into it, and "Done…" is an Agentaro notice. Voice mode speaks only the director's own words.
- "dodaj przycisk mówiący, że skończyłem mówić (nie wykrył pauzy)": a **Done** button sends what was said so far. The pause is now detected relative to the speaker's own loudness too, so steady background noise no longer hides it.
- "wybierz może w rozmowie przełącznik języka": an **Auto / PL / EN** switch in the chat header, saved per user. It sets the language for Whisper, the director's replies ("Write your reply in Polish/English", or the latest message's language) and Piper's voice (Polish voice; English voice when installed, `AGENTARO_PIPER_VOICE_EN`; Auto guesses from the text).

- "nie czytaj uśmieszków": emoji, text smileys and Markdown marks are removed from what Piper reads; the chat shows the reply unchanged.

- "dodaj usuwanie szumów, żeby nie było 'wszystkie prawa zastrzeżone'": Whisper runs with `-sns` (suppress non-speech tokens). Sentences it invents on silence or noise (learnt from film subtitles: "Wszystkie prawa zastrzeżone", "Napisy stworzone przez…", "Dziękuję za obejrzenie", "Subskrybuj", "Thanks for watching") are dropped when that is all the sentence says. A whole utterance of just "Koniec", "Dziękuję" or "Thank you" is dropped too. Real sentences that mention these words stay (tests). On the host, plain noise had given "KONIEC".

- "wpisz w prompty systemowe, żeby odpowiadali krócej w rozmowie głosowej": messages sent from voice mode are marked (`chat_messages.spoken`). When the user's latest message was spoken, the prompts ask the director for at most 3 short spoken sentences and the verifier for at most 2, with no lists, Markdown or emoji.
- "zwiększ tempo syntezy mowy, tak x1.5 co najmniej" and "przełącznik prędkości wymowy": a speed switch in the voice panel (1× / 1,25× / 1,5× / 2×, saved per user, default 1,5×). It sets Piper's `--length-scale` to speed^-1.35, because pauses shrink less than sounds. Measured on the host: 1.26×, 1.55× and 1.9×. Whisper still understands the 2× speech.

- Owner fix ("wiadomości czasami się rozsynchronizowują… raz mówisz, że agent przyjmuje zadanie, a za chwilę, że nie wiesz, o co chodzi"; "ma to być turbo odporne i w rozmowie, i w pisaniu tekstem"). The owner's data showed 6 answers in two days that were written for an earlier message and posted after a newer one. Voice mode then spoke them as the answer to the newer message. The fix covers typed and spoken chat (specs 011, 017 and 019):
  - **The director answers the latest state.** When the user writes again while an answer is being written, that answer is not posted. The director answers again with the whole conversation, up to 3 times; after that the newest message gets its own run.
  - **The streamed reply stops.** Once the user writes again, an outdated reply being written is no longer shown or spoken (checked once a second).
  - **One director at a time.** Checking "nothing is running" and creating the run are one locked step, so two messages sent at the same moment can no longer start two directors.
  - **Every answer records its message.** Each director, verifier and Agentaro message stores `reply_to_id`, the user message it was written for.
  - **Voice speaks only answers to the latest words.** Anything older is shown but not spoken, and the chat labels it "Answer to an earlier message".
  - **Bubbles stay in saved order.** They are always in the order the server saved them, including when a reply arrives while the user's own message is still being sent.
  - **The verifier follows the conversation.** A verifier comment on an answer the user has already moved past is not posted, and the director's newer answer is checked instead.
  - Tests: `test/models/chat_order_test.rb`, `director_chat_test.rb`.
- Owner fix ("jakość rozpoznawania mowy jest znowu średnia"). Whisper now gets a hint (`--prompt`) with Agentaro's own words (epik, spec, krok, przestrzeń, weryfikator) and the names of the user's team, up to 400 characters, without control characters. A recording that comes back as only the hint counts as silence. The model is unchanged; the owner chose not to download a bigger one for now. In a check with the installed model, a sentence read by Piper came back as "epik ze specem 23" with the hint and "Epic ze Spec&23" without it. Tests: `test/models/voice_test.rb`.
- Owner fix ("napisałem 'hi there', pojawiło się coś szybko… zanim dokończył, napisałem 'cześć'… nie możesz mi dwa razy podobnego cześć pisać, ani pojawiać i znikać wiadomości"). The earlier ordering fix did not work in production. Background runs work inside Rails' executor, where the query cache is on. While the reply streamed, the check "has the user written again?" ran once a second, and from then on it kept getting its first, cached answer. "cześć" went unseen, the answer to "hi there!" was posted, and a second greeting followed. Tests call the runner without the executor, so they missed it. Runs (director, verifier, epic steps, tasks) now work without the query cache. Test: `chat_order_test.rb` ("with the query cache on"), which failed before the fix.
- Spec 024 (owner: "nie róbmy przerywania"): G6 is replaced. Speaking over the director no longer stops it; the microphone listens after the director has finished, and typed messages wait while the answer is read aloud. The earlier owner fix that dropped and rewrote an answer when the user wrote again is withdrawn: answers are always posted, and messages wait in the chat instead.

## Security analysis (B20), after spec 017

Scope: this spec and specs 001–016.

- **Nothing leaves the host.** whisper.cpp and Piper run locally; no keys and no outside services. The browser sends audio only to Agentaro.
- **Programs.** Both tools run through `HostProcess`: no shell, fixed arguments, the minimal environment, timeouts. The text to speak goes on standard input, never as an argument (test with shell-like text). Recordings must be WAV, at most 2 MB, and are deleted after transcription (tests). Speech requests are at most 600 characters, with control characters removed.
- **Access and limits.** Voice endpoints require sign-in (test). Synthesis has an independent limit of 300 requests per user per 10 minutes. The transcription endpoint saves the server-produced text under the current user after the normal chat checks. Transcription and sending recordings have no count limit. Text submissions, including those with a spoken flag supplied by the client, still go through the typed-chat limit. Only the owner can read a partial reply, which lives in memory during the run.
- **Audit log.** Recordings are not stored in the audit log; it keeps only "[N bytes, audio/wav, not stored]" (spec 003 behaviour, unchanged). Text sent for speech is the director's own reply, already in the chat.
- **Microphone.** Used only after the user presses the voice button, and released when voice mode ends or the page is left.
- **Found on the way.** Text with Polish letters given to a program on standard input could fail with an encoding error; the pipe is now binary (test through the speech path). A variable kept from an earlier loop pass duplicated the end of a streamed reply; fixed and tested.
- **Language switch.** Only auto, pl or en are stored and passed to whisper (test with a forged value); the voice file is chosen from settings, never from the request.
- **Regressions in 001–016.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities.
- **B20 recheck after removal of the recording quota (specs 001–022).** Reviewed the changed route for authentication, CSRF, account scoping, audio handling and the chat validation and queue path. A signed-in user can initiate repeated Whisper work up to the existing per-request timeout and generate successive chat runs. The existing budget gap (spec 011, F14) also applies to voice. The full suite, Brakeman and the refreshed dependency audit passed.
