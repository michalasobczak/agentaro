// Spec 051: arranging spaces with the mouse on the Spaces page (computer only). A space's card is dragged into a group
// or within it; a group's heading is dragged to order the groups. Each change is saved at once; if saving fails the page
// is reloaded, so it always shows what the server has. First-party, no libraries, no markup written.
"use strict";

window.agentaroOnPage((signal) => {
  const layout = document.querySelector("[data-space-layout]");
  if (!layout || !window.matchMedia("(min-width: 640px)").matches) return; // G4: groups are not changed on a phone
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
  let card = null, section = null;

  layout.querySelectorAll(".space-card").forEach((c) => { c.draggable = true; });
  layout.querySelectorAll("[data-group-handle]").forEach((h) => { h.draggable = true; });

  const status = layout.querySelector("[data-space-status]");

  async function send(url, body) {
    try {
      const response = await fetch(url, { method: "PATCH", body, headers: { Accept: "application/json", "X-CSRF-Token": csrf }, credentials: "same-origin" });
      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.error || `Not saved (${response.status}).`);
      }
      if (status) status.hidden = true;
    } catch (error) {
      // Owner fix: the reason stays on the page, and the page shows the saved order again.
      try { sessionStorage.setItem("agentaro.spaces.error", error.message || "Not saved."); } catch (_) { /* private mode */ }
      window.agentaroReload();
    }
  }
  try {
    const saved = sessionStorage.getItem("agentaro.spaces.error");
    if (saved && status) { status.textContent = `Not moved — ${saved}`; status.hidden = false; }
    sessionStorage.removeItem("agentaro.spaces.error");
  } catch (_) { /* private mode */ }

  // The card in `grid` the pointer is before (by rows, then by columns), or null for the end.
  function cardBefore(grid, x, y) {
    return [...grid.querySelectorAll(".space-card:not(.is-dragging)")].find((c) => {
      const box = c.getBoundingClientRect();
      return y < box.top + box.height / 2 || (y < box.bottom && x < box.left + box.width / 2);
    }) || null;
  }

  function sectionBefore(y) {
    return [...layout.querySelectorAll(".space-section:not(.is-dragging)")].find((s) => {
      const box = s.getBoundingClientRect();
      return s.dataset.groupId && y < box.top + box.height / 2;
    }) || layout.querySelector(".space-section[data-group-id='']");
  }

  layout.addEventListener("dragstart", (event) => {
    const handle = event.target.closest?.("[data-group-handle]");
    if (handle) {
      section = handle.closest(".space-section");
      section.classList.add("is-dragging");
    } else {
      card = event.target.closest?.(".space-card");
      if (!card) return;
      card.classList.add("is-dragging");
    }
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", "");
  }, { signal });

  layout.addEventListener("dragover", (event) => {
    if (card) {
      const grid = event.target.closest?.("[data-space-drop]");
      if (!grid) return;
      event.preventDefault();
      const before = cardBefore(grid, event.clientX, event.clientY);
      before ? grid.insertBefore(card, before) : grid.insertBefore(card, grid.querySelector(".space-drop-hint"));
    } else if (section) {
      event.preventDefault();
      const before = sectionBefore(event.clientY);
      if (before !== section) layout.insertBefore(section, before);
    }
  }, { signal });

  layout.addEventListener("drop", (event) => { if (card || section) event.preventDefault(); }, { signal });

  layout.addEventListener("dragend", () => {
    if (card) {
      const moved = card;
      card = null;
      moved.classList.remove("is-dragging");
      const target = moved.closest(".space-section");
      const index = [...target.querySelectorAll(".space-card")].indexOf(moved) + 1;
      const body = new FormData();
      body.append("group_id", target.dataset.groupId || "");
      body.append("index", String(index));
      target.querySelector(".space-drop-hint")?.remove();
      send(moved.dataset.placeUrl, body);
    } else if (section) {
      const moved = section;
      section = null;
      moved.classList.remove("is-dragging");
      const body = new FormData();
      layout.querySelectorAll(".space-section").forEach((s) => { if (s.dataset.groupId) body.append("ids[]", s.dataset.groupId); });
      send(layout.dataset.orderUrl, body);
    }
  }, { signal });
});
