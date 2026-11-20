// Agentaro calendar (spec 007, G6): drag & drop, resize, create, cut / copy / paste, duplicate, delete.
// First-party, no libraries. Every change is sent to the server; the page then reloads, so what you
// see is always what was saved. Without this script every view and form still works.
"use strict";

window.agentaroOnPage((signal) => { // spec 020: on every visit; `signal` ends listeners when the page is left
  const cal = document.querySelector(".calendar");
  if (!cal) return;

  const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
  const tasksUrl = cal.dataset.moveUrl;            // "/tasks"
  const newUrl = cal.dataset.newUrl;               // "/tasks/new"
  const returnTo = cal.dataset.returnTo;
  const phone = window.matchMedia("(max-width: 639px)");
  const SNAP = 15;                                 // minutes (R5)
  const DRAG_THRESHOLD = 4;                        // pixels before a press becomes a drag
  const scrollKey = "agentaro:cal-scroll:" + location.pathname + location.search;
  const clipKey = "agentaro:cal-clipboard";
  const body = document.getElementById("cal-body");

  // ---------- Wall-clock time helpers ("YYYY-MM-DDTHH:MM" in the app time zone) ----------
  const toMs = (local) => Date.parse(local + ":00Z");
  const fromMs = (ms) => new Date(ms).toISOString().slice(0, 16);
  const addMinutes = (local, minutes) => fromMs(toMs(local) + minutes * 60000);
  const minutesBetween = (a, b) => Math.round((toMs(b) - toMs(a)) / 60000);
  const at = (date, minutes) => addMinutes(date + "T00:00", minutes);
  const timeOfDay = (local) => { const [h, m] = local.slice(11, 16).split(":").map(Number); return h * 60 + m; };
  const snap = (minutes) => Math.round(minutes / SNAP) * SNAP;
  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  // ---------- Scroll: keep position across reloads, otherwise open at 07:00 (Q9) ----------
  if (body) {
    const saved = sessionStorage.getItem(scrollKey);
    body.scrollTop = saved !== null ? Number(saved) : (document.getElementById("h7")?.offsetTop || 0);
    sessionStorage.removeItem(scrollKey);
  }
  const reload = () => { if (body) sessionStorage.setItem(scrollKey, String(body.scrollTop)); window.agentaroReload(); };
  // Auto refresh (app.js) reloads through here, so the scroll position is kept.
  document.addEventListener("agentaro:refresh", (event) => { event.preventDefault(); reload(); }, { signal });

  // ---------- Server calls ----------
  async function send(method, url, data) {
    let result = {};
    try {
      const response = await fetch(url, {
        method, credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify(data)
      });
      result = await response.json().catch(() => ({}));
      if (!response.ok || !result.ok) window.alert((result.errors || ["The change could not be saved."]).join("\n"));
    } catch (error) {
      window.alert("The change could not be saved: " + error.message);
    }
    reload();
  }

  // R4: for a recurring task ask whether the change is for this occurrence or the whole series.
  function askScope(task) {
    if (task.recurring !== "true") return Promise.resolve("this");
    const dialog = document.getElementById("scope-dialog");
    return new Promise((resolve) => {
      const done = (value) => { dialog.close(); resolve(value); };
      dialog.querySelectorAll("button").forEach((button) => { button.onclick = () => done(button.value === "cancel" ? null : button.value); });
      dialog.oncancel = () => resolve(null);
      dialog.showModal();
    });
  }

  const taskData = (el) => ({ ...el.dataset });

  async function moveTask(task, start, end) {
    if (start === task.start && end === task.end) return reload();
    const scope = await askScope(task);
    if (!scope) return reload();
    send("PATCH", `${tasksUrl}/${task.id}/move`, { occurrence: task.occurrence, starts_at: start, ends_at: end, scope });
  }

  const duplicateTask = (task) => send("POST", `${tasksUrl}/${task.id}/duplicate`, { occurrence: task.occurrence });

  async function deleteTask(task) {
    const scope = await askScope(task);
    if (!scope) return;
    if (!window.confirm(scope === "series" ? `Delete every occurrence of “${task.title}”?` : `Delete “${task.title}”?`)) return;
    send("DELETE", `${tasksUrl}/${task.id}`, { occurrence: task.occurrence, scope });
  }

  // ---------- New task in a popup over the calendar (owner correction to G6) ----------
  const taskDialog = document.getElementById("task-dialog");
  const taskForm = document.getElementById("new-task-form");
  const field = (id) => document.getElementById(id);

  // A date three months later (series limit, Q3), as YYYY-MM-DD.
  const quarterAfter = (date) => {
    const d = new Date(date + "T00:00:00Z");
    d.setUTCMonth(d.getUTCMonth() + 3);
    return d.toISOString().slice(0, 10);
  };

  function openNew(start, end) {
    if (!taskDialog || !taskForm) {
      const params = new URLSearchParams({ starts_at: start, ends_at: end, return_to: returnTo });
      location.href = `${newUrl}?${params}`;
      return;
    }
    taskForm.reset();
    showErrors([]);
    if (start && end) {
      field("task_start_date").value = start.slice(0, 10);
      field("task_start_time").value = start.slice(11, 16);
      field("task_end_date").value = end.slice(0, 10);
      field("task_end_time").value = end.slice(11, 16);
    }
    const until = taskForm.querySelector('input[name="task[repeat_until]"]');
    if (until) { until.value = quarterAfter(field("task_start_date").value); until.max = until.value; }
    taskDialog.showModal();
    field("task_title")?.focus();
  }

  function showErrors(messages) {
    const list = taskDialog?.querySelector("[data-errors]");
    if (!list) return;
    list.replaceChildren(...messages.map((m) => { const li = document.createElement("li"); li.textContent = m; return li; }));
    list.hidden = messages.length === 0;
    if (messages.length) list.scrollIntoView({ block: "nearest" });
  }

  if (taskDialog && taskForm) {
    taskDialog.querySelectorAll("[data-close]").forEach((button) => button.addEventListener("click", () => taskDialog.close()));
    taskDialog.addEventListener("click", (e) => { if (e.target === taskDialog) taskDialog.close(); }); // click on the backdrop
    taskForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      const submit = taskForm.querySelector('[type="submit"]');
      submit.disabled = true;
      try {
        const response = await fetch(taskForm.action, {
          method: "POST", credentials: "same-origin", body: new FormData(taskForm),
          headers: { Accept: "application/json", "X-CSRF-Token": csrf }
        });
        const result = await response.json().catch(() => ({}));
        if (response.ok && result.ok) { taskDialog.close(); reload(); return; }
        showErrors(result.errors || ["The task could not be saved."]);
      } catch (error) {
        showErrors(["The task could not be saved: " + error.message]);
      }
      submit.disabled = false;
    });
    document.querySelector("[data-new-task]")?.addEventListener("click", (e) => { e.preventDefault(); openNew(); });
  }

  // ---------- Clipboard (cut / copy / paste), kept across weeks in sessionStorage ----------
  const banner = document.getElementById("cal-clipboard");
  const readClip = () => { try { return JSON.parse(sessionStorage.getItem(clipKey)); } catch { return null; } };
  const writeClip = (clip) => { if (clip) sessionStorage.setItem(clipKey, JSON.stringify(clip)); else sessionStorage.removeItem(clipKey); showClip(); };

  function showClip() {
    const clip = readClip();
    document.querySelectorAll(".task.is-cut").forEach((el) => el.classList.remove("is-cut"));
    if (!clip) { banner.hidden = true; return; }
    if (clip.mode === "cut") {
      document.querySelectorAll(`.task[data-id="${clip.id}"][data-occurrence="${clip.occurrence}"]`).forEach((el) => el.classList.add("is-cut"));
    }
    banner.replaceChildren();
    const text = document.createElement("span");
    text.textContent = `${clip.mode === "cut" ? "Cut" : "Copied"} “${clip.title}” — right-click a free slot, or point at it and press ⌘/Ctrl+V.`;
    const cancel = document.createElement("button");
    cancel.type = "button"; cancel.className = "secondary"; cancel.textContent = "Cancel";
    cancel.onclick = () => writeClip(null);
    banner.append(text, cancel);
    banner.hidden = false;
  }

  const clipTask = (task, mode) => writeClip({ mode, id: task.id, occurrence: task.occurrence, title: task.title,
    recurring: task.recurring, start: task.start, end: task.end, allDay: task.allDay });

  async function paste(start) {
    const clip = readClip();
    if (!clip) return;
    const duration = minutesBetween(clip.start, clip.end);
    if (clip.mode === "copy") {
      send("POST", `${tasksUrl}/${clip.id}/copy`, { occurrence: clip.occurrence, starts_at: start });
    } else {
      const scope = await askScope({ recurring: clip.recurring });
      if (!scope) return;
      sessionStorage.removeItem(clipKey);
      send("PATCH", `${tasksUrl}/${clip.id}/move`, { occurrence: clip.occurrence, starts_at: start, ends_at: addMinutes(start, duration), scope });
    }
  }

  // ---------- Where is the pointer? ----------
  let pointer = { x: 0, y: 0 };
  document.addEventListener("pointermove", (e) => { pointer = { x: e.clientX, y: e.clientY }; }, { passive: true, signal });

  // Slot under a screen point: { date, minutes } in the time grid, { date } in month / all-day cells.
  function slotAt(x, y) {
    const el = document.elementFromPoint(x, y);
    if (!el) return null;
    const day = el.closest(".cal-day");
    if (day) {
      const rect = day.getBoundingClientRect();
      const minutes = clamp(((y - rect.top) / rect.height) * 1440, 0, 1439);
      return { kind: "time", date: day.dataset.date, minutes, el: day };
    }
    const cell = el.closest(".month-day, .allday-cell");
    if (cell) return { kind: cell.classList.contains("allday-cell") ? "allday" : "month", date: cell.dataset.date, el: cell };
    return null;
  }

  // Start time for a paste or a new task at a slot; month and all-day cells keep the original time of day.
  function startForSlot(slot, keepTimeFrom) {
    if (slot.kind === "time") return at(slot.date, clamp(Math.floor(slot.minutes / SNAP) * SNAP, 0, 1440 - SNAP));
    return at(slot.date, keepTimeFrom ? timeOfDay(keepTimeFrom) : 9 * 60);
  }

  const hoveredTask = () => document.elementFromPoint(pointer.x, pointer.y)?.closest(".task[data-id]");

  // ---------- Context menu ----------
  const menu = document.getElementById("cal-menu");
  function openMenu(x, y, items) {
    menu.replaceChildren(...items.map(([label, key, action, css]) => {
      const button = document.createElement("button");
      button.type = "button"; button.setAttribute("role", "menuitem");
      if (css) button.className = css;
      const name = document.createElement("span"); name.textContent = label;
      const hint = document.createElement("kbd"); hint.textContent = key || "";
      button.append(name, hint);
      button.onclick = () => { closeMenu(); action(); };
      return button;
    }));
    menu.hidden = false;
    const { width, height } = menu.getBoundingClientRect();
    menu.style.left = `${Math.min(x, window.innerWidth - width - 8)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - height - 8)}px`;
    menu.querySelector("button")?.focus();
  }
  const closeMenu = () => { menu.hidden = true; };
  document.addEventListener("click", (e) => { if (!menu.contains(e.target)) closeMenu(); }, { signal });
  window.addEventListener("scroll", closeMenu, { capture: true, signal });

  cal.addEventListener("contextmenu", (e) => {
    if (phone.matches) return;
    const el = e.target.closest(".task[data-id]");
    const slot = slotAt(e.clientX, e.clientY);
    if (el) {
      e.preventDefault();
      const task = taskData(el);
      const editable = task.editable === "true";
      openMenu(e.clientX, e.clientY, [
        [ editable ? "Edit" : "Open", "", () => { location.href = el.href; } ],
        ...(editable ? [
          [ "Cut", "⌘X", () => clipTask(task, "cut") ],
          [ "Copy", "⌘C", () => clipTask(task, "copy") ],
          [ "Duplicate", "⌘D", () => duplicateTask(task) ],
          [ "Delete", "⌫", () => deleteTask(task), "danger" ]
        ] : [ [ "Copy", "⌘C", () => clipTask(task, "copy") ] ])
      ]);
    } else if (slot) {
      e.preventDefault();
      const clip = readClip();
      const start = startForSlot(slot, clip?.start);
      const items = [ [ "New task here", "", () => openNew(start, addMinutes(start, 60)) ] ];
      if (clip) items.unshift([ `Paste “${clip.title}” here`, "⌘V", () => paste(start) ]);
      openMenu(e.clientX, e.clientY, items);
    }
  });

  // ---------- Keyboard: ⌘/Ctrl + C, X, V, D; Delete; Escape ----------
  document.addEventListener("keydown", (e) => {
    if (e.target.closest("input, textarea, select, [contenteditable], dialog")) return;
    if (e.key === "Escape") { closeMenu(); writeClip(null); return; }
    if (phone.matches) return;
    const mod = e.metaKey || e.ctrlKey;
    const el = hoveredTask();
    const task = el && taskData(el);
    const editable = task && task.editable === "true";
    const key = e.key.toLowerCase();
    if (mod && key === "c" && task) { e.preventDefault(); clipTask(task, "copy"); }
    else if (mod && key === "x" && editable) { e.preventDefault(); clipTask(task, "cut"); }
    else if (mod && key === "d" && editable) { e.preventDefault(); duplicateTask(task); }
    else if (mod && key === "v" && readClip()) {
      const slot = slotAt(pointer.x, pointer.y);
      if (slot) { e.preventDefault(); paste(startForSlot(slot, readClip().start)); }
    } else if ((e.key === "Delete" || e.key === "Backspace") && editable && !mod) { e.preventDefault(); deleteTask(task); }
  }, { signal });

  // ---------- Drag & drop, resize, create by dragging ----------
  let gesture = null;
  let suppressClick = false;

  cal.addEventListener("dragstart", (e) => { if (e.target.closest(".task")) e.preventDefault(); });

  cal.addEventListener("pointerdown", (e) => {
    if (e.button !== 0 || phone.matches || e.target.closest("dialog, #cal-menu, .cal-toolbar")) return;
    const el = e.target.closest(".task[data-id]");
    if (el) {
      if (el.dataset.editable !== "true") return;
      const handle = e.target.closest(".handle");
      gesture = { type: handle ? (handle.classList.contains("handle-top") ? "resize-top" : "resize-bottom") : "move",
                  el, task: taskData(el), x: e.clientX, y: e.clientY, started: false,
                  grab: grabOffset(el, e) };
    } else {
      const slot = slotAt(e.clientX, e.clientY);
      if (slot && slot.kind === "time") gesture = { type: "create", slot, x: e.clientX, y: e.clientY, started: false };
    }
  });

  // Minutes between the task's start and the point where it was grabbed (so it does not jump).
  function grabOffset(el, e) {
    const slot = slotAt(e.clientX, e.clientY);
    const task = el.dataset;
    if (!slot || slot.kind !== "time") return 0;
    return minutesBetween(task.start, at(slot.date, slot.minutes));
  }

  window.addEventListener("pointermove", (e) => {
    if (!gesture) return;
    if (!gesture.started) {
      if (Math.hypot(e.clientX - gesture.x, e.clientY - gesture.y) < DRAG_THRESHOLD) return;
      gesture.started = true;
      if (gesture.el) gesture.el.classList.add("is-dragging");
    }
    e.preventDefault();
    preview(e.clientX, e.clientY);
  }, { signal });

  window.addEventListener("pointerup", (e) => {
    if (!gesture) return;
    const current = gesture;
    gesture = null;
    if (!current.started) return; // a plain click: links open the task, empty slots below
    suppressClick = true;
    setTimeout(() => { suppressClick = false; }, 0);
    finish(current, e.clientX, e.clientY);
  }, { signal });

  cal.addEventListener("click", (e) => {
    if (suppressClick) { e.preventDefault(); e.stopPropagation(); return; }
    if (phone.matches || e.target.closest(".task, a, button, dialog, form, .cal-toolbar")) return;
    const slot = slotAt(e.clientX, e.clientY);
    if (!slot || slot.kind === "allday") return;
    const start = startForSlot(slot);
    openNew(start, addMinutes(start, 60));
  }, true);

  // The range a gesture would produce, as wall-clock start and end.
  function rangeFor(g, x, y) {
    const slot = slotAt(x, y);
    const task = g.task;
    if (g.type === "create") {
      if (!slot || slot.kind !== "time" || slot.date !== g.slot.date) return null;
      const a = snap(g.slot.minutes), b = snap(slot.minutes);
      const from = Math.min(a, b), to = Math.max(a, b);
      return { slot: g.slot, start: at(g.slot.date, from), end: at(g.slot.date, Math.max(to, from + SNAP)) };
    }
    if (!slot) return null;
    const duration = minutesBetween(task.start, task.end);
    if (g.type === "move") {
      if (slot.kind === "time") {
        if (task.allDay === "true") return null;
        const start = at(slot.date, clamp(snap(slot.minutes - g.grab), 0, 1440 - SNAP));
        return { slot, start, end: addMinutes(start, duration) };
      }
      if (slot.kind === "allday" && task.allDay !== "true") return null;
      const start = at(slot.date, timeOfDay(task.start));
      return { slot, start, end: addMinutes(start, duration) };
    }
    if (slot.kind !== "time") return null;
    const point = at(slot.date, snap(slot.minutes));
    if (g.type === "resize-bottom") {
      const end = toMs(point) > toMs(task.start) ? point : addMinutes(task.start, SNAP);
      return { slot, start: task.start, end };
    }
    const start = toMs(point) < toMs(task.end) ? point : addMinutes(task.end, -SNAP);
    return { slot, start, end: task.end };
  }

  let ghost = null;
  function preview(x, y) {
    const range = rangeFor(gesture, x, y);
    document.querySelectorAll(".drop-target").forEach((el) => el.classList.remove("drop-target"));
    ghost?.remove(); ghost = null;
    if (!range) return;
    if (range.slot.kind !== "time") { range.slot.el.classList.add("drop-target"); return; }
    const column = range.slot.el;
    const dayStart = range.slot.date + "T00:00";
    const from = clamp(minutesBetween(dayStart, range.start), 0, 1440);
    const to = clamp(minutesBetween(dayStart, range.end), 0, 1440);
    ghost = document.createElement("div");
    ghost.className = "ghost";
    ghost.style.top = `${(from / 1440) * 100}%`;
    ghost.style.height = `${Math.max(((to - from) / 1440) * 100, 0.6)}%`;
    column.append(ghost);
    autoScroll(y);
  }

  function autoScroll(y) {
    if (!body) return;
    const rect = body.getBoundingClientRect();
    if (y < rect.top + 30) body.scrollTop -= 12;
    else if (y > rect.bottom - 30) body.scrollTop += 12;
  }

  function finish(g, x, y) {
    const range = rangeFor(g, x, y);
    ghost?.remove(); ghost = null;
    document.querySelectorAll(".drop-target").forEach((el) => el.classList.remove("drop-target"));
    g.el?.classList.remove("is-dragging");
    if (!range) return;
    if (g.type === "create") return openNew(range.start, range.end);
    moveTask(g.task, range.start, range.end);
  }

  showClip();
});
