// Spec 035: behaviour of the microphone mute toggle, run against the real voice() from chat.js.
// Levels: 0.31 is speech before or during the mute, 0.5 is speech after unmuting, 0 is a pause.
const BEFORE = 0.31, AFTER = 0.5;

async function started() {
  const v = buildChat();
  await v.start.click();
  await settle();
  assertEqual("listening", v.state, "voice mode starts listening");
  assertEqual("false", v.mute.getAttribute("aria-pressed"), "starts unmuted");
  return v;
}

function assertMuted(v) {
  assertEqual("true", v.mute.getAttribute("aria-pressed"), "aria-pressed while muted");
  assert(v.mute.classList.contains("is-on"), "the toggle is filled while muted");
  assertEqual("Muted", v.muteLabel.textContent, "visible label while muted");
  assertEqual("true", v.panel.dataset.muted, "the panel is marked muted");
  assertEqual("Microphone muted — nothing you say is sent.", v.note.textContent, "note while muted");
  assert(v.doneButton.hidden, "Done is hidden while muted");
  assert(world.tracks.filter((t) => !t.stopped).every((t) => t.enabled === false), "microphone tracks are disabled");
}

function assertUnmuted(v) {
  assertEqual("false", v.mute.getAttribute("aria-pressed"), "aria-pressed after unmuting");
  assert(!v.mute.classList.contains("is-on"), "the toggle is not filled");
  assertEqual("Mute", v.muteLabel.textContent, "visible label when not muted");
  assertEqual("false", v.panel.dataset.muted, "the panel is not marked muted");
  assert(world.tracks.filter((t) => !t.stopped).every((t) => t.enabled === true), "microphone tracks are enabled");
}

// S1: muted for 60 s of speech with pauses, Done pressed too: no request, no message.
scenario("S1", async () => {
  const v = await started();
  await v.mute.click();
  assertMuted(v);
  assertEqual("Microphone muted", v.stateLabel.textContent, "state label while muted");
  assertEqual("Microphone muted", v.status.textContent, "announcement for screen readers");
  // The early return in onAudio alone must hold, even if a browser ignored track.enabled and sent real sound.
  for (let i = 0; i < 13; i++) { v.feed(BEFORE, 1500); v.feed(0, 3100); } // pauses that would send
  v.feed(BEFORE, 56000);                                                  // past the 55 s limit
  await v.doneButton.click();
  await settle();
  assertEqual(0, v.transcribes().length, "requests to /director/voice/transcribe while muted");
  assertEqual(0, world.received.length, "messages reaching the director while muted");
  assertEqual("listening", v.state, "still waiting, shown as muted");
});

// S2 + S3: mute in the middle of an utterance; it is thrown away; after unmuting the next utterance is sent
// alone, answered and spoken, and listening goes on without a new microphone prompt.
scenario("S2", async () => {
  const v = await started();
  v.feed(BEFORE, 500);
  assertEqual("hearing", v.state, "speech detected before the mute");
  await v.mute.click();
  assertMuted(v);
  assertEqual("listening", v.state, "hearing becomes listening on mute");
  v.feed(BEFORE, 2000); // still speaking while muted
  v.feed(0, 3500);      // the pause that would have sent the utterance
  await v.doneButton.click();
  await settle();
  assertEqual(0, v.transcribes().length, "the utterance in progress is discarded");

  await v.mute.click();
  assertUnmuted(v);
  assertEqual("Microphone on", v.status.textContent, "announcement after unmuting");
  assertEqual("Listening…", v.stateLabel.textContent, "state label after unmuting");
  assertEqual("Speak; I send when you pause.", v.note.textContent, "note after unmuting");
  assert(!v.doneButton.hidden, "Done is back after unmuting");

  v.feed(0, 300);
  v.feed(AFTER, 1000);
  v.feed(0, 3200);
  await settle();
  assertEqual(1, v.transcribes().length, "the next utterance is sent once");
  const sent = v.samples(v.transcribes()[0]);
  assert(sent.has(level(AFTER)), "the utterance after unmuting is in the recording");
  assert(!sent.has(level(BEFORE)), "nothing spoken before or during the mute is in the recording");
  assertEqual(1, world.received.length, "the message reaches the director");
  assertEqual("thinking", v.state, "waiting for the director");

  // The director answers; the answer is spoken, then listening goes on and the next utterance is sent too.
  const asked = world.received[0].message.id;
  v.chat.emit("message", { id: asked + 1, author: "director", content: "Dobrze." });
  await settle();
  assertEqual(1, world.played.length, "the answer is played");
  assertEqual("speaking", v.state, "speaking the answer");
  world.played[0].onended();
  await settle();
  assertEqual("listening", v.state, "listening again after the answer");
  v.feed(AFTER, 1000);
  v.feed(0, 3200);
  await settle();
  assertEqual(2, v.transcribes().length, "the conversation goes on");
  assertEqual(1, world.getUserMediaCalls, "no new microphone request");
  assertEqual(1, world.contexts, "the same AudioContext");
});

// S5 + R8: muting while the director speaks lets the answer play to the end; after it the panel stays muted
// and nothing is recorded.
scenario("S5", async () => {
  const v = await started();
  v.feed(AFTER, 1000);
  v.feed(0, 3200);
  await settle();
  const asked = world.received[0].message.id;
  v.chat.emit("message", { id: asked + 1, author: "director", content: "Pierwsze zdanie. Drugie zdanie." });
  await settle();
  assertEqual("speaking", v.state, "the director speaks");
  await v.mute.click();
  assertMuted(v);
  assertEqual("Speaking…", v.stateLabel.textContent, "the state label stays while speaking");
  assert(!world.played[0].stopped, "the director's voice is not stopped by muting");
  world.played[0].onended();
  await settle();
  assertEqual(2, world.played.length, "the second sentence is still spoken");
  world.played[1].onended();
  await settle();
  assertEqual("listening", v.state, "back to waiting after the answer");
  assertEqual("Microphone muted", v.stateLabel.textContent, "but still muted");
  v.feed(BEFORE, 1000);
  v.feed(0, 3200);
  await settle();
  assertEqual(1, v.transcribes().length, "nothing more is sent while muted");
});

// R9: ending voice mode clears the mute; the next session starts with the microphone on.
scenario("R9", async () => {
  const v = await started();
  v.feed(BEFORE, 500);
  await v.mute.click();
  await v.stop.click();
  assert(v.panel.hidden, "voice mode ended");
  assertEqual("false", v.mute.getAttribute("aria-pressed"), "the toggle is reset");
  assertEqual("", v.status.textContent, "no announcement left over");
  await v.start.click();
  await settle();
  assertUnmuted(v);
  assertEqual("listening", v.state, "the new session listens");
  v.feed(0, 300);
  v.feed(AFTER, 1000);
  v.feed(0, 3200);
  await settle();
  assertEqual(1, v.transcribes().length, "the new session sends speech");
  assert(!v.samples(v.transcribes()[0]).has(level(BEFORE)), "nothing from the previous session");
});

// Owner change (2026-11-23): a breath of two seconds does not end the utterance; three seconds of quiet do.
scenario("breath", async () => {
  const v = await started();
  v.feed(BEFORE, 2000);
  v.feed(0, 2500);   // taking a breath
  await settle();
  assertEqual(0, v.transcribes().length, "a 2.5 s pause does not send");
  assertEqual("hearing", v.state, "still hearing during the breath");
  v.feed(AFTER, 1500);
  v.feed(0, 3200);
  await settle();
  assertEqual(1, v.transcribes().length, "the pause of 3 s sends one utterance");
  const sent = v.samples(v.transcribes()[0]);
  assert(sent.has(level(BEFORE)) && sent.has(level(AFTER)), "both parts are in one recording");
});

// The toggle does nothing before voice mode starts (state off).
scenario("off", async () => {
  const v = buildChat();
  await v.mute.click();
  assertEqual("false", v.mute.getAttribute("aria-pressed"), "no mute while voice mode is off");
  assertEqual("", v.status.textContent, "no announcement while voice mode is off");
});

(async () => {
  const name = globalThis.arguments[0]; // jsc passes the arguments after "--"
  try {
    if (!scenarios[name]) throw new Error(`unknown scenario ${name}`);
    await scenarios[name]();
    print("ok");
  } catch (error) {
    print(`not ok: ${error.message}`);
  }
})();
