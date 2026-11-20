// Agentaro — small helpers for every page (spec 007). First-party, no libraries.
"use strict";

// Forms marked data-confirm ask before submitting (e.g. "Delete this task?").
document.addEventListener("submit", (event) => {
  const message = event.target.dataset && event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
}, true);

// Auto refresh (owner fix after spec 010). A page with [data-refresh-url] asks the server every 20 seconds
// for a fingerprint of what it shows and reloads when it changed — never while the user is busy: a dialog
// or menu open, a drag in progress, a task selected, or unsaved edits (then a notice is shown instead).
(() => {
  const watched = document.querySelector("[data-refresh-url]");
  if (!watched) return;
  const INTERVAL = 20000;
  let stamp = watched.dataset.refreshStamp;
  let dirty = false;
  let stopped = false;

  document.addEventListener("input", (event) => { if (event.target.form && !event.target.closest("dialog, .chat-app")) dirty = true; });

  const busy = () => Boolean(document.querySelector("dialog[open], .is-dragging, .is-selected, .cal-menu:not([hidden])")) ||
    (document.activeElement && document.activeElement.matches("input, textarea, select"));

  async function check() {
    if (stopped || document.hidden) return;
    let response;
    try {
      response = await fetch(watched.dataset.refreshUrl, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
    } catch (_) { return; } // offline for a moment: try again next time
    if (!response.ok) { stopped = response.status === 401 || response.status === 403 || response.status === 404 || response.type === "opaqueredirect"; return; }
    const data = await response.json().catch(() => null);
    if (!data || data.stamp === stamp) return;
    if (dirty) {
      const notice = document.querySelector("[data-refresh-notice]");
      if (notice) notice.hidden = false;
      return;
    }
    if (busy()) return; // stamp stays old, so the next check tries again
    stamp = data.stamp;
    // The calendar keeps its scroll position on reload; other pages simply reload.
    if (document.dispatchEvent(new CustomEvent("agentaro:refresh", { cancelable: true }))) location.reload();
  }

  setInterval(check, INTERVAL);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check(); });
})();

