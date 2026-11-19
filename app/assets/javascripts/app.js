// Agentaro — small helpers for every page (spec 007). First-party, no libraries.
"use strict";

// Forms marked data-confirm ask before submitting (e.g. "Delete this task?").
document.addEventListener("submit", (event) => {
  const message = event.target.dataset && event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
}, true);
