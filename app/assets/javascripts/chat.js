// Agentaro — the director chat (spec 011, owner fix: "chat niech będzie naprawdę chatem").
// First-party, no libraries. Messages are sent and received as JSON; the page never reloads.
// Everything is built with textContent (never HTML). Without this script the form posts normally.
"use strict";

(() => {
  const app = document.querySelector(".chat-app");
  if (!app) return;

  const url = app.dataset.messagesUrl;
  const scroller = document.getElementById("chat-scroll");
  const stream = document.getElementById("chat-stream");
  const typing = stream.querySelector("[data-typing]");
  const status = app.querySelector("[data-status]");
  const form = document.getElementById("chat-composer");
  const input = document.getElementById("chat-input");
  const sendButton = form.querySelector(".send");
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
  const idleStatus = status.textContent === "writing…" ? "your director" : status.textContent;

  let lastId = Number(app.dataset.lastId) || 0;
  let writing = app.dataset.writing === "true";
  let lastDay = [...stream.querySelectorAll("[data-day]")].pop()?.dataset.day || null;
  let pollTimer = null;
  let sending = false;

  // ---------- Scrolling: stay at the bottom unless the user scrolled up to read ----------
  const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 120;
  const toBottom = () => { scroller.scrollTop = scroller.scrollHeight; };
  toBottom();

  // ---------- Building messages (textContent only) ----------
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
  }

  function setWriting(value) {
    writing = value;
    const stick = nearBottom();
    typing.hidden = !value;
    status.textContent = value ? "writing…" : idleStatus;
    if (value) status.dataset.writing = ""; else delete status.dataset.writing;
    if (stick) toBottom();
    schedulePoll();
  }

  // ---------- Receiving: poll quickly while the director is writing, slowly otherwise ----------
  async function poll() {
    if (document.hidden) return schedulePoll();
    try {
      const response = await fetch(`${url}?after=${lastId}`, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
      if (response.type === "opaqueredirect" || response.status === 401) return; // signed out: stop
      if (response.ok) {
        const data = await response.json();
        data.messages.forEach(append);
        if (data.writing !== writing) return setWriting(data.writing);
      }
    } catch (_) { /* offline for a moment: try again later */ }
    schedulePoll();
  }

  function schedulePoll() {
    clearTimeout(pollTimer);
    pollTimer = setTimeout(poll, writing ? 1500 : 8000);
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
    const now = new Date();
    const pending = bubble({ author: "user", content, time: now.toTimeString().slice(0, 5) }, "is-pending");
    stream.querySelector("[data-empty]")?.remove();
    stream.insertBefore(pending, typing);
    toBottom();
    input.value = "";
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
      grow();
    } finally {
      sending = false;
      grow();
      input.focus();
    }
  }

  form.addEventListener("submit", (event) => { event.preventDefault(); send(); });
  input.addEventListener("input", grow);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) { event.preventDefault(); send(); }
  });

  grow();
  schedulePoll();
})();
