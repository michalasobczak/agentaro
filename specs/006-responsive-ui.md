# 006 — Responsive layout and visual design

Status: **implemented** 2026-11-19 (closed (owner: "make it responsive design, desktop/tablet native, mobile also but with limited functionality … make layout more attractive"). Items marked *(interpretation)* follow the owner's words and can be changed.)
Date: 2026-11-19
Depends on: [002](002-authentication-roles.md), [003](003-http-audit-log.md), [004](004-data-changelog.md)

## 1. TL;DR

Agentaro gets a designed interface: a sidebar layout that uses the full width on desktop and tablet, larger type, cards, badges and clear forms, in light and dark mode. Phones get a compact layout with only what is needed on the go. Confirmed by screenshots at desktop, tablet and phone widths and by tests of the mobile limits.

## 2. Abstract

**Current state.** The pages from specs 002–004 use a minimal stylesheet: a plain top bar, 15 px text, a 1100 px column, unstyled tables.

**Gap.** The owner finds it rudimentary; it is not designed for tablets or phones, and the text is small.

**Constraints.** No JavaScript and no external resources (Content-Security-Policy from spec 002, on-prem principle): system fonts, inline SVG icons, CSS only.

## 3. Objective

**Goals**
- G1. Desktop and tablet (≥ 640 px; narrower sidebar between 640 and 1099 px): fixed sidebar with brand, navigation with icons and the signed-in user; content centered and using the available width (up to 1600 px).
- G2. Larger type: 17 px base on desktop and tablet, 16 px on phones; clear headings.
- G3. Components: page header, cards, stat tiles on the home page, tables with sticky headers and horizontal scrolling, status badges (role, TOTP, account state), primary/secondary/danger buttons, larger form fields, styled flash messages, centered sign-in card.
- G4. Light and dark mode following the system setting. *Owner fix (2026-11-20, "potrzebuję też dark mode"): a switch **Auto / Light / Dark** in the sidebar and the phone menu, saved on the account (`users.theme`, migration `20261121128000`); the choice is set on `body`, so it applies at once with Turbo, and "auto" still follows the system.*
- G5. Phones (< 640 px): top bar with a collapsible menu (`<details>`, no JavaScript). *(interpretation)* Available on phones: sign-in, TOTP, home, my sessions, change password. Admin tools (users, audit log, data changes) are for desktop and tablet: hidden from the phone menu, and opening them on a phone shows a short note instead of the page.

**Out of scope**
- New features or changed behaviour; access rules stay as in spec 002 (hiding on phones is presentation, not authorization).
- Custom web fonts, JavaScript, client-side interactivity.

**Success criteria**
- S1. No horizontal page scrolling at 375, 768 and 1440 px (wide tables scroll inside their own box).
- S2. On a phone, the menu shows no admin links and admin pages show the note.
- S3. All existing tests pass; CSP unchanged (no inline scripts, no external sources).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| System | `app/assets/stylesheets/application.css` | to change (rewrite) |
| System | `app/views/layouts/application.html.erb`, `app/helpers/application_helper.rb` (nav, icons, badges) | to change |
| System | all views from specs 002–004 | to change (markup only) |

## 5. Functional Domain Changes

- **State:** rudimentary single-column pages → designed, responsive layout.
- **Rules:** R1. Presentation only — every route, permission and response code stays the same. R2. Admin tools stay reachable for admins on any device by URL; on phones the page body is replaced by a note through CSS.
- **Data:** none.

## 6. Critical Path

Stylesheet (tokens, layout, components) → layout with sidebar and phone menu → restyle pages → tests → screenshots at three widths.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Integration | 0 failures | `bin/rails test` (existing + layout markers for phone limits) | commit | admin links rendered without the desktop-only marker |
| Manual | S1, S2 | screenshots at 375, 768, 1440 px | push | horizontal page scroll |

## 8. Expected Outcome

- **Direct effect:** a modern, readable interface on desktop and tablet; a focused phone view.
- **Rollback:** revert the stylesheet and views.

## 9. Additional Information

- **Rejected alternatives:** a CSS framework (Tailwind, Bootstrap) — needs a build step or a CDN; plain CSS keeps the minimal stack. Web fonts — external requests or extra files for little gain.
- **Questions:** Q1. Is the phone scope in G5 right? *(interpretation; owner can adjust)*
- **Decision history:** the first breakpoint (900 px) treated portrait tablets (768–834 px) as phones; found in the tablet screenshot and lowered to 640 px.
- **Results (2026-11-19):** screenshots at 1440 px (sidebar, dashboard, users, user detail, audit log, data changes), 768 px (sidebar 220 px, 17 px type, wide tables scroll inside their card, no page scroll) and 375 px (top bar, menu with Home and My sessions only, admin note, no page scroll). Security check: presentation only; no inline styles or scripts (test); raw HTML only for the generated QR code and constant icons; Brakeman unchanged (F8 of spec 005).
