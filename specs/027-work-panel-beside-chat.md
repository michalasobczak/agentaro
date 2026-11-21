# 027 — Work panel beside the director chat

Status: **closed** 2026-11-20 (the owner's decisions Q1–Q3 in the chat); **implemented** 2026-11-20.
Date: 2026-11-20
Depends on: [013](013-projects.md), [016](016-sequential-steps.md), [020](020-pages-without-reloading.md)

## 1. TL;DR

On the Director page, a panel to the right of the chat stacks every active space. Each space lists its epics in progress (new, planned, running, blocked), each with its steps and their states. Running epics and steps blink, and a space with nothing planned or in progress says so. The panel redraws itself every 5 seconds. Tests and a browser check confirm it.

## 2. Abstract

- **Current state:**
  - The Director page is the chat alone.
  - To see what goes on, the user opens each space's board.
  - The chat strip of spec 023 shows only who is busy.
- **Gap or problem:** the owner wants the whole picture beside the conversation: "obok chatu, po prawej, stacki ze space i zadań… nazwa projektu, pod spodem epici i zadania, co które są w realizacji mają mrugać… te, które nie mają… niech info, że nie ma".
- **Rationale:** talking to the director is easier while seeing what the director manages.

## 3. Objective

**Goals**
- G1. **Place** (Q1). On the Director page, the chat is on the left and the panel on the right. Under 900 px the panel is below the chat. The floating chat on other pages does not change.
- G2. **What it shows** (Q2).
  - For each space, the epics that are new, planned, running or blocked: running first, then blocked, planned and new, at most 20 per space.
  - Under each epic, the steps of its current plan, with the number, title and state; the agent's name is in the tooltip.
  - Finished and cancelled epics are left out.
- G3. **Empty spaces.** A space with no such epic shows "Nothing planned or in progress."
- G4. **Which spaces** (Q3). Only active spaces, in alphabetical order.
- G5. **Running blinks.** The state of a running epic and of a running step blinks. Colours follow the board:
  - planned: accent;
  - running: amber;
  - blocked: red;
  - succeeded steps: green;
  - failed or timed-out steps: red.
- G6. **Live.** The panel redraws itself every 5 seconds while the tab is visible, and only when something changed.

**Out of scope**
- Actions in the panel; links go to the space and the epic.
- The panel beside the floating chat (Q1).

**Success criteria**
- S1. On the owner's Director page, Nomystria shows the research epic with its 5 steps, step 4 blinking. Spaces with no work say so.
- S2. When a step ends, the panel changes within about 5 seconds, without reloading the page.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `WorkPanel.for(user)`: the data, once for the page and for the JSON | to create |
| System | `GET /director/work` (`DirectorsController#work`) | to create |
| System | `directors/_work_panel.html.erb`, `work_panel.js`, `.director-layout` in `directors/show` | to create |
| System | `application.css`: layout, panel, blink; the floating chat hidden on this page as before; notices at the bottom left here | to change |
| Data | none | — |

## 5. Functional Domain Changes

- **State:** the Director page shows the work beside the chat.
- **Rules:**
  - R1. **The user's own work.** Only the signed-in user's spaces and epics are shown.
  - R2. **The current plan.** Steps shown are those of the current plan (`active_step_from`); a moved or replanned epic does not show its retired steps.
  - R3. **Safe drawing.** The server draws the panel first; `work_panel.js` redraws it from JSON, with `textContent` only and no inline style.
  - R4. **Motion.** With reduced motion, nothing blinks; the states stay as text and colour.
  - R5. **Room for the panel.** The floating chat stays hidden on this page. Notices of spec 026 sit at the bottom left here, over the chat, so they do not cover the panel.
  - R6. **Sides in voice mode** (fix 2026-11-21). When voice mode (spec 020 G5) hides the page chat, the panel stays in the right column, and from 900 px the floating chat takes the page chat's place on the left. Before the fix the panel slid to the left and the floating chat opened on the right. Second fix (2026-11-21, owner: "nie widzę zadań po prawej stronie od czatu, tylko w trybie voice"): this also holds when the floating chat was maximized earlier — the choice is remembered in the browser, and the maximized panel covered the work panel.
- **Resilience:** offline, the next poll catches up.
- **Data:** no change.

## 6. Critical Path

1. `WorkPanel` and the route.
2. The partial and the layout.
3. Script and styles.
4. Tests, then a browser check at 1440 px and on a phone.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | active spaces only; epics in progress, running first, with steps; finished left out; empty space note; page carries panel and script; JSON equals the data | `test/integration/work_panel_test.rb` | merge | other users' epics never appear; no inline `style=` |
| E2E | panel beside the chat at 1440 px; below it on a phone without horizontal scroll; changes within 5 s | browser, demo data, 2026-11-20 | release | — |

## 8. Expected Outcome

- **Direct effect:** what the team is doing, per space, is visible during the conversation.
- **Side effects:** one small request every 5 seconds while the Director page is visible.
- **Rollback:** revert the code. There is no data change.

## 9. Additional Information

- **Rejected alternatives:**
  - The panel also beside the floating chat (Q1).
  - Showing epics finished today (Q2).
  - Showing archived spaces (Q3).
- **Technical debt:** the panel polls on its own instead of riding on the chat's poll.
- **Sources and questions (answered by the owner on 2026-11-20):**
  - Q1. Where? The Director page, to the right of the chat.
  - Q2. What? Epics in progress with their steps.
  - Q3. Which spaces? Active only.

## Security analysis (B20), after spec 027

- **Scope.** `WorkPanel` reads only `current_user` spaces and epics. A test checks that another user's epic never appears.
- **Rendering.** Titles come from the user's data and the director's plans; ERB escapes them, and the script uses `textContent`. Links come from server routes.
- **Load.** One indexed query per poll, with at most 20 epics per space.
- **Tools.** Brakeman: 0 warnings. No new gems.
