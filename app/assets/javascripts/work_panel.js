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

  const SVG = "http://www.w3.org/2000/svg";
  const chevron = () => { // the same icon as the server's icon(:chevron_down), built without markup
    const svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("class", "icon tiny"); svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("aria-hidden", "true");
    const path = document.createElementNS(SVG, "path"); path.setAttribute("d", "m6 9 6 6 6-6");
    svg.append(path);
    return svg;
  };
  const foldButton = () => {
    const button = el("button", "work-fold");
    button.type = "button"; button.dataset.workFold = ""; button.title = "Collapse or expand";
    button.setAttribute("aria-expanded", "true");
    button.append(chevron());
    return button;
  };
  const count = (n, title) => { const pill = el("span", "space-count", String(n)); pill.title = title; return pill; };
  const stats = (epics) => { // "N running", "N blocked", as on the Spaces page
    const box = el("span", "work-stats small");
    [ "running", "blocked" ].forEach((state) => {
      const n = epics.filter((e) => e.state === state).length;
      if (!n) return;
      const item = el("span", `s-${state}`);
      item.append(el("strong", null, String(n)), ` ${state}`);
      box.append(item);
    });
    return box;
  };
  const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

  function spaceNode(space) {
    const section = el("section", "work-space");
    section.dataset.foldKey = `s${space.id}`;
    const bar = el("div", "work-bar work-space-bar");
    bar.append(foldButton(), link(space.name, space.url, "work-space-name"));
    if (space.ci || space.server) { // spec 052: CI and server dots
      const dots = el("span", "work-ci");
      if (space.ci) { const d = el("i", `is-${space.ci}`); d.title = `CI: ${space.ci}`; dots.append(d); }
      if (space.server) { const d = el("i", `is-${space.server}`); d.title = `Server: ${space.server}`; dots.append(d); }
      bar.append(dots);
    }
    bar.append(stats(space.epics), count(space.epics.length, plural(space.epics.length, "epic")));
    const body = el("div", "work-fold-body");
    section.append(bar, body);
    if (!space.epics.length) { body.append(el("p", "work-none small muted", "Nothing planned or in progress.")); return section; }
    const list = el("ul", "work-epics");
    space.epics.forEach((epic) => {
      const item = el("li", `work-epic is-${epic.state}`);
      item.dataset.foldKey = `e${epic.id}`;
      const head = el("div", "work-epic-head");
      if (epic.steps.length) head.append(foldButton());
      const title = link(epic.title, epic.url);
      title.dataset.liveEpic = String(epic.id); // spec 038: a click shows what the epic is doing
      title.title = "Show what it is doing";
      head.append(title);
      if (epic.steps.length) {
        const progress = el("span", "work-progress small", `${epic.steps.filter((s) => s.state === "succeeded").length}/${epic.steps.length}`);
        progress.title = "Steps finished";
        head.append(progress);
      }
      head.append(el("span", "work-state small", epic.paused || epic.state));
      if (epic.pause_url) { // spec 048: pause or resume the epic from the panel
        const button = el("button", "work-pause link small", epic.paused ? "Resume" : "Pause");
        button.type = "button";
        button.dataset.pauseUrl = epic.pause_url;
        button.title = epic.paused ? "Start the epic's work again" : "The current step finishes, then nothing more starts until you resume";
        head.append(button);
      }
      item.append(head);
      if (epic.steps.length) {
        const steps = el("ol", "work-steps work-fold-body");
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
    body.append(list);
    return section;
  }

  // Keep in step with app/views/directors/_work_panel.html.erb.
  function draw(holder, data) {
    const groups = data.groups || [ { id: null, name: null, spaces: data.spaces } ];
    const many = groups.length > 1;
    const nodes = data.spaces.length ? groups.map((group) => {
      const box = Boolean(group.name || many); // spec 051: the owner's groups as panels
      const section = el("section", box ? "work-group-box" : "work-group-plain");
      section.dataset.foldKey = `g${group.id ?? "none"}`;
      if (box) {
        const bar = el("div", "work-bar work-group-bar");
        bar.append(foldButton(), el("h3", "work-group-name", group.name || "Bez grupy"),
                   count(group.spaces.length, plural(group.spaces.length, "space")), stats(group.spaces.flatMap((s) => s.epics)));
        section.append(bar);
      }
      const body = el("div", "work-fold-body");
      body.append(...group.spaces.map(spaceNode));
      section.append(body);
      return section;
    }) : [ el("p", "muted small", "No active spaces.") ];
    holder.replaceChildren(...nodes);
  }

  // Owner change to spec 027 (2026-11-23): groups, spaces and epics fold; the folds are kept in this browser only.
  const FOLD_KEY = "agentaro.work.folded";
  const readFolds = () => { try { return new Set(JSON.parse(localStorage.getItem(FOLD_KEY) || "[]")); } catch (_) { return new Set(); } };
  const writeFolds = (set) => { try { localStorage.setItem(FOLD_KEY, JSON.stringify([ ...set ])); } catch (_) { /* private mode */ } };
  const setFold = (node, folded) => {
    node.classList.toggle("is-folded", folded);
    node.querySelector(":scope > .work-bar [data-work-fold], :scope > .work-epic-head [data-work-fold]")?.setAttribute("aria-expanded", String(!folded));
  };
  const foldable = (holder) => [ ...holder.querySelectorAll("[data-fold-key]") ].filter((node) => node.querySelector(":scope > .work-bar, :scope > .work-epic-head > [data-work-fold]"));
  function applyFolds(holder) {
    const folded = readFolds();
    holder.querySelectorAll("[data-work-fold]").forEach((button) => { button.hidden = false; });
    foldable(holder).forEach((node) => setFold(node, folded.has(node.dataset.foldKey)));
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
            if (text !== last) { if (last !== null) { draw(holder, JSON.parse(text)); applyFolds(holder); } last = text; }
          }
        } catch (_) { /* offline for a moment, or the page was left */ }
      }
      timer = setTimeout(poll, POLL_MS);
    }
    signal.addEventListener("abort", () => clearTimeout(timer));
    applyFolds(holder);
    holder.addEventListener("click", (event) => { // folding: the arrow, or anywhere on a folded bar that is not a link
      const button = event.target.closest("[data-work-fold]");
      const bar = event.target.closest(".work-bar, .work-epic-head");
      const node = (button || bar)?.closest("[data-fold-key]");
      if (!node || (!button && (!node.classList.contains("is-folded") || event.target.closest("a, button")))) return;
      event.preventDefault();
      const now = !node.classList.contains("is-folded");
      const set = readFolds();
      now ? set.add(node.dataset.foldKey) : set.delete(node.dataset.foldKey);
      writeFolds(set);
      setFold(node, now);
    }, { signal });
    const all = panel.querySelector("[data-work-fold-all]");
    if (all) {
      all.hidden = false;
      all.addEventListener("click", (event) => {
        const what = event.target.closest("[data-fold-all]")?.dataset.foldAll;
        if (!what) return;
        const nodes = foldable(holder);
        nodes.forEach((node) => setFold(node, what === "collapse"));
        writeFolds(new Set(what === "collapse" ? nodes.map((node) => node.dataset.foldKey) : []));
      }, { signal });
    }
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
