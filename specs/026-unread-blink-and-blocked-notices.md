# 026 — Unread chat blinks; blocked epics pop up

Status: **closed** 2026-11-20 (the owner's decisions Q1–Q3 in the chat); **implemented** 2026-11-20.
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [016](016-sequential-steps.md), [020](020-pages-without-reloading.md)

## 1. TL;DR

The closed floating chat's button blinks while an answer is unread. When the tab is in the background, its title blinks too. A blocked epic pops up on every page with its reason and Try again, Open epic and Close. It also comes as a macOS notification once the user has allowed it. Closing is remembered on the server until the epic is blocked again. Tests and a browser check confirm it.

## 2. Abstract

- **Current state:**
  - An unread answer shows a small red dot on the chat button.
  - A blocked epic is shown in three places:
    - a system message in the chat;
    - the Blocked column of its space;
    - its own page, where Try again is.
- **Gap or problem:** the owner missed both an unread answer and a blocked epic ("chcę, żeby czat mrugał, jeśli mam coś nieprzeczytanego… żeby wyskakiwał komunikat o tym, że jest coś zablokowanego"). A blocked epic waits until someone happens to look.
- **Rationale:** a stopped epic stops all its work, so it should be noticed at once.

## 3. Objective

**Goals**
- G1. **Blinking chat** (Q1).
  - The closed floating chat's button blinks while an answer is unread, until the chat is opened.
  - While the tab is in the background, a new answer makes the tab title alternate with "(1) New message from <director>", until the tab is shown.
- G2. **Popup for blocked epics** (Q2).
  - Every page shows a notice for each blocked epic whose notice is not closed. Each notice holds the epic, its space and the reason, plus Try again, Open epic and Close.
  - At most 5 notices are shown, newest first.
- G3. **Closing** (Q3).
  - Close stores the time on the epic, so the notice does not come back on any device.
  - Blocking the epic again shows it again.
  - Try again resumes the epic as on its page; the notice goes when the epic is no longer blocked.
- G4. **macOS notification** (Q2).
  - A notice offers "Also show these as Mac notifications". It asks the browser for permission once, on the user's click.
  - When allowed, each new block also comes as a system notification while the tab is in the background, once per block. Clicking it opens the epic.

**Out of scope**
- Notifications for things other than blocked epics.
- Push notifications when no Agentaro tab is open.

**Success criteria**
- S1. With an unread answer, the closed chat's button blinks.
- S2. A blocked epic pops up within about 10 seconds on any page; Close hides it everywhere.
- S3. The epic blocked again pops up again.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `work_items.block_dismissed_at` (migration `20261121127000`) | to create |
| System | `WorkItem#block!` clears it; scope `block_notices` | to change |
| System | `NoticesController` (`GET /notices`, `POST /notices/:id/dismiss`) | to create |
| System | `notices.js`, `#notice-stack` in the layout (kept across Turbo visits) | to create |
| System | `chat.js`: `has-unread` on the launcher, title blink | to change |
| System | `application.css`: blink, notices, placement beside the open chat | to change |

## 5. Functional Domain Changes

- **State:** blocked epics are announced on every page until the user closes them.
- **Rules:**
  - R1. **Blinking button.** It blinks while the chat is closed and an answer newer than the last one seen exists. It stops when the chat is opened. With reduced motion it does not animate; the red dot stays.
  - R2. **Blinking title.** It blinks only while the tab is hidden, and stops when it is shown.
  - R3. **Notices are the user's own.**
    - Only the signed-in user's own blocked epics are listed; another user's cannot be closed (404).
    - The page polls every 10 seconds, every 30 while hidden, and at once when shown again.
  - R4. **Placement.**
    - Notices sit at the top right, or beside the open floating chat, not over it.
    - With the chat maximized or on a phone, they sit at the bottom left.
  - R5. **System notifications.**
    - They are shown only after the user clicks to allow them, and only while the tab is hidden.
    - Each block is shown once per browser (remembered in local storage).
  - R6. **The notice is built safely.** Everything is set with `textContent`, with no inline style or script.
- **Resilience:**
  - When offline, the next poll catches up.
  - If Close fails, the notice shows again on the next poll.
- **Data:** one nullable column.

## 6. Critical Path

1. Migration and model.
2. Controller and routes.
3. Layout and `notices.js`.
4. Chat blinking.
5. Tests.
6. Browser check on demo data.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | listed with reason and links; Close hides; a new block shows again; other users' epics neither listed nor closable; every page has the notice area and script | `test/integration/notices_test.rb` | merge | no inline `style=` or script |
| E2E | notice beside the open chat; Close hides it on the server; a new block shows again; the closed chat's button blinks with an unread answer | browser, demo data, 2026-11-20 | release | — |
| Manual | macOS notification after allowing it | owner | — | — |

## 8. Expected Outcome

- **Direct effect:** blocked epics and unread answers are noticed at once.
- **Side effects:** one small request every 10 seconds per open tab.
- **Rollback:** revert the code. The column can stay.

## 9. Additional Information

- **Rejected alternatives:**
  - Only the chat button blinking, without the tab title (Q1).
  - Notices only inside Agentaro (Q2).
  - Notices that disappear by themselves (Q3).
- **Technical debt:**
  - The notices poll is separate from the chat poll.
  - Try again on a notice uses the same action as the epic page and follows its redirect.
- **Sources and questions (answered by the owner on 2026-11-20):**
  - Q1. Blinking? The button and the browser tab.
  - Q2. Where? Inside Agentaro, plus macOS notifications.
  - Q3. Until when? Until closed; stored on the server for all devices.

## Security analysis (B20), after spec 026

- **Scope.** Notices and Close are limited to `current_user.work_items`. Another user's id gives 404 (test).
- **Requests.** Close and Try again are POSTs with the CSRF token. Polling is a GET that reads only.
- **Rendering.** Titles and reasons come from the user's own data and agents' errors. They are set with `textContent` and truncated to 300 characters, and a link's `href` is built only from server routes.
- **Notifications.**
  - System notifications carry the epic title and reason to macOS; they stay on this computer.
  - Permission is asked only on the user's click.
- **Tools.** Brakeman: 0 warnings. No new gems.
