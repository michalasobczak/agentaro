// Spec 027: the panel beside the director chat — each active space, its epics in progress and their steps —
// redrawn every 5 seconds from GET /director/work (only when something changed). Built with textContent only.
"use strict";

(() => {
  const POLL_MS = 5000;
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };
  const link = (text, href, className) => { const a = el("a", className, text); a.href = href; return a; };
  const label = (state) => state.replace(/_/g, " ");

  function draw(holder, data) {
    const groups = data.groups || [ { name: null, spaces: data.spaces } ];
    const many = groups.length > 1;
    const nodes = data.spaces.length ? groups.flatMap((group) => [
      ...(group.name || many ? [ el("h3", "work-group small", group.name || "Bez grupy") ] : []), // spec 051
      ...group.spaces.map((space) => {
      const section = el("section", "work-space");
      section.append(link(space.name, space.url, "work-space-name"));
      if (!space.epics.length) { section.append(el("p", "work-none small muted", "Nothing planned or in progress.")); return section; }
      const list = el("ul", "work-epics");
      space.epics.forEach((epic) => {
        const item = el("li", `work-epic is-${epic.state}`);
        const head = el("div", "work-epic-head");
        const title = link(epic.title, epic.url);
        title.dataset.liveEpic = String(epic.id); // spec 038: a click shows what the epic is doing
        title.title = "Show what it is doing";
        head.append(title, el("span", "work-state small", epic.paused || epic.state));
        if (epic.pause_url) { // spec 048: pause or resume the epic from the panel
          const button = el("button", "work-pause link small", epic.paused ? "Resume" : "Pause");
          button.type = "button";
          button.dataset.pauseUrl = epic.pause_url;
          button.title = epic.paused ? "Start the epic's work again" : "The current step finishes, then nothing more starts until you resume";
          head.append(button);
        }
        item.append(head);
        if (epic.steps.length) {
          const steps = el("ol", "work-steps");
          epic.steps.forEach((step) => {
            const row = el("li", `work-step is-${step.state.replace(/_/g, "-")}`);
            row.title = step.agent || "";
            row.dataset.liveStep = String(step.id); // spec 038
            row.tabIndex = 0;
            row.setAttribute("role", "button");
            row.append(el("span", "work-step-n", String(step.position)), el("span", "work-step-title", step.title), el("span", "work-state small", step.note || label(step.state)));
            steps.append(row);
          });
          item.append(steps);
        }
        list.append(item);
      });
      section.append(list);
      return section;
    }) ]) : [ el("p", "muted small", "No active spaces.") ];
    holder.replaceChildren(...nodes);
  }

  window.agentaroOnPage((signal) => {
    const panel = document.querySelector("[data-work-panel]");
    if (!panel) return;
    const holder = panel.querySelector("[data-work-spaces]");
    let last = null, timer = null;
    async function poll() {
      if (signal.aborted) return;
      if (!document.hidden) {
        try {
          const response = await fetch(panel.dataset.url, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual", signal });
          if (response.ok) {
            const text = await response.text();
            if (text !== last) { if (last !== null) draw(holder, JSON.parse(text)); last = text; }
          }
        } catch (_) { /* offline for a moment, or the page was left */ }
      }
      timer = setTimeout(poll, POLL_MS);
    }
    signal.addEventListener("abort", () => clearTimeout(timer));
    holder.addEventListener("click", async (event) => { // spec 048
      const button = event.target.closest("[data-pause-url]");
      if (!button) return;
      event.preventDefault();
      button.disabled = true;
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
      await fetch(button.dataset.pauseUrl, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin", signal }).catch(() => null);
      clearTimeout(timer); last = ""; poll(); // "" (not null) so the next answer is drawn
    }, { signal });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) { clearTimeout(timer); poll(); } }, { signal });
    poll();
  });
})();
