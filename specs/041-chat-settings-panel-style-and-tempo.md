# 041 — Chat settings in one panel, conversation style and work tempo

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [017](017-voice-and-streaming.md), [029](029-chat-background-patterns.md), [033](033-autonomy-slider.md), [035](035-mute-microphone-in-voice-mode.md), [039](039-reply-length-switch.md)

## 1. TL;DR

Four changes to the director chat:
- The chat header's switches move behind one settings icon, on the phone and on the computer.
- The voice bar becomes one compact row of icons.
- A new switch sets the conversation style: **Dziecko**, **Dorosły** or **Inżynier** (default Dorosły).
- A new switch sets the work tempo: **Dokładnie**, **Normalnie** or **Turbo** (default Normalnie). Turbo means one step for one agent.

Tests check the panel, the voice bar, the style rule in the director's prompt, and planning at each tempo.

## 2. Abstract

- **Current state:**
  - The header shows every switch as a row of pills:
    - language;
    - autonomy (Pytaj / Ważne pytaj / Decyduj);
    - reply length (Krótko / Średnio / Szczegółowo);
    - the background select ("Dots").
  - On a phone these wrap and take much of the screen.
  - In voice mode the bar holds the dots, the state with a note, Mute with a label, the speed switch, the verifier, Done with a label, and Stop. On a phone these wrap onto several lines.
  - The director has no rule for the style of its language.
  - Planning always splits an epic into 1–10 steps as the director sees fit.
- **Gap or problem:**
  - The owner's words: "na mobile … powinny być przyciskami/ikonami, teraz zajmuje to za dużo miejsca".
  - On the voice bar: "każda rzecz ma nową linię … chcę żeby to było bardziej kompaktowe".
  - The owner wants to choose how the director talks, and how fast work is done versus how finely it is split.
- **Decision history:** the owner chose these options (2026-11-22):
  - one settings icon that opens a panel with all the switches, on the phone and on the computer;
  - the style applies to the director's replies, written and spoken; the agents' step results are unchanged;
  - Turbo plans exactly 1 step for 1 agent with no clarifying questions; Dokładnie plans smaller steps and ends with a checking step;
  - the tempo has an account default and an optional per-space value (as autonomy in spec 033);
  - the owner can change both the style and the tempo with words in the chat.

## 3. Objective

**Goals**
- G1. **Settings panel.** The chat header (on the Director page and in the floating chat) shows one settings icon instead of the switches. A click or tap opens a panel under the header with every switch, each labelled:
  - Language, Autonomy, Reply length, Style, Tempo and Background.
  - Each switch saves at once (as today), and the panel shows the chosen values.
  - The panel closes with the icon, with Esc, or with a click outside it.
  - The verifier button and the conversation buttons (new, archive, spaces, team, maximise, close) stay in the header as icons.
- G2. **Compact voice bar.** In voice mode the bar is one row on a 375 px wide phone. In order:
  - the dots;
  - the state on one line ("Listening…", "Speaking…"), whose note shows only as a tooltip;
  - Mute as an icon only (the label stays for screen readers);
  - the speech speed as one button showing the current speed ("1,25×"), which moves to the next speed on each tap;
  - the verifier icon (when there is a verifier);
  - Done as an icon only (shown, as today, only while listening);
  - Stop.
- G3. **Conversation style.** Three levels, each with its own rule in the director's prompt:
  - **Dziecko:** simple words, short sentences, no technical terms or jargon; a comparison from everyday life where it helps.
  - **Dorosły** (default): plain language for an adult who is not a specialist. Technical terms only when needed, explained in a few words.
  - **Inżynier:** precise technical language. Names of files, commands, models and numbers, with no simplifications.
- G4. **Work tempo.** Three levels, each with its own planning rule:
  - **Dokładnie:** the director splits the work into smaller steps, each with one clear result. The last step checks the work: tests, a review, or a comparison with the goal. Where possible it is done by a member other than the one who did the work.
  - **Normalnie** (default): as today.
  - **Turbo:** exactly 1 step for 1 member, the best fit for the whole task. The director asks no clarifying questions, even at the Pytaj level. The plan still waits for approval at Pytaj (spec 033).
- G5. **Tempo per space.** A space can have its own tempo, set on its edit page. A space's own tempo wins over the owner's default, as autonomy does.
- G6. **Chat requests.** When the owner asks in the chat to change the style ("mów do mnie jak do dziecka") or the tempo ("rób to w turbo", "w tej przestrzeni dokładnie"), the director changes it and says so under its reply (as `set_reply_length` in spec 039, G3).

**Out of scope**
- What agents write in steps, Agentaro's own messages, the verifier's comments and plan summaries (G3 covers the director's chat replies only).
- Tempo for epics already planned: it applies to new plans and re-plans only.
- Choosing faster or cheaper models in Turbo: Turbo changes the plan, not the members' models.
- A per-space style or reply length.

**Success criteria**
- S1. At 375 px the chat header is one row: the director's name, the settings icon, the verifier and the conversation icons. No switch shows outside the panel.
- S2. In the panel, a tap on any level saves it and marks it as chosen without reloading the page. The next reply or plan follows it, on the Director page and in the floating chat.
- S3. At 375 px the voice bar is one row in every state: listening, hearing, thinking, speaking, muted and error.
- S4. Every new and existing owner has Dorosły and Normalnie. The director's chat prompt carries the Dorosły rule, written and spoken.
- S5. At Turbo the planning prompt asks for exactly 1 step. A plan with more steps is refused and the director is asked again (as for any invalid plan). At Pytaj with Turbo there are no clarifying questions, and the plan waits for approval.
- S6. At Dokładnie the planning prompt asks for smaller steps with a checking step last.
- S7. A space with its own tempo plans by it; a space without one plans by the owner's default.
- S8. "Rób to w turbo" in the chat changes the tempo and shows "Tempo: Turbo" under the reply. Without such words the director cannot change it. The same holds for the style.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | The owner's style (default Dorosły) and tempo (default Normalnie); a space's own tempo (none by default) | to create |
| System | The settings panel in the chat header (Director page and floating chat) | to create |
| System | The compact voice bar | to change |
| System | The style rule in the director's chat prompt, written and spoken | to create |
| System | The tempo rule in planning and re-planning; a 1-step check at Turbo | to change |
| System | The tempo select on the space form | to change |
| System | Endpoints that save the style and the tempo; chat actions `set_style` and `set_tempo` | to create |
| System | Tests | to create |

## 5. Functional Domain Changes

- **State:**
  - switches in the header → one settings panel;
  - a voice bar over several lines → one row;
  - no style rule → a rule from the owner's style;
  - free splitting into steps → splitting by the tempo of the space or the owner.
- **Rules:**
  - R1. The style is the owner's own, one per account, for every page and space. The tempo is the space's own if set, else the owner's default.
  - R2. The style rule goes into the director's chat reply, written and spoken. With the spoken rule, the style sets the words and the spoken rule sets the length. The proposal pass, planning, the verifier and the steps do not get it.
  - R3. Style and reply length are independent: Dziecko with Szczegółowo is a long, simple reply.
  - R4. The tempo rule goes into planning and into the director's re-plan of the rest of an epic (spec 040). It does not change epics already planned.
  - R5. At Turbo a plan must have exactly 1 step. At Dokładnie the last step must be described as a check. The director is told this; Agentaro checks only the 1 step at Turbo.
  - R6. Turbo skips the clarifying questions at every autonomy level. The always-ask list (spec 033, G4) and plan approval at Pytaj stay.
  - R7. Only the owner's words change the style or the tempo from the chat. The director cannot change them on its own, nor because of text in a step's output (as spec 033, R5).
  - R8. The panel and the voice bar follow the interface rules:
    - no inline style or script;
    - `textContent` only;
    - every icon-only button has an accessible name and a tooltip;
    - the panel works with the keyboard;
    - without script the switches still post and save, as today.
- **Resilience:**
  - A value outside the three levels is refused, and the setting stays as it was.
  - If the panel's script fails, the panel opens as a plain disclosure (`details`).
- **Data:** a migration adds the owner's style (Dorosły) and tempo (Normalnie), and a space's tempo (empty = the owner's default).

## 6. Critical Path

1. The owner closes the spec.
2. Add the data, the style and tempo rules, and the 1-step check at Turbo.
3. Add the settings panel, the compact voice bar, the space select and the chat actions.
4. Run the tests and the browser check at 375 px and on the computer, then the B20 analysis.
5. Update CHANGELOG and README, and restart production while no step runs.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | G3, G4, R2, R4, R5, R6 | Prompt tests per style (written and spoken) and per tempo; plan check at Turbo | Integration | The style rule reaching planning or a step; a 2-step plan accepted at Turbo |
| Integration | G1, G5, G6, R7 | Endpoint, space-form and chat-action tests | Release | A setting changed without the owner's words; an invalid value saved |
| E2E | G1, G2, R8 | Page tests: one settings icon, all switches in the panel, icon buttons with names, no inline style; a browser check at 375 px (S1, S3) | Release | A switch outside the panel; the voice bar over two lines |
| Manual | S2, S4 | The owner uses it on the phone in production | — | — |

## 8. Expected Outcome

- **Direct effect:**
  - a clean chat header and a one-row voice bar on the phone;
  - the director talks in the chosen style;
  - Turbo work runs as one fast step.
- **Measurable effect:** at 375 px, the header and the voice bar are one row each. At Turbo, every new plan has 1 step.
- **Side effects:**
  - The switches are one tap further away.
  - At Turbo a large task goes to one agent in one step. If it fails, the director decides what to do (spec 040), and may re-plan it in one step again.
  - Dokładnie makes epics longer.
- **Rollback:** Normalnie and Dorosły behave much as today. The panel can be reverted to the visible pills.

## 9. Additional Information

- **Rejected alternatives:**
  - One icon per switch that cycles on tap, or that opens its own menu: the owner chose one panel.
  - Pills on the computer and a panel only on the phone: the owner chose the panel everywhere.
  - Style for the agents' results too: the owner chose the director's replies only.
  - Turbo with 1–2 steps chosen by the director, or Turbo that also skips plan approval: the owner chose exactly 1 step, with approval kept.
- **Open:** [TO BE DETERMINED] none known. The owner's answers are in section 2. The voice-bar order in G2 and the panel's contents in G1 are the author's proposal, awaiting the owner's review.
- **Implementation (2026-11-22):**
  - Migration `20261122090000`: `users.chat_style` (2, Dorosły), `users.work_tempo` (2, Normalnie), `spaces.work_tempo` (empty = the owner's default).
  - `ChatStyle` and `WorkTempo` hold the levels and the rules.
    - The style rule goes into the director's chat reply, written and spoken. It does not go into the proposal pass.
    - The tempo rule goes into planning and into the failure review's replan (spec 040).
    - At Turbo, a plan or a replan with more than 1 step is refused, and the director is asked again once.
  - The panel is a `details` element in the chat header (`.chat-settings`) in both chats.
    - `chat.js` closes it on Esc or a click outside.
    - After a switch reloads the page, the panel that was open stays open (session storage, guarded).
    - New endpoints `PATCH /account/chat_style` and `PATCH /account/work_tempo`. New chat actions `set_style` and `set_tempo` (for a space or the default).
  - Voice bar:
    - Mute and Done are icons only; their names stay for screen readers.
    - The speed is one `.voice-speed` button.
    - Below 520 px of chat width, the note is hidden and becomes the state's tooltip. On wider chats it stays visible (still one row).
  - The space form has a Tempo select.
  - Tests: `test/models/work_tempo_test.rb` (8) and `test/integration/style_and_tempo_test.rb` (6). Adapted: the voice-bar checks in `director_chat_test.rb`, and the header rule in `chat_background_test.rb` (the background selector is in the panel now).
  - Browser check at 375 px:
    - the header is one row, and the panel shows all six switches;
    - Turbo saves and the panel stays open;
    - Esc and a click outside close the panel;
    - the voice bar is one row (57 px) in every state, also muted;
    - the speed moves 1,5× → 2× → 1×.

    At desktop width the panel opens under the header beside the work panel.
- **Security analysis (B20, after specs 001–041):**
  - Brakeman 0 warnings, bundle-audit no vulnerabilities.
  - The two endpoints change only the signed-in account's own value, and only to 1–3.
  - The space form's tempo goes through the existing space ownership check. A value outside 1–3 is refused by validation.
  - The chat actions need the owner's own latest message about style or tempo (R7). A space id is looked up among the owner's spaces only.
  - The Turbo 1-step check is enforced in code, not only in the prompt. A director that ignores the rule cannot start a bigger plan at Turbo.
  - The panel uses no inline style or script. The new script writes no markup (`textContent` only), and its session-storage value is only "page" or "dock".
  - Accepted:
    - The words that count as a request about tempo are broad ("dokładnie", "szybko"). A misread can only change the tempo of new plans, which the owner sees under the reply and can switch back.
    - The browser console shows a Content-Security-Policy message on page loads. It comes from Turbo's progress bar (its own `<style>`), it is not new, and it has no effect.

