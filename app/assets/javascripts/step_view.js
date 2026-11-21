// Spec 038: a click on a step (or an epic) in the work panel opens the view beside it — what the agent is doing,
// from GET /director/live. While a step runs, or while an epic is followed, it refreshes every 2 seconds (R6);
// a closed view or a hidden tab asks for nothing. Built with textContent only (R5).
"use strict";

(() => {
  const POLL_MS = 2000;
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };
  const link = (text, href, className) => { const a = el("a", className, text); a.href = href; return a; };
  const clock = (seconds) => {
    const s = Math.max(0, seconds | 0), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
    const two = (n) => String(n).padStart(2, "0");
    return h ? `${h}:${two(m)}:${two(r)}` : `${m}:${two(r)}`;
  };
  const time = (date) => date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });

  function entryNode(entry) {
    const item = el("li", `step-log-entry is-${entry.kind}${entry.error ? " is-error" : ""}`);
    if (entry.kind !== "text") {
      const label = entry.kind === "action" ? entry.label : `${entry.label || "result"}${entry.error ? " failed" : ""}`;
      item.append(el("span", "step-log-label", label));
      if (entry.source === "web") item.append(el("span", "step-log-source", "web"));
    }
    item.append(el("span", "step-log-text", entry.text || (entry.kind === "result" ? "(no output)" : "")));
    return item;
  }

  function section(title, text, className) {
    const box = el("div", `step-view-section ${className || ""}`);
    box.append(el("h3", "step-view-label", title), el("div", "pre", text));
    return box;
  }

  function draw(body, data, stale) {
    const nodes = [];
    const head = el("div", "step-view-epic");
    head.append(link(data.epic.title, data.epic.url), el("span", "work-state small", data.epic.state));
    nodes.push(head);
    if (data.following) nodes.push(el("p", "small muted", "Following the epic: the next step shows when it starts."));

    const step = el("div", `step-view-step is-${data.step.state.replace(/_/g, "-")}`);
    step.append(el("strong", null, `Step ${data.step.position} of ${data.step.of}: ${data.step.title}`));
    const meta = el("div", "small muted step-view-meta");
    meta.append(el("span", "step-view-state", data.step.label));
    if (data.step.agent) meta.append(el("span", null, data.step.agent));
    if (data.run && data.run.elapsed != null) meta.append(el("span", null, `${data.running ? "running for" : "took"} ${clock(data.run.elapsed)}`));
    step.append(meta);
    nodes.push(step);

    if (data.run && data.run.interrupted) nodes.push(el("p", "flash alert small", "Interrupted (Agentaro was restarted): the log below is what it did until then."));
    if (stale) nodes.push(el("p", "small muted", `Not refreshed since ${time(stale)}.`));
    if (data.waits) nodes.push(section("Waits for", data.waits, "is-waits"));
    if (data.question) nodes.push(section("Question for you", data.question, "is-question"));
    if (!data.run && data.step.description) nodes.push(section("Task", data.step.description));
    if (data.running && data.stream === "none") nodes.push(el("p", "small muted", "This executor reports when it ends."));
    if (data.running && data.stream !== "none" && !data.entries.length && !data.text) nodes.push(el("p", "small muted", "Starting…"));

    if (data.earlier) nodes.push(el("p", "small muted", `${data.earlier} earlier entries`));
    if (data.entries.length) {
      const log = el("ol", "step-log");
      data.entries.forEach((entry) => log.append(entryNode(entry)));
      nodes.push(log);
    }
    if (data.text) nodes.push(section(data.running ? "Writing" : "Text", data.text, "is-text"));
    if (data.answer) nodes.push(section("Answer", data.answer, "is-answer"));
    if (data.error) nodes.push(section("Error", data.error, "is-error"));
    if (data.run) nodes.push(link("Open the run (full trace)", data.run.url, "small"));
    body.replaceChildren(...nodes);
  }

  window.agentaroOnPage((signal) => {
    const view = document.querySelector("[data-step-view]");
    const panel = document.querySelector("[data-work-panel]");
    if (!view || !panel) return;
    const layout = view.closest(".director-layout");
    const body = view.querySelector("[data-step-view-body]");
    let target = null, timer = null, last = null, failedSince = null, controller = null;

    function close() {
      target = null; last = null; failedSince = null;
      clearTimeout(timer);
      if (controller) controller.abort();
      view.hidden = true;
      layout.classList.remove("has-step-view");
      body.replaceChildren();
    }

    async function load() {
      clearTimeout(timer);
      if (!target || signal.aborted) return;
      const wanted = target;
      let data = null;
      if (!document.hidden) {
        controller = new AbortController();
        signal.addEventListener("abort", () => controller.abort(), { once: true });
        try {
          const url = `${view.dataset.url}?${wanted.kind}=${encodeURIComponent(wanted.id)}`;
          const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual", signal: controller.signal });
          if (target !== wanted) return;
          if (response.status === 404) { body.replaceChildren(el("p", "muted small", "This step is no longer in your work.")); return; }
          if (response.ok) {
            const text = await response.text();
            data = JSON.parse(text);
            failedSince = null;
            if (text !== last) {
              const atEnd = view.scrollHeight - view.scrollTop - view.clientHeight < 40;
              draw(body, data, null);
              if (atEnd || last === null) view.scrollTop = view.scrollHeight;
              last = text;
            }
          } else { failedSince = failedSince || new Date(); }
        } catch (_) {
          if (signal.aborted || target !== wanted) return;
          failedSince = failedSince || new Date();
        }
        if (failedSince && last) draw(body, JSON.parse(last), failedSince);
      }
      const live = data ? (data.running || data.following) : true;
      if (target === wanted && live) timer = setTimeout(load, POLL_MS);
    }

    function open(kind, id) {
      target = { kind, id }; last = null; failedSince = null;
      view.hidden = false;
      layout.classList.add("has-step-view");
      body.replaceChildren(el("p", "muted small", "Loading…"));
      load();
    }

    panel.addEventListener("click", (event) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const epic = event.target.closest("[data-live-epic]");
      const step = event.target.closest("[data-live-step]");
      if (epic) { event.preventDefault(); open("epic", epic.dataset.liveEpic); }
      else if (step) open("step", step.dataset.liveStep);
    }, { signal });
    panel.addEventListener("keydown", (event) => {
      const step = event.target.closest("[data-live-step]");
      if (step && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); open("step", step.dataset.liveStep); }
    }, { signal });
    view.querySelector("[data-step-view-close]").addEventListener("click", close, { signal });
    document.addEventListener("keydown", (event) => { if (event.key === "Escape" && target) close(); }, { signal });
    document.addEventListener("visibilitychange", () => { if (!document.hidden && target) load(); }, { signal });
    signal.addEventListener("abort", () => clearTimeout(timer));
  });
})();
