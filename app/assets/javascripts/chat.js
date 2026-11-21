// Agentaro — the director chat (spec 011, owner fixes: "chat niech będzie naprawdę chatem"; floating chat on the
// right on every other page). First-party, no libraries. Messages are sent and received as JSON; the page never
// reloads. Everything is built with textContent (never HTML). Without this script the form posts normally.
// Spec 017: the director's reply streams into a growing bubble, and voice mode talks with the director: the
// browser listens, Whisper on the host transcribes, Piper on the host speaks the answer sentence by sentence.
"use strict";

(() => {
  // Owner fix ("poprosiłem directora o status i pisał dwie wiadomości jednocześnie"): several copies of the chat were
  // alive at once, two of them on the same element, each drawing its own reply. Never run this file twice in a tab;
  // one chat per element (a new one ends the old); a chat whose element left the page ends itself.
  if (window.agentaroChats) return;
  window.agentaroChats = new Set(); // the live chats, for checks in the browser
  // Browser storage is a convenience only (open or closed, unsent draft): it may be missing or throw.
  const store = {
    get(area, key) { try { return window[area].getItem(key); } catch (_) { return null; } },
    set(area, key, value) { try { value == null ? window[area].removeItem(key) : window[area].setItem(key, value); } catch (_) { /* ignore */ } }
  };
  const OPEN_KEY = "agentaro.chat.open";
  const SEEN_KEY = "agentaro.chat.seen";
  const DRAFT_KEY = "agentaro.chat.draft";
  const MAX_KEY = "agentaro.chat.max"; // owner fix: the floating chat maximized

  // Spec 026: while the tab is in the background, a new answer makes its title blink until the user comes back.
  const titleBlink = (() => {
    let timer = null, base = null;
    const stop = () => { if (!timer) return; clearInterval(timer); timer = null; document.title = base; };
    document.addEventListener("visibilitychange", () => { if (!document.hidden) stop(); });
    return (who) => {
      if (timer || !document.hidden) return;
      base = document.title;
      let on = false;
      timer = setInterval(() => { on = !on; document.title = on ? `(1) New message from ${who}` : base; }, 1000);
    };
  })();

  // Spec 029: the chat background pattern. One handler per tab for every selector (full chat and floating chat).
  // The body attribute is the confirmed choice; a change is saved on the account and applied only when the server
  // confirms it; a failure puts the selectors back and says so. One save at a time.
  (() => {
    let saving = null; // the value being saved
    const selects = () => document.querySelectorAll("[data-chat-background-select]");
    const confirmed = () => document.body.dataset.chatBackground || "solid";
    const announce = (text) => document.querySelectorAll("[data-chat-background-status]").forEach((s) => { s.textContent = text; });
    const show = (value) => selects().forEach((s) => { if (s.value !== value) s.value = value; });
    const sync = () => {
      document.querySelectorAll("[data-chat-background-apply]").forEach((b) => { b.hidden = true; });
      show(saving || confirmed());
    };

    async function save(select) {
      const value = select.value;
      if (saving) { select.value = saving; return; }
      if (value === confirmed()) return;
      saving = value;
      show(value);
      announce("");
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
      const response = await fetch(select.form.action, { method: "PATCH", body: JSON.stringify({ chat_background: value }),
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin" }).catch(() => null);
      const data = response?.ok ? await response.json().catch(() => null) : null;
      saving = null;
      if (data?.chat_background) {
        document.body.dataset.chatBackground = data.chat_background;
        window.Turbo?.cache?.clear?.(); // pages restored from the cache would show the old choice
        announce("Chat background saved.");
      } else {
        announce("The chat background could not be saved. Try again.");
      }
      show(confirmed());
    }

    document.addEventListener("change", (event) => {
      if (event.target.matches?.("[data-chat-background-select]")) save(event.target);
    });
    document.addEventListener("submit", (event) => {
      if (!event.target.matches?.("[data-chat-background-form]")) return;
      event.preventDefault();
      save(event.target.querySelector("[data-chat-background-select]"));
    }, true);
    window.agentaroOnPage(sync); // the floating chat stays across visits; its selector follows the new page
  })();

  // Owner fix ("model zwraca formatowanie **xxx**, ale czat tego nie formatuje"): the same small part of Markdown as
  // ChatFormatHelper — **bold**, *italic*, `code`, "- " and "1. " lists, "# " headings — built with textContent only.
  const LIST_ITEM = /^\s*(?:([-*•])|(\d+)[.)])\s+(.*)$/;
  const HEADING = /^\s{0,3}#{1,6}\s+(.*)$/;
  const INLINE = /\*\*(.+?)\*\*|__(.+?)__|`([^`\n]+)`|(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])/;
  function inline(text) {
    const out = [];
    let rest = text, m;
    while ((m = INLINE.exec(rest))) {
      out.push(document.createTextNode(rest.slice(0, m.index)));
      const node = document.createElement(m[1] || m[2] ? "strong" : m[3] ? "code" : "em");
      node.textContent = m[1] || m[2] || m[3] || m[4];
      out.push(node);
      rest = rest.slice(m.index + m[0].length);
    }
    out.push(document.createTextNode(rest));
    return out;
  }
  function chatFormat(text) {
    const blocks = [];
    String(text || "").split("\n").forEach((line) => {
      const last = blocks[blocks.length - 1];
      let m;
      if ((m = LIST_ITEM.exec(line))) {
        const kind = m[1] ? "ul" : "ol";
        if (last && last.kind === kind) last.items.push(m[3]); else blocks.push({ kind, items: [ m[3] ] });
      } else if ((m = HEADING.exec(line))) blocks.push({ kind: "heading", text: m[1] });
      else if (line.trim() === "") blocks.push({ kind: "gap" });
      else if (last && last.kind === "p") last.text += `\n${line}`;
      else blocks.push({ kind: "p", text: line });
    });
    return blocks.filter((b) => b.kind !== "gap").map((b) => {
      if (b.kind === "ul" || b.kind === "ol") {
        const list = document.createElement(b.kind);
        b.items.forEach((item) => { const li = document.createElement("li"); li.append(...inline(item)); list.append(li); });
        return list;
      }
      const div = document.createElement("div");
      div.className = b.kind === "heading" ? "md-h" : "md-p";
      div.append(...inline(b.text));
      return div;
    });
  }

  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  // Spec 023, R10/R12: the author's icon, drawn from the same JSON fields the server uses (chat_message_json).
  function agentIcon(message) {
    const icon = el("span", `agent-icon is-bubble ${message.icon_kind ? "is-" + message.icon_kind : message.icon_tone || ""}`.trim(), message.icon_letter || "?");
    icon.setAttribute("aria-hidden", "true");
    if (message.icon_agent) {
      icon.dataset.agentIcon = message.icon_agent;
      const dot = el("span", "status-dot is-free");
      dot.hidden = true; // until the team status says otherwise
      icon.append(dot);
    }
    return icon;
  }

  function bubble(message, extraClass) {
    const row = el("div", `bubble-row from-${message.author}`);
    if (message.id) row.dataset.id = message.id;
    if (message.author !== "user" && message.icon_kind) row.append(agentIcon(message));
    const box = el("div", `bubble${extraClass ? " " + extraClass : ""}`);
    if (message.author !== "user") box.append(el("div", "bubble-name", message.name));
    const text = el("div", "bubble-text");
    text.append(...chatFormat(message.content));
    box.append(text);
    if (message.actions) box.append(el("div", "bubble-actions", message.actions));
    if (message.earlier) box.append(el("div", "bubble-earlier", "Answer to an earlier message")); // owner fix: never mistaken for an answer to the latest
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
    const life = new AbortController(); // spec 020: ended by destroy() when a Turbo visit replaces this chat
    const listeners = { stream: [], message: [], writing: [] };
    const emit = (name, value) => listeners[name].forEach((fn) => fn(value));
    const directorName = app.querySelector(".chat-who strong")?.textContent || "Director";
    const directorAvatar = app.querySelector(".chat-avatar");
    const directorIcon = { icon_kind: "director", icon_letter: directorAvatar?.firstChild?.textContent || "?", icon_agent: directorAvatar?.dataset.agentIcon };
    // Spec 023: the team status (G4, R11) — the stamp the page has, and the latest statuses for new icons.
    let teamStamp = ""; // the first poll fetches the statuses once (for icons of new messages), then only changes
    let team = null;
    const teamToggle = app.querySelector("[data-team-toggle]");
    teamToggle?.addEventListener("click", () => {
      const open = teamToggle.getAttribute("aria-expanded") !== "true";
      teamToggle.setAttribute("aria-expanded", String(open));
      teamToggle.closest("[data-team-strip]").classList.toggle("is-open", open);
    }, { signal: life.signal });
    const showTeam = (root) => { if (team) window.agentaroTeamStatus?.apply(team, root); };

    // ---------- Scrolling: stay at the bottom unless the user scrolled up to read ----------
    // Owner fix ("auto scroll w panelu bocznym nie działa skutecznie"): "stuck" remembers whether the reader is at the
    // bottom (it changes only when they scroll), and any change of size — a growing streamed reply, the voice panel,
    // the floating panel opening, the phone keyboard — keeps a stuck chat at the bottom.
    const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 80;
    let stuck = true;
    const toBottom = () => {
      stuck = true;
      scroller.scrollTop = scroller.scrollHeight;
      requestAnimationFrame(() => { if (stuck) scroller.scrollTop = scroller.scrollHeight; }); // after layout settles
    };
    scroller.addEventListener("scroll", () => { stuck = nearBottom(); }, { passive: true, signal: life.signal });
    if (window.ResizeObserver) {
      const keep = new ResizeObserver(() => { if (stuck) scroller.scrollTop = scroller.scrollHeight; });
      keep.observe(stream);
      keep.observe(scroller);
    }

    // Owner fix (a date shown twice): compared with the last separator in the chat itself, not a remembered value.
    function addDay(day) {
      const shown = [...stream.querySelectorAll("[data-day]")].pop()?.dataset.day || lastDay;
      if (!day || day === shown) return;
      lastDay = day;
      const separator = el("div", "chat-day");
      separator.dataset.day = day;
      separator.append(el("span", null, day));
      stream.insertBefore(separator, typing);
    }

    // Owner fix ("wiadomości się rozsynchronizowują"): bubbles always stand in the order the server saved them, even
    // when a reply arrives while the user's own message is still on its way; an answer written for an earlier message
    // says so.
    const latestUser = () => Math.max(0, ...[...stream.querySelectorAll(".bubble-row.from-user[data-id]")].map((r) => Number(r.dataset.id)));

    function append(message) {
      if (message.id && stream.querySelector(`.bubble-row[data-id="${message.id}"]`)) return; // already shown
      stream.querySelector("[data-empty]")?.remove();
      if (message.author !== "user" && message.reply_to && message.reply_to < latestUser()) message = { ...message, earlier: true };
      const later = message.id && [...stream.querySelectorAll(".bubble-row[data-id]")].find((r) => Number(r.dataset.id) > message.id);
      const row = bubble(message);
      if (later) {
        later.before(row);
      } else {
        addDay(message.day);
        stream.insertBefore(row, typing);
      }
      showTeam(row);
      if (message.id > lastId) lastId = message.id;
      if (stuck || message.author === "user") toBottom();
      if (message.author !== "user") {
        dropStream();
        hooks.reply?.(message.id);
      }
      emit("message", message);
    }

    // Spec 017, G4: the director's reply so far, in a bubble that grows until the final message replaces it.
    function showStream(text, replyTo) {
      if (!text) return;
      if (replyTo && replyTo < latestUser()) return dropStream(); // owner fix: written before the user's latest words
      if (!streamRow) {
        streamRow = bubble({ author: "director", name: directorName, content: "", ...directorIcon }, "is-streaming");
        streamRow.querySelector(".bubble-time").remove();
        showTeam(streamRow);
        stream.insertBefore(streamRow, typing);
      }
      streamRow.querySelector(".bubble-text").replaceChildren(...chatFormat(text));
      typing.hidden = true;
      if (stuck) toBottom();
      emit("stream", { text, replyTo });
    }

    function dropStream() {
      streamRow?.remove();
      streamRow = null;
    }

    function setWriting(value) {
      writing = value;
      typing.hidden = !value || Boolean(streamRow);
      if (!value) dropStream();
      status.textContent = value ? "writing…" : idleStatus;
      if (value) status.dataset.writing = ""; else delete status.dataset.writing;
      hooks.writing?.(value);
      emit("writing", value);
      if (stuck) toBottom();
      schedulePoll();
      if (!value) flush();
    }

    // ---------- Receiving: quickly while the director is writing, slowly otherwise, rarely while hidden ----------
    let detached = 0;
    async function poll() {
      if (stopped) return;
      // Turbo moves the floating chat between pages, so a moment off the page is normal; three polls are not.
      if (!app.isConnected) { if (++detached >= 3) return instance.destroy(); return schedulePoll(); }
      detached = 0;
      if (document.hidden) return schedulePoll();
      try {
        const first = !loaded && visible();
        const after = loaded ? lastId : first ? 0 : closedAfter;
        const response = await fetch(`${url}?after=${after}&team_stamp=${encodeURIComponent(teamStamp)}`, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
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
          if (data.team) { team = data.team; teamStamp = data.team_stamp || ""; }
          showTeam(app); // spec 023, R12: dots and the strip in place; also keeps "for N min" fresh
          if (loaded && data.streaming) showStream(data.streaming, data.streaming_reply_to);
          if (data.writing !== writing) return setWriting(data.writing);
          flush(); // messages that waited across a reload go once the director is free
        }
      } catch (_) { /* offline for a moment: try again later */ }
      schedulePoll();
    }

    function schedulePoll() {
      clearTimeout(pollTimer);
      pollTimer = setTimeout(poll, !visible() ? 20000 : writing ? 500 : 8000); // spec 017: often while the reply streams
    }

    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); }, { signal: life.signal });

    // ---------- Sending ----------
    function grow() {
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 160) + "px";
      sendButton.disabled = input.value.trim() === "";
    }

    function receive(data) {
      (data.messages || [ data.message ]).forEach(append);
      setWriting(data.writing);
    }

    // Owner fix ("moja wypowiedź czeka… do momentu, aż mówca skończy… nie róbmy przerywania"): while the director
    // (or the verifier) writes, or voice mode reads the answer aloud, what the user sends waits in the chat, below
    // the answer, marked "Waiting…"; when they have finished, everything waiting goes at once and gets one answer.
    // It is kept in this tab's storage, so a reload does not lose it.
    const WAIT_KEY = `agentaro.chat.waiting.${app.closest("[data-chat-dock]") ? "dock" : "page"}`;
    const MAX_WAITING = 10;
    let held = false; // voice mode is speaking
    const waiting = [];
    const busy = () => writing || held || sending;
    const saveWaiting = () => store.set("sessionStorage", WAIT_KEY, waiting.length ? JSON.stringify(waiting.map((w) => w.content)) : null);

    function waitRow(content, state = "is-waiting") {
      const row = bubble({ author: "user", content, time: "" }, state);
      row.querySelector(".bubble-time").textContent = "Waiting for the director to finish…";
      stream.querySelector("[data-empty]")?.remove();
      stream.append(row); // below the reply being written and the typing dots
      return row;
    }

    function hold(value) {
      held = value;
      if (!value) flush();
    }

    function flush() {
      if (busy() || waiting.length === 0 || stopped) return;
      const batch = waiting.splice(0, MAX_WAITING);
      saveWaiting();
      post(batch);
    }

    function send() {
      const content = input.value.trim();
      if (!content) return;
      input.value = "";
      hooks.draft?.(null);
      grow();
      const item = { content, row: waitRow(content) };
      waiting.push(item);
      saveWaiting();
      toBottom();
      flush(); // at once when nobody is speaking
      input.focus();
    }

    async function post(batch) {
      sending = true;
      batch.forEach((w) => { w.row.querySelector(".bubble").classList.replace("is-waiting", "is-pending"); w.row.querySelector(".bubble-time").textContent = ""; });
      try {
        const body = new FormData();
        batch.forEach((w) => body.append("chat_message[contents][]", w.content));
        const response = await fetch(url, { method: "POST", body, headers: { Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin" });
        const data = await response.json().catch(() => ({ ok: false, error: "Could not send. Try again." }));
        if (!data.ok) throw new Error(data.error || "Could not send. Try again.");
        batch.forEach((w) => w.row.remove());
        sending = false;
        receive(data);
      } catch (error) {
        batch.forEach((w) => { w.row.querySelector(".bubble").classList.replace("is-pending", "is-failed"); w.row.querySelector(".bubble-time").textContent = error.message; });
        const text = batch.map((w) => w.content).join("\n");
        input.value = input.value ? `${text}\n${input.value}` : text; // nothing typed is lost
        hooks.draft?.(input.value);
      } finally {
        sending = false;
        grow();
        flush(); // anything typed while this was on its way
      }
    }

    // Messages that waited when the page was reloaded or left.
    try { JSON.parse(store.get("sessionStorage", WAIT_KEY) || "[]").forEach((content) => { if (typeof content === "string" && content) waiting.push({ content, row: waitRow(content) }); }); } catch (_) { /* ignore */ }

    // Spec 019, owner fix: the button invites the verifier until it is sent away. Resolves to whether it is on now.
    const verifyButton = app.querySelector("button[data-verify]");
    let verifierOn = verifyButton?.getAttribute("aria-pressed") === "true";
    function showVerifier(on) {
      verifierOn = on;
      app.querySelectorAll("button[data-verify], [data-voice-verify]").forEach((b) => { b.classList.toggle("is-on", on); b.setAttribute("aria-pressed", String(on)); });
      const label = verifyButton?.querySelector(".verify-label");
      if (label) label.textContent = on ? "Verifier on" : "Verifier";
    }
    async function verify() {
      if (!verifyButton) return verifierOn;
      try {
        const response = await fetch(verifyButton.form.action, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin" });
        const data = await response.json().catch(() => ({ ok: false }));
        if (!data.ok) return verifierOn;
        showVerifier(data.active);
        if (data.writing) { setWriting(true); status.textContent = "verifier checking…"; }
        return data.active;
      } catch (_) { return verifierOn; }
    }
    // Owner fix (spec 024): a chat replaced by a Turbo visit stops listening, so one Enter never sends twice.
    const on = { signal: life.signal };
    verifyButton?.addEventListener("click", (event) => { event.preventDefault(); verify(); }, on);

    form.addEventListener("submit", (event) => { event.preventDefault(); send(); }, on);
    input.addEventListener("input", () => { grow(); hooks.draft?.(input.value); }, on);
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) { event.preventDefault(); send(); }
    }, on);

    toBottom();
    grow();
    schedulePoll();
    const instance = { poll, grow, input, toBottom, receive, verify, csrf, hold, signal: life.signal, get busy() { return busy(); }, get lastId() { return lastId; }, get verifierOn() { return verifierOn; }, get loaded() { return loaded; }, get writing() { return writing; },
                       on: (name, fn) => listeners[name].push(fn) };
    // Spec 020, owner fix ("przewinęło mi na początek rozmowy"): Turbo moves the floating chat into the next page,
    // and moving an element resets its scroll; keep the position across the move.
    let saved = null;
    instance.keepScroll = () => { saved = { stuck, top: scroller.scrollTop }; };
    instance.restoreScroll = () => {
      if (!saved) return;
      if (saved.stuck) toBottom(); else { scroller.scrollTop = saved.top; stuck = false; }
      saved = null;
    };
    const talk = voice(app, instance);
    instance.destroy = () => {
      stopped = true; clearTimeout(pollTimer); life.abort(); talk?.end();
      waiting.forEach((w) => w.row.remove()); // waiting ones stay stored for the next chat
      dropStream();
      window.agentaroChats.delete(instance);
      if (app.agentaroChat === instance) app.agentaroChat = null;
    };
    app.agentaroChat?.destroy(); // one chat per element
    app.agentaroChat = instance;
    window.agentaroChats.add(instance);
    return instance;
  }

  // ---------- Spec 017: voice mode ----------
  // States: listening → hearing (speech detected) → transcribing → thinking (director writes) → speaking → listening.
  // Silence detection is energy-based: the noise floor is learnt while quiet; speech is a level well above it;
  // about a second of quiet after speech ends the utterance. The microphone waits while the director speaks (owner fix,
  // spec 024: no interrupting; it replaced G6).
  function voice(app, chat) {
    const start = app.querySelector("[data-voice-start]");
    const panel = app.querySelector("[data-voice-panel]");
    if (!start || !panel || app.dataset.voice !== "ready") return;
    // Spec 020, Q1: on the Director page voice mode runs in the floating chat, which survives moving between pages.
    const dockStart = !app.closest("[data-chat-dock]") && document.querySelector("[data-chat-dock] [data-voice-start]");
    if (dockStart) {
      start.addEventListener("click", () => {
        const dock = document.querySelector("[data-chat-dock]");
        if (!dock.classList.contains("is-open")) dock.querySelector("[data-dock-open]")?.click();
        dockStart.click(); // still inside the user's click, so the microphone may start
      }, { signal: chat.signal });
      return { end() {} };
    }
    const stateLabel = panel.querySelector("[data-voice-state]");
    const note = panel.querySelector("[data-voice-note]");
    const dots = [...panel.querySelectorAll(".voice-dots i")];
    const doneButton = panel.querySelector("[data-voice-done]");
    const LABELS = { listening: "Listening…", hearing: "Listening…", transcribing: "Writing down…", thinking: "Thinking…", speaking: "Speaking…", error: "Voice problem" };
    const SILENCE_MS = 1000, MIN_SPEECH_MS = 600, MAX_SPEECH_MS = 30000, TARGET_RATE = 16000;

    let state = "off", ctx = null, mic = null, source = null, processor = null;
    let floor = 0.01, loudMs = 0, quietMs = 0, speechMs = 0, chunks = [], preroll = [], peak = 0, heard = [], heardMs = 0;
    let askedId = 0; // owner fix: the user's latest spoken message; only answers written for it are spoken
    let awaitingAfter = null, spoken = 0, finalText = null, generation = 0, playing = null, queue = Promise.resolve(), pending = 0;
    let waitingVerifier = false; // owner fix: an active verifier speaks after the director
    let waitingToListen = false; // owner fix: voice mode started while the director was still writing

    function setState(next, text) {
      state = next;
      chat.hold?.(next === "speaking"); // owner fix: typed messages wait while the answer is read aloud
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
      app.closest("[data-chat-dock]")?.classList.add("is-voice"); // spec 020, Q1: shown on the Director page too
      if (chat.writing) { setState("thinking", "The director is finishing…"); waitingToListen = true; return; } // owner fix: no interrupting
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
      chat.hold?.(false);
      awaitingAfter = null;
      panel.hidden = true;
      start.hidden = false;
      app.closest("[data-chat-dock]")?.classList.remove("is-voice");
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
      const threshold = Math.max(0.015, floor * 4); // owner fix: fewer false starts from background noise

      if (state === "speaking") return; // owner fix ("nie róbmy przerywania"): the microphone waits for the director
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
        if (!response.ok || !data.ok) throw new Error(data.error || "Could not understand the recording.");
        if (!data.message) return listen("I heard nothing — speak again.");
        setState("thinking", `You: ${data.message.content}`);
        awaitingAfter = data.message.id; askedId = data.message.id; spoken = 0; finalText = null;
        chat.receive(data);
      } catch (error) {
        if (mine === generation && state !== "off") { setState("error", error.message); setTimeout(() => { if (state === "error") listen(); }, 2500); }
      }
    }

    // ---- Speaking the reply: complete sentences go to Piper in order, while the rest is still streaming ----
    chat.on("stream", ({ text, replyTo }) => {
      if (awaitingAfter == null || state === "off" || (replyTo && replyTo < askedId)) return; // owner fix: only the answer to the latest words
      speakUpTo(text, false);
    });
    chat.on("message", (message) => {
      if (awaitingAfter == null || state === "off" || message.author === "user" || message.id <= awaitingAfter) return;
      if (message.reply_to && message.reply_to < askedId) return; // written before the user's latest words: shown, not spoken
      awaitingAfter = null;
      if (message.author === "verifier") { // spec 019, G6: the verifier speaks with its own voice
        waitingVerifier = false;
        finalText = message.content;
        sentences(message.content).forEach((t) => say(t, "verifier"));
        return finishWhenDone();
      }
      if (message.author !== "director") { waitingVerifier = false; return listen(); } // Agentaro's notices are shown, not spoken
      finalText = message.content;
      if (chat.verifierOn) { waitingVerifier = true; awaitingAfter = message.id; } // its comment comes next
      speakUpTo(message.content, true);
    });
    chat.on("writing", (value) => {
      if (!value && waitingToListen && state === "thinking") { waitingToListen = false; return listen(); }
      if (value || awaitingAfter == null) return;
      if (waitingVerifier && pending === 0 && state === "thinking") { waitingVerifier = false; awaitingAfter = null; return listen(); } // no comment came
      if (state === "thinking" && finalText == null) listen();
    });

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

    function say(text, speaker = "director") {
      const mine = generation;
      pending++;
      const audio = fetch(app.dataset.voiceSpeakUrl, { method: "POST", body: JSON.stringify({ text, speaker }),
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
        if (mine === generation && pending === 0 && finalText != null) afterSpeech();
      });
    }

    function finishWhenDone() {
      queue = queue.then(() => { if (pending === 0 && state !== "off" && state !== "hearing") afterSpeech(); });
    }

    // After speaking: listen again, or wait for the verifier's comment when it is on.
    function afterSpeech() {
      if (waitingVerifier) return setState("thinking", "The verifier is checking…");
      listen();
    }

    start.addEventListener("click", begin, { signal: chat.signal });
    panel.querySelector("[data-voice-stop]").addEventListener("click", end, { signal: chat.signal });
    panel.querySelector("[data-voice-done]").addEventListener("click", done, { signal: chat.signal });
    // Spec 019, G6: ask the verifier from voice mode; its comment is spoken in its own voice.
    panel.querySelector("[data-voice-verify]")?.addEventListener("click", async () => {
      if (state === "off" || state === "transcribing") return;
      const after = chat.lastId;
      const on = await chat.verify();
      if (on && chat.writing) { // invited now: it checks the conversation at once
        generation++; playing?.stop?.(); playing = null; pending = 0;
        awaitingAfter = after; finalText = null; waitingVerifier = true;
        setState("thinking", "The verifier is checking…");
      }
    });

    // Owner fix: speech speed (1x–2x), saved for the user; the next sentence uses it.
    const speeds = panel.querySelector("[data-speed-url]");
    speeds?.addEventListener("click", async (event) => {
      const button = event.target.closest("[data-speed]");
      if (!button) return;
      const response = await fetch(speeds.dataset.speedUrl, { method: "PATCH", body: JSON.stringify({ speed: button.dataset.speed }),
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": chat.csrf }, credentials: "same-origin" }).catch(() => null);
      if (!response?.ok) return;
      const { speed } = await response.json();
      speeds.querySelectorAll("[data-speed]").forEach((b) => {
        const on = Number(b.dataset.speed) === speed;
        b.classList.toggle("is-active", on); b.setAttribute("aria-pressed", String(on));
      });
    });
    window.addEventListener("pagehide", end, { signal: chat.signal });
    return { end };
  }

  // ---------- The full-page chat (Director page): started on every visit, ended when the page is left ----------
  window.agentaroOnPage((signal) => {
    const page = document.querySelector(".chat-app:not(.is-dock)");
    if (!page) return;
    // Whatever the Director page shows counts as read for the floating chat.
    const markRead = (id) => { if (id > (Number(store.get("localStorage", SEEN_KEY)) || 0)) store.set("localStorage", SEEN_KEY, String(id)); };
    page.querySelectorAll(".bubble-row:not(.from-user)[data-id]").forEach((row) => markRead(Number(row.dataset.id)));
    const instance = chat(page, { reply: markRead });
    signal.addEventListener("abort", () => instance.destroy());
  });

  // ---------- The floating chat: one per window, kept across Turbo visits (spec 020, data-turbo-permanent) ----------
  const started = new WeakSet();
  window.agentaroOnPage(() => {
    const dock = document.querySelector("[data-chat-dock]");
    if (!dock || started.has(dock)) return;
    started.add(dock);
    startDock(dock);
  });

  function startDock(dock) {
  const app = dock.querySelector(".chat-app");
  const launcher = dock.querySelector("[data-dock-open]");
  const unread = dock.querySelector("[data-unread]");
  const seen = () => Number(store.get("localStorage", SEEN_KEY)) || 0;
  const isOpen = () => dock.classList.contains("is-open");
  const markSeen = (id) => { if (id > seen()) store.set("localStorage", SEEN_KEY, String(id)); };
  let newest = Number(app.dataset.latestReplyId) || 0;
  const directorName = launcher.querySelector(".chat-launcher-label")?.textContent || "the director";
  // Spec 026: unread answers show a dot and make the closed chat's button blink until it is opened.
  function showUnread() {
    const on = !isOpen() && newest > seen();
    unread.hidden = !on;
    launcher.classList.toggle("has-unread", on);
  }

  const instance = chat(app, {
    visible: isOpen,
    reply: (id) => { if (id > newest) titleBlink(directorName); newest = Math.max(newest, id); if (isOpen()) markSeen(id); else showUnread(); },
    writing: (value) => launcher.classList.toggle("is-writing", value),
    draft: (text) => store.set("sessionStorage", DRAFT_KEY, text || null)
  });
  launcher.classList.toggle("is-writing", app.dataset.writing === "true");
  document.addEventListener("turbo:before-render", () => instance.keepScroll());
  document.addEventListener("turbo:render", () => instance.restoreScroll());

  const draft = store.get("sessionStorage", DRAFT_KEY);
  if (draft) { instance.input.value = draft; instance.grow(); }

  function setOpen(open, focus) {
    dock.classList.toggle("is-open", open);
    launcher.setAttribute("aria-expanded", String(open));
    store.set("localStorage", OPEN_KEY, open ? "1" : null);
    if (open) {
      markSeen(newest);
      showUnread();
      instance.poll(); // loads the history the first time, then keeps it current
      instance.toBottom();
      if (focus) instance.input.focus();
    } else {
      showUnread();
      if (focus) launcher.focus();
    }
  }

  // Owner fix ("nie działa maksymalizacja okna rozmowy"): the button grows the panel over the page and back, so a
  // spoken conversation never leaves the floating chat (the link to the Director page is the fallback).
  const maxButton = dock.querySelector("[data-dock-max]");
  function setMax(on) {
    dock.classList.toggle("is-max", on);
    maxButton?.setAttribute("aria-pressed", String(on));
    maxButton?.setAttribute("title", on ? "Back to the side panel" : "Maximize the chat");
    store.set("localStorage", MAX_KEY, on ? "1" : null);
    instance.toBottom();
  }
  maxButton?.addEventListener("click", (event) => { event.preventDefault(); setMax(!dock.classList.contains("is-max")); });
  setMax(store.get("localStorage", MAX_KEY) === "1");

  launcher.addEventListener("click", () => setOpen(true, true));
  dock.querySelector("[data-dock-close]").addEventListener("click", () => setOpen(false, true));
  dock.addEventListener("keydown", (event) => { if (event.key === "Escape" && isOpen()) setOpen(false, true); });
  setOpen(store.get("localStorage", OPEN_KEY) === "1", false);
  }
})();
