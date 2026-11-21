// Spec 026: a notice pops up on every page when an epic is blocked — its title, the reason, and Try again, Open
// and Close. Closing is stored on the server, so it does not come back elsewhere until the epic is blocked again.
// When the tab is in the background, a macOS notification is shown too (after the user allowed it once).
// First-party, no libraries; everything is built with textContent.
"use strict";

(() => {
  const POLL_MS = 10000;
  const NOTIFIED_KEY = "agentaro.notices.notified";
  const store = {
    get(key) { try { return JSON.parse(localStorage.getItem(key) || "[]"); } catch (_) { return []; } },
    set(key, value) { try { localStorage.setItem(key, JSON.stringify(value.slice(-50))); } catch (_) { /* ignore */ } }
  };
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };
  const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content;
  const post = (url) => fetch(url, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrf() }, credentials: "same-origin" });

  let started = false, timer = null, shown = new Map();

  function start() {
    const stack = document.querySelector("[data-notices]");
    if (!stack || started) return;
    started = true;
    const url = stack.dataset.url;

    async function poll() {
      clearTimeout(timer);
      try {
        const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
        if (response.type === "opaqueredirect" || response.status === 401) return; // signed out
        if (response.ok) render((await response.json()).blocked || []);
      } catch (_) { /* offline for a moment */ }
      timer = setTimeout(poll, document.hidden ? POLL_MS * 3 : POLL_MS);
    }

    function render(items) {
      const keys = new Set(items.map((i) => i.key));
      shown.forEach((node, key) => { if (!keys.has(key)) { node.remove(); shown.delete(key); } });
      items.forEach((item) => {
        if (!shown.has(item.key)) { const node = card(item); shown.set(item.key, node); stack.append(node); }
      });
      notifySystem(items);
    }

    function card(item) {
      const node = el("section", "notice is-blocked");
      node.setAttribute("role", "alert");
      const head = el("div", "notice-head");
      head.append(el("strong", null, "Epic blocked"), el("span", "notice-space small", item.space));
      const title = el("a", "notice-title", item.title);
      title.href = item.url;
      const reason = el("p", "notice-reason small", item.reason);
      const actions = el("div", "notice-actions");
      const retry = el("button", "secondary small", "Try again");
      retry.type = "button";
      retry.addEventListener("click", async () => {
        retry.disabled = true;
        try { await post(item.retry_url); } catch (_) { /* the next poll shows what happened */ }
        poll();
      });
      const open = el("a", "button secondary small", "Open epic");
      open.href = item.url;
      const close = el("button", "link small", "Close");
      close.type = "button";
      close.addEventListener("click", async () => {
        node.remove(); shown.delete(item.key);
        try { await post(item.dismiss_url); } catch (_) { /* shown again by the next poll */ }
      });
      if (item.retry_url) actions.append(retry); // spec 033: a step's question is answered on the epic's page
      actions.append(open, close);
      node.append(head, title, reason, actions);
      if ("Notification" in window && Notification.permission === "default") {
        const allow = el("button", "link small notice-allow", "Also show these as Mac notifications");
        allow.type = "button";
        allow.addEventListener("click", async () => {
          try { await Notification.requestPermission(); } catch (_) { /* not supported */ }
          document.querySelectorAll(".notice-allow").forEach((b) => b.remove());
        });
        node.append(allow);
      }
      return node;
    }

    // A macOS notification for each new block, once, while the tab is in the background.
    function notifySystem(items) {
      if (!("Notification" in window) || Notification.permission !== "granted" || !document.hidden) return;
      const done = store.get(NOTIFIED_KEY);
      items.filter((i) => !done.includes(i.key)).forEach((item) => {
        try {
          const n = new Notification(`Epic blocked: ${item.title}`, { body: item.reason, tag: `agentaro-${item.key}` });
          n.onclick = () => { window.focus(); window.location.href = item.url; n.close(); };
        } catch (_) { /* not allowed here */ }
        done.push(item.key);
      });
      store.set(NOTIFIED_KEY, done);
    }

    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
    poll();
  }

  if (document.readyState !== "loading") start(); else document.addEventListener("DOMContentLoaded", start, { once: true });
  document.addEventListener("turbo:load", start);
})();
