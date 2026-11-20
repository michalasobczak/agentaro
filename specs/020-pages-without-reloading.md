# 020 — Pages without reloading: the conversation keeps going

Status: **draft**
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [017](017-voice-and-streaming.md), [019](019-verifier.md)

## 1. TL;DR

Moving between pages (Calendar, Spaces, Team…) no longer reloads the whole page. Only the page content is replaced, so the floating chat stays alive, with its microphone, voice, streamed reply and verifier: a spoken conversation goes on wherever the user clicks. Done with **Turbo** (Hotwire, the Rails standard). Confirmed by tests and by a voice conversation kept across pages in the browser.

## 2. Abstract

**Current state.** Every link and form loads a new page. The browser then closes the old page with its microphone and audio, so voice mode (spec 017) stops whenever the user clicks Calendar or Spaces.

**Need (owner, 2026-11-20).** "klikam na calendar, spaces… i mówienie się anuluje… powinno być niezależnie, gdzie jestem, na której karcie strony". The owner chose pages without reloading (over a pop-out window).

## 3. Objective

**Goals**
- G1. **Turbo Drive** handles links and forms: the server renders pages as today, and Turbo swaps the body. The address, the back and forward buttons and the page titles work as before.
- G2. **The floating chat is permanent** (`data-turbo-permanent`). It is moved untouched from page to page, together with its state: the microphone, voice mode, the playback queue, the streamed reply and the verifier.
- G3. **Page scripts start on every visit**, not only on the first load (`turbo:load`), and start once per page:
  - `calendar.js` (drag and drop, menus, dialogs), `kanban.js` and `folder_picker.js`;
  - the auto refresh in `app.js`, which no longer reloads the page but asks Turbo to refresh it, so the chat survives;
  - `chat.js` on the Director page.
- G4. **Forms** (sign-in, task forms, space forms, confirmations) keep working. Errors render with status 422, redirects use 303, and `data-confirm` keeps asking.
- G5. **The Director page** (Q1).
- G6. **Fallback:** without JavaScript everything works as today, with full page loads.

**Out of scope**
- Live updates pushed by the server (Turbo Streams); the app keeps polling.
- Offline use.

**Success criteria**
- S1. In voice mode, clicking Calendar, Spaces, a space and an epic keeps the conversation going: the voice is still speaking and the microphone still listening (browser check by the owner and on the host).
- S2. The calendar's drag and drop, menus and new-task dialog, the kanban ordering and the folder suggestions work after arriving by a link, not only after a full load (browser checks).
- S3. All forms work: validation errors show and successful saves redirect (tests and browser).
- S4. The Content-Security-Policy is unchanged: Turbo is served as a first-party file (test).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `turbo-rails` gem; Turbo loaded from the app's own assets | to add |
| System | Layout: the floating chat permanent; page scripts in the body or started on `turbo:load` | to change |
| System | `app.js` (confirm, auto refresh via Turbo), `calendar.js`, `kanban.js`, `folder_picker.js`, `chat.js`: start on every visit, once | to change |
| System | Controllers: failing forms 422, redirects 303 where Turbo needs them | to check |

## 5. Functional Domain Changes

**Rules**
- R1. A page script never binds twice. Document-level listeners are added once and look up the current page's elements when they run.
- R2. A dialog, a drag or a dirty form still blocks the auto refresh (spec 010 owner fix).
- R3. Sign-in, sign-out and session expiry make full page loads, so the chat and its microphone end when the account changes.

**Resilience:** if Turbo fails to load, links and forms work as full page loads.

## 6. Critical Path

Add Turbo → permanent floating chat → page scripts on `turbo:load` (calendar first) → forms and status codes → auto refresh through Turbo → tests → browser checks: voice across pages, calendar, kanban, forms → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | pages and forms with Turbo headers; 422 on errors; CSP unchanged; the floating chat marked permanent | `test/integration/*` | merge | no inline scripts; no outside script sources |
| Manual | voice across pages; calendar, kanban, folder picker after link visits | owner + browser | release | — |

## 8. Expected Outcome

- **Direct effect:** the conversation, spoken or typed, goes on while the user works anywhere in Agentaro. Pages also feel faster.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** one more gem. Page scripts become more complex, because they start on every visit.
- **Rollback:** remove Turbo; pages load fully again.

## 9. Additional Information

- **Rejected alternatives:** a pop-out chat window (the owner chose pages without reloading); a hand-made navigation without Turbo (more code, less tested).
- **Technical debt:** none known yet.
- **External dependencies:** turbo-rails (MIT).
- **Questions:**
  - Q1. **The Director page while the floating chat is talking.** Proposal: the Director page shows the full chat as today. When voice mode is running in the floating chat, it moves to that page as well, so nothing stops, and the page's own chat is hidden until voice mode ends, so you never see two copies of the conversation. [TO BE DETERMINED]
  - Q2. **On a phone the floating chat covers the screen while open.** Proposal: unchanged — close it to use the page; voice mode goes on while it is closed, shown by the pulsing button. [TO BE DETERMINED]
