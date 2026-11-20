// Agentaro — the director chat (spec 011, owner fixes: "chat niech będzie naprawdę chatem"; floating chat on the
// right on every other page). First-party, no libraries. Messages are sent and received as JSON; the page never
// reloads. Everything is built with textContent (never HTML). Without this script the form posts normally.
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
      if (message.author !== "user") hooks.reply?.(message.id);
    }

    function setWriting(value) {
      writing = value;
      const stick = nearBottom();
      typing.hidden = !value;
      status.textContent = value ? "writing…" : idleStatus;
      if (value) status.dataset.writing = ""; else delete status.dataset.writing;
      hooks.writing?.(value);
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
          if (data.writing !== writing) return setWriting(data.writing);
        }
      } catch (_) { /* offline for a moment: try again later */ }
      schedulePoll();
    }

    function schedulePoll() {
      clearTimeout(pollTimer);
      pollTimer = setTimeout(poll, !visible() ? 20000 : writing ? 1500 : 8000);
    }

    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });

    // ---------- Sending ----------
    function grow() {
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 160) + "px";
      sendButton.disabled = input.value.trim() === "" || sending;
    }

    async function send() {
      const content = input.value.trim();
      if (!content || sending) return;
      sending = true;
      const pending = bubble({ author: "user", content, time: new Date().toTimeString().slice(0, 5) }, "is-pending");
      stream.querySelector("[data-empty]")?.remove();
      stream.insertBefore(pending, typing);
      toBottom();
      input.value = "";
      hooks.draft?.(null);
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
      } catch (error) {
        pending.querySelector(".bubble").classList.replace("is-pending", "is-failed");
        pending.querySelector(".bubble-time").textContent = error.message;
        input.value = content; // nothing typed is lost
        hooks.draft?.(content);
      } finally {
        sending = false;
        grow();
        input.focus();
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
    return { poll, grow, input, toBottom, get loaded() { return loaded; } };
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
