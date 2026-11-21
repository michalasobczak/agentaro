# 029 — Chat background patterns

Status: **implemented with the proposed defaults** (Q1, Q2 still awaiting the owner's confirmation); release-gate failures (S3 contrast, header overflow) fixed 2026-11-21
Date: 2026-11-20
Depends on: [006](006-responsive-ui.md), [020](020-pages-without-reloading.md), [024](024-conversation-fixes.md), [027](027-work-panel-beside-chat.md)

## 1. TL;DR

Signed-in users can choose Solid, Dots, Grid, Gradient or Animated in the Director chat. Verify that the same account preference survives reloads, applies to both chat views and keeps messages readable in light and dark palettes.

## 2. Abstract

- **Current state.** `directors/show.html.erb` and `directors/_dock.html.erb` render the shared `directors/_chat.html.erb`. Its `.chat-scroll` has an opaque `--bg` fill. The message stream contains date labels and bubbles with their own surfaces. `chat.js` handles messages, scrolling, streaming and the dock lifecycle. Turbo retains the dock element across visits.
- **Gap.** The message viewport has one appearance. The dock's browser storage handles UI state such as an unsent draft and has no account-wide appearance setting.
- **Rationale.** A single account preference gives both views the same appearance across conversations and devices.
- **Decision history.** Commit `72c6c29` introduced `users.theme` with an `auto` database default, a model allowlist, an authenticated account PATCH and a server-rendered `body[data-theme]`. In `application.css`, explicit Light and Dark override the OS preference. Auto follows `prefers-color-scheme`. Spec [028](028-animated-page-background.md) reserves the page layer for its own animation and leaves the chat viewport opaque. Either spec can ship first.

## 3. Objective

**Goals**

- G1. Offer an account-wide background selector in the full Director chat and its floating dock, including maximized and mobile layouts.
- G2. Keep all patterns readable in both effective palettes and render a static variant when reduced motion is requested.

**Out of scope**

- Custom images or patterns, per-conversation and per-space settings, archived conversations, and configuration of the page background in spec 028.

**Success criteria**

- S1. Both chat views offer five labeled choices. Solid is selected for existing and new accounts without a saved preference. The selector shows the persisted value on first render.
- S2. A successful save applies without a full page reload and survives reload, Turbo navigation, starting a new conversation and reopening the account in another session. Another user's preference is independent. Changing the pattern preserves scroll position, unsent text and any active reply.
- S3. Normal-sized message text and viewport labels meet at least 4.5:1 against their rendered backing in both palettes, including at the lightest and darkest points of each pattern. The pattern stays behind message surfaces. Bubble boundaries remain visible and the selector has visible keyboard focus.
- S4. Animated moves only in the chat viewport. Reduced motion immediately stops its movement and leaves a static gradient, including when the OS preference changes with the chat open. The saved choice stays Animated.
- S5. With spec 028 enabled, its page effect is masked inside the chat viewport. With either spec installed independently, its own effect and motion preference work.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `app/views/directors/_chat.html.erb` — selector rendered in both chat views | to change |
| System | `app/views/layouts/application.html.erb` — server-rendered account pattern on body | to change |
| System | `app/assets/stylesheets/application.css` — selector, scoped pattern palettes and reduced motion | to change |
| System | `app/assets/javascripts/chat.js` — save, feedback and synchronize both selectors through Turbo visits | to change |
| System | `config/routes.rb`, `app/controllers/account/chat_backgrounds_controller.rb` — singular account PATCH | to change / to create |
| Data | `app/models/user.rb`, new `db/migrate/*_add_chat_background_to_users.rb`, `db/schema.rb` — allowed values, default and persistence | to change / to create / to change |
| Tests | `test/models/user_test.rb`, `test/integration/chat_background_test.rb` — model and request/rendering coverage | to change / to create |
| Tests | `test/integration/theme_test.rb`, `director_chat_test.rb`, `layout_test.rb`, `work_panel_test.rb` (integration paths) — regression coverage | exists |
| Organization | `README.md`, `CHANGELOG.md` — document status and verified implementation | to change |

## 5. Functional Domain Changes

- **State.** One solid viewport becomes a selectable viewport, with one preference per user.
- **R1. Patterns.** Solid (`solid`) uses the existing plain fill. Dots (`dots`) adds subtle repeated dots, Grid (`grid`) adds thin crossing lines, Gradient (`gradient`) adds a static soft tonal transition, and Animated (`animated`) moves a soft gradient slowly with no flashes. Use first-party CSS over an opaque `--bg` base.
- **R2. Selector.** Place a compact native select labeled “Chat background” in the chat header, before the action buttons. On narrow screens and in the dock header it can wrap to its own row within the header. Show readable text labels and the saved selection. Support keyboard operation and an announced save error. Keep the control outside the message stream and composer.
- **R3. Data.** Mirror the theme setting with `users.chat_background`, a non-null string with database default `solid`, and a model inclusion validation. Existing accounts get Solid on migration. Render only an allowlisted value in `body[data-chat-background]`, falling back to Solid for an absent or unrecognized value. Apply the attribute's CSS rules solely inside `.chat-scroll`.
- **R4. Save.** The signed-in account PATCH uses `current_user`, Rails CSRF protection and exact allowlist validation. JSON success returns the persisted value. A missing, non-string or unknown value returns 422 and preserves the stored preference. Send from `chat.js` with the existing same-origin CSRF convention. Apply the confirmed choice to the body and both selector instances. During a save, prevent overlapping submissions in the tab. On failure, restore the last confirmed selection and let the user retry. For concurrent successful saves across sessions, the last committed write wins. A fresh page request reads the persisted value.
- **R5. Turbo.** Initialize from the server-rendered body and synchronize the retained dock selector after Turbo renders. Update the document state after saving without replacing the chat. Turbo snapshot restoration in the same tab must preserve the most recent confirmed choice. Fresh visits use the server value.
- **R6. Contrast and motion.** Place the decorative layer beneath the message stream with no pointer or focus targets. Use the effective palette selected by the existing light, dark and Auto rules. Keep bubbles and direct-on-pattern labels readable, including timestamps, formatted text and pending/failed states. Where a translucent surface fails S3, adjust its local backing or foreground and preserve the state cue. A chat-scoped CSS reduced-motion rule disables the background animation while keeping its static composition.
- **R7. Page boundary.** The chat owns its viewport, chat-specific color tokens and keyframes. Spec 028 owns its separate page layer. The composer, header and work panel retain their existing component surfaces.

## 6. Critical Path

1. Owner reviews the draft and resolves Q1–Q2.
2. Add and test the schema default, validation and account endpoint.
3. Render the selector and preference, connect save and Turbo synchronization, and add the five scoped treatments.
4. Run the control gates with isolated development browser data. Run Rondo B20 across this and prior specs, revalidate project context and record results in README and CHANGELOG. Restart the owner's instance after changing runtime files, per project instructions.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | Exactly five values are valid and new accounts default to Solid | Extend model tests and verify the migration default with a pre-existing user | Merge | Fail on invalid model values or missing default |
| Integration | Each valid choice persists and renders in both views; only the current account is updated | Test PATCH, database reload, Director and dock selectors/body attribute, another account, a separate signed-in session and invalid inputs | Merge | Fail on anonymous mutation, cross-account update, malformed values or loss of the stored choice |
| Contract | Theme and pattern are independent and selector meets project CSP rules | Assert theme and pattern updates preserve each other's values, and extend markup checks for labels, selection and absence of inline style/script. Review Rails CSRF protection | Merge | Fail on raw request values reaching CSS, CSP relaxation or an unprotected write |
| E2E | Save and navigation preserve the live chat | Exercise reload, Turbo forward/back, new conversation, dock reopening/maximize, keyboard operation and simulated request failure during a draft or reply | Release | Fail on stale selection after restoration, draft/scroll loss, duplicate chat handlers or silent failure |
| Manual | All five patterns are readable and correctly scoped | Check explicit Light/Dark against opposing OS modes and Auto in both palettes. Measure contrast on rendered surfaces, including extrema of Animated, and inspect desktop/mobile and dock layouts. Toggle reduced motion live. Repeat with the page effect enabled when spec 028 is available | Release | Fail on contrast below S3, overflow, movement under reduce or page background bleeding through chat |

## 8. Expected Outcome

- **Direct effect.** Both chat views reflect a single saved background preference.
- **Measurable effect.** Five verified patterns, one persisted account value, and passing contrast, motion and navigation gates.
- **Side effects.** The selector can add a row to compact headers. The account update follows the existing audit and data changelog behavior.
- **Rollback.** Remove the feature's UI, endpoint and styling to restore the solid viewport. Retain the column for a reversible rollback or reverse the migration if dropping saved choices is approved.

## 9. Additional Information

- **Rejected alternatives.** Browser-only persistence would lose the preference on another device. A page-wide pattern would collide with spec 028's layer.
- **Technical debt.** The effective palette branches currently live in the shared stylesheet. Keep chat tokens beside the corresponding theme rules.
- **External dependencies.** None.
- **Sources.** [README](../README.md), [CHANGELOG](../CHANGELOG.md), [manifesto](../MANIFESTO.md), [chat partial](../app/views/directors/_chat.html.erb), [chat runtime](../app/assets/javascripts/chat.js), [stylesheet](../app/assets/stylesheets/application.css), [theme controller](../app/controllers/account/themes_controller.rb), [theme tests](../test/integration/theme_test.rb).
- **Q1.** [TO BE DETERMINED] Does the owner approve Solid as the default and the labeled native select in the shared header, including its own row where space is limited?
- **Q2.** [TO BE DETERMINED] Does the owner approve the proposed 4.5:1 gate and a slowly moving gradient that becomes static with reduced motion?

## Release-gate fixes (2026-11-21)

Reproduced on demo data in the browser (1280 px window, both palettes), then fixed:
- **Failed-send error, 1.1:1.** The error replaces the time of a failed user message and kept the user bubble's light time colour on the pale red fill. It now uses `--bad-text`, as does the failed text. Inline code there has an opaque `--surface` backing. Measured: 6.5:1 light, 7.3:1 dark; code 7.4:1 / 7.9:1.
- **System and verifier names (light 4.3:1 and 4.1:1).** New text tokens for the soft fills: `--ok-text`, `--warn-text`, `--bad-text` (darker in light; in dark the same or lighter). Measured: system 6.5:1 / 7.1:1, verifier 5.9:1 / 7.5:1.
- **Clipped header.**
  - Cause 1: a floating chat left open on another page kept its room on the Director page (`margin-right` on `.main`), though it is hidden there. The chat shrank to about 110 px beside the work panel. Now no room is kept while the full chat is shown, except in voice mode, when the floating chat is the one shown.
  - Cause 2: below 760 px of chat width the selector now takes its own row; before, only below 470 px.
  - Measured: no header overflow at 375, 750, 1280, 1440 and 1920 px, Director page and floating chat, normal and maximized.
- **Tests.** `chat_background_test.rb`:
  - contrast of these pairs computed from the palette tokens, in both palettes;
  - the rules that use them;
  - the header and dock rules.

