# 042 — On a phone, the menu shows the chosen page, not the chat

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [011](011-list-and-management.md), [041](041-chat-settings-panel-style-and-tempo.md)

## 1. TL;DR

On a phone, choosing a page from the menu shows that page. Today the floating chat opens again on top of it. Tests and a browser check at 375 px confirm the fix.

## 2. Abstract

- **Current state:**
  - Below 640 px the floating chat (dock) covers the whole screen.
  - The browser remembers whether the chat is open (`localStorage`), and every new page opens it again if it was open.
  - Since an owner fix, a *maximized* chat already goes back to the side panel when a link outside the chat is followed. On a phone the side panel is the whole screen too, so that fix changes nothing there.
- **Gap or problem:** the owner's words: "na mobile działa w zasadzie tylko chat, z menu nie da się wybrać skutecznie innych opcji, bo znowu się wyświetla czat".
- **Rationale:** on the phone the menu is the only way to the other pages.

## 3. Objective

**Goals**
- G1. On a phone-width screen (where the chat covers the page), following a link or menu item outside the chat closes the chat, and the chosen page is shown.
- G2. A link inside the chat (for example to an epic) still opens its page. The chat closes for it too on a phone, because otherwise the page cannot be seen.
- G3. After a page change on a phone, the chat stays closed until the owner taps the chat button. On a computer nothing changes: the open chat stays open beside the page.

**Out of scope**
- The chat's look on the phone (spec 041).
- The Director page, which shows the chat as the page itself.

**Success criteria**
- S1. At 375 px with the chat open:
  - the owner opens the menu (after closing the chat, or from a page where the chat is closed), taps Spaces, and sees the Spaces page;
  - the chat button is visible, and one tap opens the chat again.
- S2. At 1280 px an open chat stays open after a menu click, as today.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `chat.js`: dock open state per screen width | to change |
| System | integration test of the dock markup (unchanged), JS test of the rule | to create |

## 5. Functional Domain Changes

- **State:** an open chat comes back on every page → on a phone, it comes back only when the owner opens it.
- **Rules:**
  - R1. "Phone" means the width at which the chat panel covers the page (below 640 px, the same breakpoint as the CSS).
  - R2. A voice conversation that is on when the chat closes this way ends, as with Done. The microphone never keeps listening behind a page the owner cannot see.
  - R3. The rule lives only in the browser; no server data changes.
- **Resilience:** without `localStorage` (private mode) the chat starts closed, as today.
- **Data:** none.

## 6. Critical Path

1. A JS test reproduces the bug: at phone width, a click outside the dock followed by a page change leaves the dock open.
2. Close the dock (and end voice) on navigation at phone width.
3. Browser check at 375 px and 1280 px on the demo data.

Done when S1 and S2 pass.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | at phone width, navigation outside the dock closes it and clears the remembered state | `test/javascript` | commit | at computer width the dock stays open |
| Manual | S1, S2 | browser at 375 px and 1280 px | release | — |

## 8. Expected Outcome

- **Direct effect:** the phone menu works.
- **Measurable effect:** one tap from the menu reaches any page.
- **Side effects:** on a phone the owner opens the chat again after each page change.
- **Rollback:** revert the JS change.

## 9. Additional Information

- **Rejected alternatives:** put the menu above the chat. Rejected because the chat would still cover the chosen page.
- **Sources and questions:** none open.

- **Implementation (2026-11-22):**
  - `chat.js`: `dockAfterClick()` decides what a page change started by a click does to the floating chat. On a phone an open chat closes and voice mode ends; on a computer a maximized chat goes back to the side panel, as before. On a phone a full page load also starts with the chat closed (G3).
  - Found in the browser check:
    - The Team page was 921 px wide on a phone because of the member's role form, so the whole page was zoomed out. The form now keeps within the screen.
    - The floating chat is kept across Turbo visits, so its settings switches stayed on the old choice after a save (also in spec 041). The saved choice is now marked in place.
  - Tests: `test/javascript/dock_test.rb` (4); `chat_dock_test.rb` adapted.
  - Browser check at 375 px on demo data: closing the chat, opening the menu and choosing Spaces shows Spaces with the chat closed; the page is 375 px wide.
