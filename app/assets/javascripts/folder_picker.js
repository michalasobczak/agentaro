// Agentaro — live folder suggestions for a space's working folder (owner fix after spec 018: "nie znam dokładnej
// nazwy katalogu"). First-party, no libraries; textContent only. Without this script the field is a plain input.
"use strict";

window.agentaroOnPage(() => { // spec 020: on every visit
  const picker = document.querySelector(".folder-picker[data-folders-url]");
  if (!picker) return;
  const input = picker.querySelector("input");
  const list = picker.querySelector(".folder-suggestions");
  const status = picker.querySelector("[data-folder-status]");
  let items = [], active = -1, timer = null, asked = 0;

  async function load() {
    const ask = ++asked;
    try {
      const response = await fetch(`${picker.dataset.foldersUrl}?path=${encodeURIComponent(input.value)}`,
                                   { headers: { Accept: "application/json" }, credentials: "same-origin" });
      if (!response.ok || ask !== asked) return;
      const data = await response.json();
      show(data.folders);
      const typed = input.value.trim();
      status.textContent = !typed ? "" : data.exists ? "✓ This folder exists" : "No folder with this exact path yet";
      status.dataset.state = data.exists ? "ok" : typed ? "missing" : "";
    } catch (_) { /* offline: no suggestions */ }
  }

  function show(folders) {
    items = folders;
    active = -1;
    list.replaceChildren(...folders.map((path, i) => {
      const li = document.createElement("li");
      li.setAttribute("role", "option");
      li.id = `folder-option-${i}`;
      const trimmed = path.replace(/\/$/, "");
      const cut = trimmed.lastIndexOf("/");
      const parent = document.createElement("span");
      parent.className = "folder-parent";
      parent.textContent = trimmed.slice(0, cut + 1);
      const name = document.createElement("strong");
      name.textContent = trimmed.slice(cut + 1) + "/";
      li.append(parent, name);
      li.addEventListener("mousedown", (event) => { event.preventDefault(); pick(i); });
      return li;
    }));
    const open = folders.length > 0 && document.activeElement === input;
    list.hidden = !open;
    input.setAttribute("aria-expanded", String(open));
  }

  function highlight(index) {
    active = (index + items.length) % items.length;
    [...list.children].forEach((li, i) => li.setAttribute("aria-selected", String(i === active)));
    input.setAttribute("aria-activedescendant", `folder-option-${active}`);
    list.children[active]?.scrollIntoView({ block: "nearest" });
  }

  // Taking a folder fills the field and shows its subfolders at once.
  function pick(index) {
    input.value = items[index];
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.focus();
  }

  const later = () => { clearTimeout(timer); timer = setTimeout(load, 120); };
  input.addEventListener("input", later);
  input.addEventListener("focus", later);
  input.addEventListener("blur", () => setTimeout(() => { list.hidden = true; input.setAttribute("aria-expanded", "false"); }, 120));
  input.addEventListener("keydown", (event) => {
    if (list.hidden || items.length === 0) return;
    if (event.key === "ArrowDown") { event.preventDefault(); highlight(active + 1); }
    else if (event.key === "ArrowUp") { event.preventDefault(); highlight(active - 1); }
    else if ((event.key === "Enter" || event.key === "Tab") && (active >= 0 || items.length === 1)) { event.preventDefault(); pick(Math.max(active, 0)); }
    else if (event.key === "Escape") { list.hidden = true; input.setAttribute("aria-expanded", "false"); }
  });
});
