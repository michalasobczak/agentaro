// Agentaro — spec 023: the Team page shows who is busy and on what, updated in place every 5 s while visible
// (never a reload, so a half-typed role is kept). First-party, no libraries; text via textContent (app.js).
"use strict";

window.agentaroOnPage((signal) => {
  const page = document.querySelector("[data-status-url]");
  if (!page) return;
  const url = page.dataset.statusUrl;
  let stamp = page.dataset.statusStamp;
  let agents = null;
  let failures = 0;
  let timer = null;

  async function check() {
    if (signal.aborted) return;
    if (!document.hidden) {
      try {
        const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", redirect: "manual", signal });
        if (response.type === "opaqueredirect" || response.status === 401) return; // signed out: stop
        if (!response.ok) throw new Error(String(response.status));
        const data = await response.json();
        failures = 0;
        page.classList.remove("is-outdated");
        if (data.stamp !== stamp || !agents) { stamp = data.stamp; agents = data.agents; }
        window.agentaroTeamStatus.apply(agents, document); // the org chart and the Members list; also refreshes "for N min"
      } catch (_) {
        if (signal.aborted) return;
        failures += 1;
        if (failures >= 3) page.classList.add("is-outdated"); // spec 023, Resilience: possibly outdated
      }
    }
    timer = setTimeout(check, 5000);
  }

  signal.addEventListener("abort", () => clearTimeout(timer));
  document.addEventListener("visibilitychange", () => { if (!document.hidden) { clearTimeout(timer); check(); } }, { signal });
  timer = setTimeout(check, 5000);
});
