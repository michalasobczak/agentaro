// Agentaro — the kanban board of a project (spec 013, Q10). First-party, no libraries.
// Cards move only up and down within their column; the new order is saved at once. States are changed by the
// director, or with the Done and Cancel buttons on a card. Without this script the board is simply shown.
"use strict";

(() => {
  const board = document.querySelector(".kanban[data-order-url]");
  if (!board) return;
  const url = board.dataset.orderUrl;
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
  let dragged = null;

  async function save(list) {
    const body = new FormData();
    list.querySelectorAll(".kanban-card").forEach((card) => body.append("ids[]", card.dataset.id));
    try {
      const response = await fetch(url, { method: "PATCH", body, headers: { "X-CSRF-Token": csrf }, credentials: "same-origin" });
      if (!response.ok) throw new Error(String(response.status));
    } catch (_) {
      location.reload(); // the board shows the order the server has
    }
  }

  // The card in `list` before which `y` falls, or null for the end.
  function cardAfter(list, y) {
    return [...list.querySelectorAll(".kanban-card:not(.is-dragging)")].find((card) => {
      const box = card.getBoundingClientRect();
      return y < box.top + box.height / 2;
    }) || null;
  }

  board.addEventListener("dragstart", (event) => {
    const card = event.target.closest?.(".kanban-card");
    if (!card) return;
    dragged = card;
    card.classList.add("is-dragging");
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", card.dataset.id);
  });

  board.addEventListener("dragover", (event) => {
    if (!dragged) return;
    const list = event.target.closest(".kanban-cards");
    if (list !== dragged.parentElement) return; // other columns: not a drop target
    event.preventDefault();
    const next = cardAfter(list, event.clientY);
    if (next !== dragged.nextElementSibling) list.insertBefore(dragged, next);
  });

  board.addEventListener("drop", (event) => { if (dragged) event.preventDefault(); });

  board.addEventListener("dragend", () => {
    if (!dragged) return;
    const list = dragged.parentElement;
    dragged.classList.remove("is-dragging");
    dragged = null;
    save(list);
  });

  // Keyboard: Alt + ↑ / ↓ on a focused card.
  board.addEventListener("keydown", (event) => {
    const card = event.target.closest(".kanban-card");
    if (!card || !event.altKey || !["ArrowUp", "ArrowDown"].includes(event.key)) return;
    event.preventDefault();
    const sibling = event.key === "ArrowUp" ? card.previousElementSibling : card.nextElementSibling;
    if (!sibling) return;
    card.parentElement.insertBefore(card, event.key === "ArrowUp" ? sibling : sibling.nextElementSibling);
    card.focus();
    save(card.parentElement);
  });
})();
