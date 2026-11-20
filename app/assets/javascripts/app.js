// Agentaro — small helpers for every page (spec 007). First-party, no libraries.
// Spec 020: pages are swapped by Turbo, so this file runs once; what depends on the page starts on every visit.
"use strict";

// Forms marked data-confirm ask before submitting (e.g. "Delete this task?").
document.addEventListener("submit", (event) => {
  const message = event.target.dataset && event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
}, true);

// Spec 020: show a page again without a full load when Turbo is there (the floating chat and voice mode survive);
// a full reload otherwise.
window.agentaroReload = () => {
  if (window.Turbo) window.Turbo.visit(location.href, { action: "replace" });
  else location.reload();
};

// Spec 020: run `start(signal)` on the first load and on every Turbo visit. `signal` ends when the page is left, so
// listeners added with it on document or window never pile up.
window.agentaroOnPage = (start) => {
  let controller = null;
  const run = () => {
    controller?.abort();
    controller = new AbortController();
    start(controller.signal);
  };
  document.addEventListener("turbo:load", run);
  document.addEventListener("turbo:before-render", () => { controller?.abort(); controller = null; });
  if (document.readyState !== "loading") run(); else document.addEventListener("DOMContentLoaded", run, { once: true });
};

// Auto refresh (owner fix after spec 010). A page with [data-refresh-url] asks the server every 20 seconds
// for a fingerprint of what it shows and refreshes when it changed — never while the user is busy: a dialog
// or menu open, a drag in progress, a task selected, or unsaved edits (then a notice is shown instead).
(() => {
  const INTERVAL = 20000;
  let watched = null, stamp = null, dirty = false, stopped = false;

  // Each visit brings its own page to watch.
  document.addEventListener("turbo:load", () => { watched = null; });
  const current = () => {
    const element = document.querySelector("[data-refresh-url]");
    if (element !== watched) { watched = element; stamp = element?.dataset.refreshStamp; dirty = false; stopped = false; }
    return element;
  };

  document.addEventListener("input", (event) => { if (event.target.form && !event.target.closest("dialog, .chat-app")) dirty = true; });

  const busy = () => Boolean(document.querySelector("dialog[open], .is-dragging, .is-selected, .cal-menu:not([hidden])")) ||
    (document.activeElement && document.activeElement.matches("input, textarea, select") && !document.activeElement.closest(".chat-app"));

  async function check() {
    const element = current();
    if (!element || stopped || document.hidden) return;
    let response;
    try {
      response = await fetch(element.dataset.refreshUrl, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual" });
    } catch (_) { return; } // offline for a moment: try again next time
    if (element !== watched) return; // the user moved on meanwhile
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
    // The calendar keeps its scroll position; other pages simply refresh.
    if (document.dispatchEvent(new CustomEvent("agentaro:refresh", { cancelable: true }))) window.agentaroReload();
  }

  setInterval(check, INTERVAL);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check(); });
})();
