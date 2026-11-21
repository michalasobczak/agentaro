# 028 — Animated page background

Status: **implemented with the proposed defaults** (Q1, Q2 still awaiting the owner's confirmation)
Date: 2026-11-20
Depends on: [006](006-responsive-ui.md), [020](020-pages-without-reloading.md), [026](026-unread-blink-and-blocked-notices.md), [027](027-work-panel-beside-chat.md)

## 1. TL;DR

Add a slow, low-contrast background to the Agentaro page, behind its interface. Verify that the page follows the selected theme and reduced-motion preference and that both forms of the Director chat keep their own background.

## 2. Abstract

- **Current state.** `app/views/layouts/application.html.erb` loads local styles and renders the responsive sidebar/top bar, main content, floating chat and notices. `application.css` holds the layout, palette and component surfaces. Calendar-specific styles and generated grid positions live in `calendar.css` and `calendar_grid.css`.
- **Current theme.** The sidebar and phone menu share `layouts/_theme_switch.html.erb`. `Account::ThemesController` validates and saves Auto, Light or Dark to `users.theme`. The application layout emits `body[data-theme]`, which Turbo replaces on visits. Explicit Light/Dark take precedence over the OS. Auto follows `prefers-color-scheme`. The separate `layouts/auth.html.erb` uses `body.auth`, the system palette and static gradients.
- **Current surfaces.** The body uses `--bg`. The shared Director and floating chat message viewport `.chat-scroll` paints its own opaque `--bg`. Chat headers, composers, cards and the work panel use `--surface`. The sidebar and mobile navigation have their own surfaces.
- **Rationale and related work.** The page currently has a flat background in the application layout. The planned Agentaro epic *Wybór wzorów tła w czacie* proposes a saved per-user choice (examples include solid, dots, grid, gradient and animated), readable in both themes. Give that epic ownership of the message viewport so either change can ship independently.

## 3. Objective

**Goals**

- G1. Move soft gradients slowly behind the layout wherever the page background is exposed.
- G2. Follow the effective light or dark palette and render a static background whenever reduced motion is requested.
- G3. Preserve chat surfaces, panel readability and normal interaction on desktop and mobile.

**Out of scope**

- Chat pattern selection, persistence and changes to chat markup, theme settings or layout dimensions.
- Additional animation controls and changes to existing component animations.

**Success criteria**

- S1. Home, Calendar, Spaces and Director have a viewport-wide background that stays behind the layout during scroll and Turbo visits. The main chat, floating chat (including maximized/mobile) and work panel retain their opaque surfaces. Existing menus, input, calendar drag and notices remain usable.
- S2. Explicit Light and Dark work against the opposite OS preference. Auto follows both system modes. Reduced motion removes the background animation on initial load and when toggled with the page open, leaving a static gradient.
- S3. The gradients have no sharp edges or flashes. Ordinary text, muted text and links directly over the page field meet a proposed minimum contrast of 4.5:1 against the base and the lightest/darkest rendered gradient regions under each theme. The effect introduces no horizontal overflow at 375, 768 or 1440 CSS px.
- S4. Only transform and optionally opacity vary per frame. In an idle-page performance trace, the effect introduces no recurring layout or full-viewport paint attributable to the animation after initial rasterization.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `app/assets/stylesheets/application.css` — page-only palette, fixed pseudo-element, keyframes and reduced motion | changed |
| System | `app/views/layouts/application.html.erb`, `app/views/layouts/auth.html.erb` — existing body selectors support a CSS-only implementation | exists |
| System | `app/views/directors/`, `calendar.css`, generated `calendar_grid.css` — regression surfaces | exists |
| Tests | `test/integration/theme_test.rb` — cover Light and return to Auto as well as the existing Dark and invalid-value cases | changed |
| Tests | `test/integration/page_background_test.rb` — stylesheet contract: one fixed layer, `z-index: -1`, `pointer-events: none`, transform-only keyframes, reduced-motion rule, both palettes, opaque `.chat-scroll`; hook only on application pages | added |
| Tests | `test/integration/layout_test.rb`, `director_chat_test.rb`, `work_panel_test.rb`, `notices_test.rb`, `calendar_test.rb` (integration paths relative to `test/integration/`) — reuse existing regression coverage | exists |
| Organization | `README.md`, `CHANGELOG.md` — record implementation, test and review outcomes | to change |
| Data | Preferences, schema and migrations | exists |

## 5. Functional Domain Changes

- **State.** The page gains an ambient background. Cards, navigation, chat and other opaque surfaces mask it within their bounds.
- **R1. Theme.** Keep `--bg` as the fallback and chat base. Use page-specific color tokens in the existing light and dark branches. Proposed light palette: indigo `#6366f1` and cyan `#22d3ee` over `#f4f5f9`, with peak alpha 0.08 and 0.06. Proposed dark palette: lavender `#8b85ff` and muted teal `#38b9bd` over `#0e1018`, with peak alpha 0.12 and 0.08. Tune at review or lower alpha if S3 fails.
- **R2. Motion.** Use two broad radial gradients fading to transparent on one fixed `body::before`. Translate by at most 4% per axis with a proposed 60-second eased alternating animation. Size the layer with enough overscan to cover the viewport throughout the motion. Use `animation: none` under `@media (prefers-reduced-motion: reduce)` and keep a static composition. CSS handles the effect without per-frame JS, animated background-position, blur filters or network assets.
- **R3. Stacking and input.** Use `isolation: isolate` on the owning body and `z-index: -1` on the pseudo-element, above the body fill and beneath its content. Set `pointer-events: none`. Keep the existing overlay order and avoid transforms or overflow clipping on body and layout wrappers. The pseudo-element adds no focus target or screen-reader content.
- **R4. Chat boundary.** Leave `.chat-scroll` opaque in both Director and floating chat. The pattern epic can later paint a pattern on that local surface over its opaque base, including when the pattern itself uses transparency. Page-specific tokens are consumed only by the page layer. Each feature owns its own motion and reduced-motion behavior.
- **R5. Authentication.** Implemented: application pages only (`body[data-theme]`); the sign-in layout keeps its static gradients until Q1 is answered. [TO BE DETERMINED] Q1 proposes applying the same layer to the auth layout, using its existing OS-driven theme and replacing the current static auth gradients with the shared composition.
- **Resilience and data.** Existing page fill remains available if the effect is unsupported. The animation needs no service, stored state, migration or navigation hook.

## 6. Critical Path

1. Owner reviews the draft and resolves Q1 and Q2.
2. Add the page palette and isolated background to `application.css`. Retain the current chat surface rules.
3. Extend theme integration coverage and execute the control gates, including a browser pass on disposable development data per `AGENTS.md`.
4. Run the Rondo B20 security review across this and prior specs, including CSP and UI layering. Revalidate specs, README and CHANGELOG against code and tests. Record results. Restart the owner's instance after changing assets it uses, per `AGENTS.md`.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | CSS-only behavior has no Ruby unit to add | Review keyframes and their consumers | Review | Reject new frame loop or keyframes that change layout, paint properties or filters |
| Integration | Auto → Dark → Light → Auto persists across pages and invalid values preserve the last choice | Extend `ThemeTest`. Run `bin/rails test`, including existing layout, chat, work panel, notices and Calendar coverage | Merge | Fail on wrong `data-theme`, missing active control or broken component assertions |
| Contract | Decorative layer uses first-party CSS, has reduced-motion handling and preserves the local chat base | Review CSS plus existing no-inline-style/script assertion in `LayoutTest` | Merge | Fail on CSP changes, hit-testable decoration or page styles applied to `.chat-scroll` |
| E2E | Effective theme, layer order and reduced motion work during navigation | In the browser, emulate both OS palettes and toggle reduced motion in-place. Inspect `getComputedStyle(document.body, "::before")`, check that the transform changes in normal mode and that animation is absent in reduced mode. Switch theme via Turbo with chat open. Exercise keyboard focus, calendar drag, mobile menu, dock and notices | Release | Fail on duplicate layers, input interception, chat state loss or motion under reduce |
| Manual | Subtle, readable and stable on desktop, tablet and phone | Compare light/dark screenshots at 375, 768 and 1440 px. Sample exposed text and gradient extrema for S3. Inspect both chats and the work panel. Compare idle traces with the effect enabled and disabled under the same conditions. Check auth routes if Q1 includes them | Release | Fail on visible movement through chat or panels, clipped UI, added overflow, poor contrast or recurring layout/full-viewport paint |

## 8. Expected Outcome

- **Direct effect.** A gently moving page background with a static reduced-motion variant and independent chat surfaces.
- **Measurable effect.** One decorative layer, no additional requests and passing contrast, interaction and rendering gates.
- **Side effects.** Document-level stacking becomes explicit. The browser gate covers overlays at their existing stack levels.
- **Rollback.** Revert the page-only CSS and its theme test changes together. If auth is included, restore its static gradient declaration. No data rollback is needed.

## 9. Additional Information

- **Rejected alternatives.** Canvas and a frame loop add runtime work for a decorative effect. Animating background-position or blur risks repeated paint.
- **Technical debt.** Light and dark page palette tokens must follow the existing theme branches. No theme-token refactor is included.
- **External dependencies.** None.
- **Sources.** [Project instructions](../AGENTS.md), [manifesto](../MANIFESTO.md), [README](../README.md), [changelog](../CHANGELOG.md), and the two planned epics on the local Agentaro board. The pattern epic was checked in the local instance on 2026-11-20.
- **Q1.** [TO BE DETERMINED] Should the background also appear on sign-in, password reset and two-factor screens as proposed in R5, or only on application pages?
- **Q2.** [TO BE DETERMINED] Implemented with the proposed values (alpha 0.08/0.06 light, 0.12/0.08 dark, 60 s alternate, ±4% translate on a layer with 8% overscan). Does the owner approve the proposed palette, motion speed and amplitude, and the S3/S4 gates?
