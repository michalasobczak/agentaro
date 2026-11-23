// Spec 046, G4 and spec 045, G4: the short acknowledgement and the spoken epic summary, against the real voice().
async function talked(natural) {
  const v = buildChat();
  if (natural) Object.assign(v.app.dataset, { conversation: "natural", acknowledgements: "Już sprawdzam.|Chwilka." });
  await v.start.click();
  await settle();
  v.feed(0, 300); v.feed(0.5, 1000); v.feed(0, 3200);
  await settle();
  assertEqual("thinking", v.state, "the owner's words went to the director");
  return v;
}

function speaks(v) { return world.fetches.filter((f) => f.url === "/director/voice/speak").map((f) => JSON.parse(f.options.body).text); }
async function runTimers() { const due = world.timers.splice(0); due.forEach((fn) => fn()); await settle(); }

// S3: 2 s without a reply → one acknowledgement; the state goes back to waiting for the answer.
scenario("ack", async () => {
  const v = await talked(true);
  await runTimers();
  const said = speaks(v);
  assertEqual(1, said.length, "one acknowledgement");
  assert([ "Już sprawdzam.", "Chwilka." ].includes(said[0]), "a phrase from the list");
  assertEqual("speaking", v.state, "it is being said");
  world.played.forEach((node) => node.onended?.()); // the phrase ends
  await settle();
  assertEqual("thinking", v.state, "still waiting for the answer after it");
  await runTimers();
  assertEqual(1, speaks(v).length, "at most one per message");
});

// S3: a reply that starts sooner gets no acknowledgement.
scenario("no-ack-when-replying", async () => {
  const v = await talked(true);
  v.chat.emit("stream", { text: "Dobrze. Już", replyTo: null });
  await settle();
  await runTimers();
  assertEqual([ "Dobrze." ].join(), speaks(v).join(), "only the reply is spoken");
});

// Negative: the Zwykła mode has no acknowledgement.
scenario("no-ack-plain", async () => {
  const v = await talked(false);
  await runTimers();
  assertEqual(0, speaks(v).length, "nothing is said");
});

// Spec 045, G4: a summary that arrives while the voice listens is read aloud; other director messages are not.
scenario("summary", async () => {
  const v = buildChat();
  await v.start.click();
  await settle();
  v.chat.emit("message", { id: 500, author: "director", content: "Lista gotowa. Nic nie czeka.", kind: null });
  await settle();
  assertEqual(0, speaks(v).length, "a message that is not a summary is not read while listening");
  v.chat.emit("message", { id: 501, author: "director", content: "Lista gotowa. Nic nie czeka.", kind: "summary" });
  await settle();
  assertEqual("Lista gotowa.|Nic nie czeka.", speaks(v).join("|"), "the summary is read, sentence by sentence");
});

(async () => {
  const name = globalThis.arguments[0];
  try {
    if (!scenarios[name]) throw new Error(`unknown scenario ${name}`);
    await scenarios[name]();
    print("ok");
  } catch (error) {
    print(`not ok: ${error.message}`);
  }
})();
