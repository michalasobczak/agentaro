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
  const INTERVAL = 20000; // a page may ask for less with data-refresh-every (seconds, at least 5)
  let watched = null, stamp = null, dirty = false, stopped = false, last = 0;

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

  async function check(force) {
    const element = current();
    if (!element || stopped || document.hidden) return;
    const every = Math.max(5, Number(element.dataset.refreshEvery) || INTERVAL / 1000) * 1000;
    if (!force && Date.now() - last < every - 500) return;
    last = Date.now();
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

  setInterval(() => check(false), 5000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check(true); });
})();

// Spec 023: busy or free (spec 036: free, working N/M or busy at the limit). Shared by the chat (team strip, status dots on icons) and the Team page (badges). The data
// comes from AgentStatus.json; text is set with textContent only. Elapsed time is counted here, so it stays fresh
// between changes of the status.
window.agentaroTeamStatus = (() => {
  const elapsed = (iso) => {
    const started = Date.parse(iso);
    if (!iso || Number.isNaN(started)) return null;
    const minutes = Math.max(0, Math.floor((Date.now() - started) / 60000));
    return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
  };
  const cut = (text, limit = 80) => (text.length > limit ? text.slice(0, limit - 3) + "..." : text);

  // The same text as ApplicationHelper#agent_activity_text.
  const activityText = (a) => {
    const where = a.cancelled ? `finishing a step of a ${a.epic_state === "cancelled" ? "cancelled" : "closed"} epic: ${a.epic}` : a.epic;
    const time = elapsed(a.started_at);
    return [where, `step ${a.step}/${a.of}: ${cut(a.title || "")}`, time && `for ${time}`].filter(Boolean).join(" · ");
  };
  // Spec 036, S3: the load first ("free · 0/6 in progress", "2/6 in progress", "busy · 6/6 in progress"), as
  // ApplicationHelper#agent_strip_label.
  const stripText = (agent) => {
    const list = agent.activities || [];
    const head = agent.headline || agent.status;
    if (list.length === 0) return head;
    return `${head} · ${activityText(list[0])}${list.length > 1 ? ` · +${list.length - 1} more` : ""}`;
  };
  const tones = { busy: "warn", working: "accent" }; // ApplicationHelper::AGENT_STATUS_TONES

  function apply(agents, root = document) {
    if (!Array.isArray(agents)) return;
    agents.forEach((agent) => {
      root.querySelectorAll(`[data-agent-icon="${agent.id}"] .status-dot`).forEach((dot) => {
        dot.className = `status-dot is-${agent.status}`;
        dot.title = agent.label;
        dot.hidden = !agent.show_dot;
      });
      root.querySelectorAll(`[data-team-agent="${agent.id}"]`).forEach((chip) => {
        chip.title = `${agent.name}: ${agent.label}`;
        chip.classList.toggle("is-busy", agent.status === "busy"); // spec 024: the ring's colour
        chip.classList.toggle("is-working", agent.status === "working"); // spec 036
        chip.classList.toggle("is-free", agent.status === "free");
        const label = chip.querySelector("[data-team-label]");
        if (label) label.textContent = stripText(agent);
      });
      root.querySelectorAll(`[data-agent-status="${agent.id}"]`).forEach((holder) => {
        holder.hidden = !agent.show_dot;
        const badge = holder.querySelector(".badge");
        if (badge) { badge.textContent = agent.headline || agent.status; badge.className = `badge${tones[agent.status] ? ` ${tones[agent.status]}` : ""}`; }
        const list = holder.querySelector(".agent-activities");
        if (list) {
          list.replaceChildren(...(agent.activities || []).flatMap((a, i) => {
            const span = document.createElement("span");
            span.className = "agent-activity muted small";
            span.title = a.title || "";
            span.textContent = activityText(a);
            return i ? [document.createTextNode(" "), span] : [span];
          }));
        }
      });
    });
    root.querySelectorAll("[data-team-strip]").forEach((strip) => {
      const count = strip.querySelector("[data-team-count]");
      const members = agents.filter((a) => a.member);
      // Spec 036: as ApplicationHelper#team_strip_count.
      const running = members.reduce((sum, a) => sum + ((a.capacity && a.capacity.running) || 0), 0);
      if (count) count.textContent = `${running} ${running === 1 ? "task" : "tasks"} in progress · ${members.filter((a) => a.status === "busy").length} of ${members.length} busy`;
    });
  }

  return { apply, activityText, stripText };
})();
