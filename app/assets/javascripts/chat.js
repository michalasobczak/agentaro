// Agentaro — the director chat (spec 011, owner fixes: "chat niech będzie naprawdę chatem"; floating chat on the
// right on every other page). First-party, no libraries. Messages are sent and received as JSON; the page never
// reloads. Everything is built with textContent (never HTML). Without this script the form posts normally.
// Spec 017: the director's reply streams into a growing bubble, and voice mode talks with the director: the
// browser listens, Whisper on the host transcribes, Piper on the host speaks the answer sentence by sentence.
"use strict";

(() => {
  // Browser storage is a convenience only (open or closed, unsent draft): it may be missing or throw.
  const store = {
    get(area, key) { try { return window[area].getItem(key); } catch (_) { return null; } },
    set(area, key, value) { try { value == null ? window[area].removeItem(key) : window[area].setItem(key, value); } catch (_) { /* ignore */ } }
  };
  const OPEN_KEY = "agentaro.chat.open";
  const SEEN_KEY = "agentaro.chat.seen";
  const DRAFT_KEY = "agentaro.chat.draft";

  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  function bubble(message, extraClass) {
    const row = el("div", `bubble-row from-${message.author}`);
    if (message.id) row.dataset.id = message.id;
    const box = el("div", `bubble${extraClass ? " " + extraClass : ""}`);
    if (message.author !== "user") box.append(el("div", "bubble-name", message.name));
    box.append(el("div", "bubble-text", message.content));
    if (message.actions) box.append(el("div", "bubble-actions", message.actions));
    box.append(el("div", "bubble-time", message.time || ""));
    row.append(box);
    return row;
  }

  // One chat: the full page, or the floating one (dock). `hooks` lets the dock know about replies and visibility.
  function chat(app, hooks = {}) {
    const url = app.dataset.messagesUrl;
    const scroller = app.querySelector(".chat-scroll");
    const stream = app.querySelector(".chat-stream");
    const typing = stream.querySelector("[data-typing]");
    const status = app.querySelector("[data-status]");
    const form = app.querySelector(".chat-composer");
    const input = form.querySelector("textarea");
    const sendButton = form.querySelector(".send");
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const idleStatus = status.textContent === "writing…" ? "your director" : status.textContent;
    const visible = hooks.visible || (() => true);

    let lastId = Number(app.dataset.lastId) || 0;
    let loaded = app.dataset.lazy !== "true";
    let closedAfter = Number(app.dataset.latestReplyId) || 0; // while the floating chat was never opened
    let writing = app.dataset.writing === "true";
    let lastDay = [...stream.querySelectorAll("[data-day]")].pop()?.dataset.day || null;
    let pollTimer = null;
    let sending = false;
    let stopped = false;
    let streamRow = null; // spec 017: the reply being written
    const listeners = { stream: [], message: [], writing: [] };
    const emit = (name, value) => listeners[name].forEach((fn) => fn(value));
    const directorName = app.querySelector(".chat-who strong")?.textContent || "Director";

    // ---------- Scrolling: stay at the bottom unless the user scrolled up to read ----------
    const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 120;
    const toBottom = () => { scroller.scrollTop = scroller.scrollHeight; };

    function addDay(day) {
      if (!day || day === lastDay) return;
      lastDay = day;
      const separator = el("div", "chat-day");
      separator.dataset.day = day;
      separator.append(el("span", null, day));
      stream.insertBefore(separator, typing);
    }

    function append(message) {
      if (message.id && stream.querySelector(`.bubble-row[data-id="${message.id}"]`)) return; // already shown
      stream.querySelector("[data-empty]")?.remove();
      const stick = nearBottom();
      addDay(message.day);
      stream.insertBefore(bubble(message), typing);
      if (message.id > lastId) lastId = message.id;
      if (stick || message.author === "user") toBottom();
      if (message.author !== "user") {
        dropStream();
        hooks.reply?.(message.id);
      }
      emit("message", message);
    }

    // Spec 017, G4: the director's reply so far, in a bubble that grows until the final message replaces it.
    function showStream(text) {
      if (!text) return;
      const stick = nearBottom();
      if (!streamRow) {
        streamRow = bubble({ author: "director", name: directorName, content: "" }, "is-streaming");
        streamRow.querySelector(".bubble-time").remove();
        stream.insertBefore(streamRow, typing);
      }
      streamRow.querySelector(".bubble-text").textContent = text;
      typing.hidden = true;
      if (stick) toBottom();
      emit("stream", text);
    }

    function dropStream() {
      streamRow?.remove();
      streamRow = null;
    }

    function setWriting(value) {
      writing = value;
      const stick = nearBottom();
      typing.hidden = !value || Boolean(streamRow);
      if (!value) dropStream();
      status.textContent = value ? "writing…" : idleStatus;
      if (value) status.dataset.writing = ""; else delete status.dataset.writing;
      hooks.writing?.(value);
      emit("writing", value);
      if (stick) toBottom();
      schedulePoll();
    }

    // ---------- Receiving: quickly while the director is writing, slowly otherwise, rarely while hidden ----------
    async function poll() {
      if (stopped) return;
      if (document.hidden) return schedulePoll();
      try {
        const first = !loaded && visible();
        const after = loaded ? lastId : first ? 0 : closedAfter;
        const response = await fetch(`${url}?after=${after}`, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
        if (response.type === "opaqueredirect" || response.status === 401) { stopped = true; return; } // signed out
        if (response.ok) {
          const data = await response.json();
          if (first) {
            loaded = true;
            if (data.messages.length === 0) stream.insertBefore(el("p", "chat-empty muted", "Say hello to your director."), typing).dataset.empty = "";
          }
          if (loaded) {
            data.messages.forEach(append);
            if (first) toBottom();
          } else {
            data.messages.forEach((m) => { closedAfter = Math.max(closedAfter, m.id); if (m.author !== "user") hooks.reply?.(m.id); });
          }
          if (loaded && data.streaming) showStream(data.streaming);
          if (data.writing !== writing) return setWriting(data.writing);
        }
      } catch (_) { /* offline for a moment: try again later */ }
      schedulePoll();
    }

    function schedulePoll() {
      clearTimeout(pollTimer);
      pollTimer = setTimeout(poll, !visible() ? 20000 : writing ? 500 : 8000); // spec 017: often while the reply streams
    }

    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });

    // ---------- Sending ----------
    function grow() {
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 160) + "px";
      sendButton.disabled = input.value.trim() === "" || sending;
    }

    // Sends the typed text, or `spoken` text from voice mode (the typed draft then stays). Resolves to the saved
    // message, or null when sending failed.
    async function send(spoken) {
      const content = (spoken ?? input.value).trim();
      if (!content || sending) return null;
      sending = true;
      const pending = bubble({ author: "user", content, time: new Date().toTimeString().slice(0, 5) }, "is-pending");
      stream.querySelector("[data-empty]")?.remove();
      stream.insertBefore(pending, typing);
      toBottom();
      if (spoken == null) {
        input.value = "";
        hooks.draft?.(null);
      }
      grow();

      try {
        const body = new FormData();
        body.append("chat_message[content]", content);
        const response = await fetch(url, { method: "POST", body, headers: { Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin" });
        const data = await response.json().catch(() => ({ ok: false, error: "Could not send. Try again." }));
        if (!data.ok) throw new Error(data.error || "Could not send. Try again.");
        pending.remove();
        append(data.message);
        setWriting(data.writing);
        return data.message;
      } catch (error) {
        pending.querySelector(".bubble").classList.replace("is-pending", "is-failed");
        pending.querySelector(".bubble-time").textContent = error.message;
        if (spoken == null) {
          input.value = content; // nothing typed is lost
          hooks.draft?.(content);
        }
        return null;
      } finally {
        sending = false;
        grow();
        if (spoken == null) input.focus();
      }
    }

    form.addEventListener("submit", (event) => { event.preventDefault(); send(); });
    input.addEventListener("input", () => { grow(); hooks.draft?.(input.value); });
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) { event.preventDefault(); send(); }
    });

    toBottom();
    grow();
    schedulePoll();
    const instance = { poll, grow, input, toBottom, send, csrf, get loaded() { return loaded; }, get writing() { return writing; },
                       on: (name, fn) => listeners[name].push(fn) };
    voice(app, instance);
    return instance;
  }

  // ---------- Spec 017: voice mode ----------
  // States: listening → hearing (speech detected) → transcribing → thinking (director writes) → speaking → listening.
  // Silence detection is energy-based: the noise floor is learnt while quiet; speech is a level well above it;
  // about a second of quiet after speech ends the utterance. Speaking over the director interrupts it (G6).
  function voice(app, chat) {
    const start = app.querySelector("[data-voice-start]");
    const panel = app.querySelector("[data-voice-panel]");
    if (!start || !panel || app.dataset.voice !== "ready") return;
    const stateLabel = panel.querySelector("[data-voice-state]");
    const note = panel.querySelector("[data-voice-note]");
    const dots = [...panel.querySelectorAll(".voice-dots i")];
    const doneButton = panel.querySelector("[data-voice-done]");
    const LABELS = { listening: "Listening…", hearing: "Listening…", transcribing: "Writing down…", thinking: "Thinking…", speaking: "Speaking…", error: "Voice problem" };
    const SILENCE_MS = 1000, MIN_SPEECH_MS = 350, MAX_SPEECH_MS = 30000, TARGET_RATE = 16000;

    let state = "off", ctx = null, mic = null, source = null, processor = null;
    let floor = 0.01, loudMs = 0, quietMs = 0, speechMs = 0, chunks = [], preroll = [], peak = 0, heard = [], heardMs = 0;
    let awaitingAfter = null, spoken = 0, finalText = null, generation = 0, playing = null, queue = Promise.resolve(), pending = 0;

    function setState(next, text) {
      state = next;
      panel.dataset.state = next;
      stateLabel.textContent = LABELS[next] || "";
      if (text != null) note.textContent = text;
      if (next !== "hearing") dots.forEach((d) => { d.style.height = ""; });
      doneButton.hidden = next !== "listening" && next !== "hearing";
    }

    async function begin() {
      if (state !== "off" && state !== "error") return; // after an error the button tries again
      try {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        await ctx.resume();
        mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
      } catch (error) {
        panel.hidden = false;
        setState("error", "No microphone: allow it for this page and try again.");
        ctx?.close(); ctx = null; mic = null;
        return;
      }
      source = ctx.createMediaStreamSource(mic);
      processor = ctx.createScriptProcessor(4096, 1, 1);
      processor.onaudioprocess = (event) => onAudio(event.inputBuffer.getChannelData(0));
      source.connect(processor);
      processor.connect(ctx.destination); // needed for the processor to run; it writes silence
      panel.hidden = false;
      start.hidden = true;
      listen("Speak; I send when you pause.");
    }

    function end() {
      generation++;
      playing?.stop?.(); playing = null;
      processor?.disconnect(); source?.disconnect();
      mic?.getTracks().forEach((t) => t.stop());
      ctx?.close();
      ctx = mic = source = processor = null;
      state = "off";
      awaitingAfter = null;
      panel.hidden = true;
      start.hidden = false;
    }

    function listen(text) {
      chunks = []; preroll = []; heard = []; loudMs = quietMs = speechMs = heardMs = peak = 0;
      setState("listening", text ?? "Speak; I send when you pause.");
    }

    function onAudio(samples) {
      let sum = 0;
      for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
      const level = Math.sqrt(sum / samples.length);
      const ms = (samples.length / ctx.sampleRate) * 1000;
      const threshold = Math.max(0.012, floor * 3);

      if (state === "speaking") { // G6: talking over the director stops it
        loudMs = level > Math.max(0.05, floor * 6) ? loudMs + ms : 0;
        if (loudMs > 250) interrupt();
        return;
      }
      if (state !== "listening" && state !== "hearing") return;

      if (level < threshold && state === "listening") floor = floor * 0.95 + level * 0.05;
      const copy = new Float32Array(samples);
      // Everything since listening began (up to 30 s), for the Done button when no speech was detected.
      heard.push(copy); heardMs += ms;
      while (heardMs > MAX_SPEECH_MS && heard.length > 1) { heardMs -= (heard.shift().length / ctx.sampleRate) * 1000; }
      if (state === "listening") {
        preroll.push(copy); if (preroll.length > 3) preroll.shift();
        loudMs = level > threshold ? loudMs + ms : 0;
        if (loudMs >= 150) { setState("hearing"); chunks = preroll.slice(); speechMs = loudMs; quietMs = 0; peak = level; }
        return;
      }
      chunks.push(copy);
      speechMs += ms;
      peak = Math.max(peak * 0.995, level);
      // Quiet is relative to the speaker's own level too, so steady background noise does not hide the pause
      // (owner: "nie wykrył pauzy").
      quietMs = level > Math.max(threshold, peak * 0.22) ? 0 : quietMs + ms;
      dots.forEach((d, i) => { d.style.height = `${Math.min(2.2, 0.55 + level * (30 + i * 6))}rem`; });
      if (quietMs >= SILENCE_MS || speechMs >= MAX_SPEECH_MS) {
        if (speechMs - quietMs < MIN_SPEECH_MS) return listen();
        transcribe(chunks.slice());
      }
    }

    // Owner fix after spec 017: "I am done speaking" — send now, without waiting for the pause.
    function done() {
      if (state === "hearing" && speechMs >= MIN_SPEECH_MS) return transcribe(chunks.slice());
      if (state === "listening" && heardMs >= MIN_SPEECH_MS) return transcribe(heard.slice());
    }

    function interrupt() {
      generation++;
      playing?.stop?.(); playing = null;
      pending = 0;
      finalText = null; awaitingAfter = null;
      listen("Go on — I am listening.");
      setState("hearing");
    }

    // 16 kHz mono 16-bit WAV from the recorded samples.
    function wav(parts, rate) {
      const total = parts.reduce((n, p) => n + p.length, 0);
      const ratio = rate / TARGET_RATE;
      const length = Math.floor(total / ratio);
      const data = new DataView(new ArrayBuffer(44 + length * 2));
      const text = (offset, value) => [...value].forEach((c, i) => data.setUint8(offset + i, c.charCodeAt(0)));
      text(0, "RIFF"); data.setUint32(4, 36 + length * 2, true); text(8, "WAVE"); text(12, "fmt ");
      data.setUint32(16, 16, true); data.setUint16(20, 1, true); data.setUint16(22, 1, true);
      data.setUint32(24, TARGET_RATE, true); data.setUint32(28, TARGET_RATE * 2, true); data.setUint16(32, 2, true); data.setUint16(34, 16, true);
      text(36, "data"); data.setUint32(40, length * 2, true);
      const all = new Float32Array(total);
      let offset = 0;
      parts.forEach((p) => { all.set(p, offset); offset += p.length; });
      for (let i = 0; i < length; i++) {
        const from = Math.floor(i * ratio), to = Math.min(total, Math.floor((i + 1) * ratio));
        let acc = 0;
        for (let j = from; j < to; j++) acc += all[j];
        const v = Math.max(-1, Math.min(1, acc / Math.max(1, to - from)));
        data.setInt16(44 + i * 2, v < 0 ? v * 0x8000 : v * 0x7fff, true);
      }
      return new Blob([ data.buffer ], { type: "audio/wav" });
    }

    async function transcribe(parts) {
      setState("transcribing", "…");
      const mine = generation;
      try {
        const response = await fetch(app.dataset.voiceTranscribeUrl, { method: "POST", body: wav(parts, ctx.sampleRate),
          headers: { "Content-Type": "audio/wav", Accept: "application/json", "X-CSRF-Token": chat.csrf }, credentials: "same-origin" });
        const data = await response.json().catch(() => ({ error: "Could not understand the recording." }));
        if (mine !== generation || state === "off") return;
        if (!response.ok) throw new Error(data.error || "Could not understand the recording.");
        if (!data.text) return listen("I heard nothing — speak again.");
        setState("thinking", `You: ${data.text}`);
        const message = await chat.send(data.text);
        if (!message) throw new Error("Could not send. Check the chat.");
        awaitingAfter = message.id; spoken = 0; finalText = null;
      } catch (error) {
        if (state !== "off") { setState("error", error.message); setTimeout(() => { if (state === "error") listen(); }, 2500); }
      }
    }

    // ---- Speaking the reply: complete sentences go to Piper in order, while the rest is still streaming ----
    chat.on("stream", (text) => { if (awaitingAfter != null && state !== "off") speakUpTo(text, false); });
    chat.on("message", (message) => {
      if (awaitingAfter == null || state === "off" || message.author === "user" || message.id <= awaitingAfter) return;
      awaitingAfter = null;
      if (message.author !== "director") return listen(); // Agentaro's own notices are shown, not spoken
      finalText = message.content;
      speakUpTo(message.content, true);
    });
    chat.on("writing", (value) => { if (!value && state === "thinking" && awaitingAfter != null && finalText == null) listen(); });

    function speakUpTo(text, final) {
      const rest = text.slice(spoken);
      let cut = final ? rest.length : -1;
      if (!final) {
        const re = /[.!?…:;](?=\s)|\n/g;
        let m;
        while ((m = re.exec(rest))) cut = m.index + 1;
      }
      if (cut <= 0) { if (final) finishWhenDone(); return; }
      const piece = rest.slice(0, cut).trim();
      spoken += cut;
      sentences(piece).forEach(say);
      if (final) finishWhenDone();
    }

    // Piper takes at most 600 characters; long sentences are split at commas or spaces.
    function sentences(text) {
      const out = [];
      text.split(/(?<=[.!?…:;])\s+|\n+/).map((t) => t.trim()).filter(Boolean).forEach((t) => {
        while (t.length > 500) {
          const at = Math.max(t.lastIndexOf(", ", 500), t.lastIndexOf(" ", 500), 300);
          out.push(t.slice(0, at)); t = t.slice(at).trim();
        }
        out.push(t);
      });
      return out;
    }

    function say(text) {
      const mine = generation;
      pending++;
      const audio = fetch(app.dataset.voiceSpeakUrl, { method: "POST", body: JSON.stringify({ text }),
        headers: { "Content-Type": "application/json", "X-CSRF-Token": chat.csrf }, credentials: "same-origin" })
        .then((r) => (r.ok ? r.arrayBuffer() : null)).then((b) => (b && ctx ? ctx.decodeAudioData(b) : null)).catch(() => null);
      queue = queue.then(async () => {
        const buffer = await audio;
        if (mine !== generation || !ctx || !buffer) { pending--; return; }
        setState("speaking");
        await new Promise((resolve) => {
          const node = ctx.createBufferSource();
          node.buffer = buffer; node.connect(ctx.destination);
          node.onended = resolve;
          playing = node;
          node.start();
        });
        playing = null;
        pending--;
        if (mine === generation && pending === 0 && finalText != null) listen();
      });
    }

    function finishWhenDone() {
      queue = queue.then(() => { if (pending === 0 && state !== "off" && state !== "hearing") listen(); });
    }

    start.addEventListener("click", begin);
    panel.querySelector("[data-voice-stop]").addEventListener("click", end);
    panel.querySelector("[data-voice-done]").addEventListener("click", done);
    window.addEventListener("pagehide", end);
  }

  // ---------- The full-page chat (Director page) ----------
  const page = document.querySelector(".chat-app:not(.is-dock)");
  if (page) {
    // Whatever the Director page shows counts as read for the floating chat.
    const markRead = (id) => { if (id > (Number(store.get("localStorage", SEEN_KEY)) || 0)) store.set("localStorage", SEEN_KEY, String(id)); };
    page.querySelectorAll(".bubble-row:not(.from-user)[data-id]").forEach((row) => markRead(Number(row.dataset.id)));
    chat(page, { reply: markRead });
  }

  // ---------- The floating chat on every other page ----------
  const dock = document.querySelector("[data-chat-dock]");
  if (!dock) return;
  const app = dock.querySelector(".chat-app");
  const launcher = dock.querySelector("[data-dock-open]");
  const unread = dock.querySelector("[data-unread]");
  const seen = () => Number(store.get("localStorage", SEEN_KEY)) || 0;
  const isOpen = () => dock.classList.contains("is-open");
  const markSeen = (id) => { if (id > seen()) store.set("localStorage", SEEN_KEY, String(id)); };
  let newest = Number(app.dataset.latestReplyId) || 0;

  const instance = chat(app, {
    visible: isOpen,
    reply: (id) => { newest = Math.max(newest, id); if (isOpen()) markSeen(id); else unread.hidden = newest <= seen(); },
    writing: (value) => launcher.classList.toggle("is-writing", value),
    draft: (text) => store.set("sessionStorage", DRAFT_KEY, text || null)
  });
  launcher.classList.toggle("is-writing", app.dataset.writing === "true");

  const draft = store.get("sessionStorage", DRAFT_KEY);
  if (draft) { instance.input.value = draft; instance.grow(); }

  function setOpen(open, focus) {
    dock.classList.toggle("is-open", open);
    launcher.setAttribute("aria-expanded", String(open));
    store.set("localStorage", OPEN_KEY, open ? "1" : null);
    if (open) {
      markSeen(newest);
      unread.hidden = true;
      instance.poll(); // loads the history the first time, then keeps it current
      instance.toBottom();
      if (focus) instance.input.focus();
    } else {
      unread.hidden = newest <= seen();
      if (focus) launcher.focus();
    }
  }

  launcher.addEventListener("click", () => setOpen(true, true));
  dock.querySelector("[data-dock-close]").addEventListener("click", () => setOpen(false, true));
  dock.addEventListener("keydown", (event) => { if (event.key === "Escape" && isOpen()) setOpen(false, true); });
  setOpen(store.get("localStorage", OPEN_KEY) === "1", false);
})();
