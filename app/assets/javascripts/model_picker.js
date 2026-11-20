// Agentaro — choose a model from the executor's list, set the effort, check the model (spec 022).
// First-party, no libraries; textContent only. Without this script the model is a plain text field.
"use strict";

window.agentaroOnPage((signal) => { // spec 020: on every visit
  document.querySelectorAll("[data-model-picker]").forEach((picker) => start(picker, signal));
});

function start(picker, signal) {
  let lists = {};
  try { lists = JSON.parse(picker.dataset.lists || "{}"); } catch (_) { return; }
  const forAgent = picker.dataset.agent === "1";
  const source = picker.dataset.source ? document.querySelector(picker.dataset.source) : null;
  const select = picker.querySelector("[data-model-select]");
  const input = picker.querySelector("[data-model-input]");
  const effortField = picker.querySelector("[data-effort-field]");
  const effort = picker.querySelector("[data-model-effort]");
  const checkButton = picker.querySelector("[data-model-check]");
  const OTHER = "\u0000other";
  const efforts = [...effort.options].map((o) => o.value).filter(Boolean);
  const savedEffort = effort.value;

  const entry = () => lists[source ? source.value : picker.dataset.key] || { models: [], efforts: [] };
  const option = (value, label) => { const o = document.createElement("option"); o.value = value; o.textContent = label; return o; };
  const result = () => picker.querySelector("[data-model-check-result]");
  const say = (text, state) => { const r = result(); if (!r) return; r.replaceChildren(text); r.className = "small model-check-result"; r.dataset.state = state || ""; };

  function fillModels() {
    const list = entry();
    const names = list.models.map((m) => m.name);
    if (!names.length) { select.hidden = true; input.hidden = false; return; }
    const first = forAgent ? `Executor's default${list.default ? ` (${list.default})` : ""}` : "None — choose per agent";
    select.replaceChildren(option("", first), ...names.map((n) => option(n, n)), option(OTHER, "Other…"));
    const value = input.value.trim();
    select.value = !value ? "" : names.includes(value) ? value : OTHER;
    select.hidden = false;
    input.hidden = select.value !== OTHER;
  }

  function fillEfforts() {
    const list = entry();
    const model = list.models.find((m) => m.name === (input.value.trim() || list.default));
    const allowed = model && model.efforts && model.efforts.length ? model.efforts : list.efforts;
    effortField.hidden = !allowed.length;
    const keep = effort.value || savedEffort;
    const fallback = forAgent ? list.default_effort : null;
    effort.replaceChildren(option("", `Default${fallback ? ` (${fallback})` : allowed.length ? " (the tool's own)" : ""}`),
                           ...efforts.filter((e) => allowed.includes(e)).map((e) => option(e, e)));
    effort.value = allowed.includes(keep) ? keep : "";
  }

  function refresh() { fillModels(); fillEfforts(); }

  select.addEventListener("change", () => {
    if (select.value === OTHER) { input.value = ""; input.hidden = false; input.focus(); }
    else { input.value = select.value; input.hidden = true; }
    fillEfforts();
    say("Not checked yet.", "");
  }, { signal });
  input.addEventListener("input", () => { fillEfforts(); say("Typed by hand — not checked yet.", "warn"); }, { signal }); // Q1
  source?.addEventListener("change", () => { refresh(); say("Not checked yet.", ""); }, { signal });

  checkButton.hidden = false;
  checkButton.addEventListener("click", async () => {
    const body = { ...JSON.parse(picker.dataset.check || "{}"), model: input.value.trim(), effort: effort.value };
    if (source) body.executor_id = source.value;
    checkButton.disabled = true;
    say("Checking… (up to a minute)", "busy");
    try {
      const response = await fetch(picker.dataset.checkUrl, {
        method: "POST", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json",
                   "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify(body)
      });
      const data = await response.json().catch(() => null);
      if (!data) say(`✗ The check did not answer (${response.status}).`, "bad");
      else say(`${data.ok ? "✓" : "✗"} ${data.output}`, data.ok ? "ok" : "bad");
    } catch (_) {
      say("✗ Agentaro did not answer; try again.", "bad");
    } finally {
      checkButton.disabled = false;
    }
  }, { signal });

  refresh();
}
