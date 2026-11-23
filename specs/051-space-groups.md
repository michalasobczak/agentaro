# 051 — Groups of spaces, arranged with the mouse

Status: **closed** 2026-11-23 (owner: "Zamknij i buduj"); **implemented** 2026-11-23.
Date: 2026-11-23
Depends on: [006](006-responsive-ui.md), [013](013-projects.md), [014](014-spaces.md), [027](027-work-panel-beside-chat.md)

## 1. TL;DR

The owner can make named groups of spaces (for example "Gry": Gra Auta, Gra Psi Patrol, Gra Słodziaki). With the mouse they can drag a space into a group, set the order of spaces within a group, and set the order of the groups. The Spaces page and the work panel show the groups. The director knows them too and can arrange spaces by words. Tests and a browser check confirm it.

## 2. Abstract

- **Current state:**
  - The Spaces page has two fixed sections, "Project spaces" and "Team spaces", sorted by name.
  - The owner has 9 spaces, among them three games.
  - The work panel lists active spaces in the same name order.
- **Gap or problem:** the owner's words: "potrzebuję funkcji grupowanie projektów i zespołów, chcę to zrobić myszką drag and drop".
- **Decision history:** the owner chose (2026-11-23):
  - a group arranges spaces on screen and the director knows it; there are no shared settings;
  - a group may hold both project and team spaces;
  - with the mouse: a space into a group, the order of spaces, the order of groups;
  - on the computer only (like the admin tools, spec 006).

## 3. Objective

**Goals**
- G1. **Groups.**
  - A group has a name (1–60 characters, unique per owner) and a place in the order.
  - A space belongs to at most one group. Spaces outside every group form a section "Bez grupy", shown last.
  - Groups replace the two fixed sections. A space's card still shows whether it is a project or a team space.
- G2. **Managing groups** on the Spaces page (computer only):
  - "New group" asks for a name;
  - a group's name can be changed in place;
  - deleting a group moves its spaces to "Bez grupy" and loses nothing else.
- G3. **Drag and drop** on the Spaces page (computer only). Each change is saved at once and kept after a reload. The owner can drag:
  - a space's card onto another group, or onto "Bez grupy";
  - a space's card within its group, to set the order;
  - a group's heading, to set the order of groups.
- G4. **Seen everywhere:**
  - the Spaces page and the work panel beside the chat (spec 027) show the groups in their order, with the spaces in their order;
  - archived spaces stay last in their group, as today;
  - on a phone the groups are shown but cannot be changed.
- G5. **The director.**
  - The director's list of spaces shows each space's group.
  - New chat actions, each on the owner's words (and agreement, spec 047):
    - `add_group` (name);
    - `rename_group`;
    - `delete_group`;
    - `move_space` (a space into a group or out of every group).

**Out of scope**
- Shared settings of a group (tempo, autonomy, goal, folder).
- Groups within groups.
- Changing groups on a phone.

**Success criteria**
- S1. Dragging "Gra Auta" into "Gry" moves it there. After a reload it is still there, also in the work panel.
- S2. The order set by dragging spaces and groups holds after a reload.
- S3. Deleting "Gry" moves its three spaces to "Bez grupy". No space, epic or setting changes.
- S4. "Dodaj Cerbeto do grupy Badania" in the chat moves Cerbeto when the group exists. When it does not, the director asks, or the owner asked for the group and the director adds it.
- S5. Another user's spaces or groups can never be moved or seen.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `space_groups` (user, name, position); `spaces.space_group_id`, `spaces.position` | to create |
| System | `SpaceGroup` model; ordering of spaces by group and position | to create |
| System | endpoints: create, rename and delete a group; move a space (group and position); reorder groups (JSON, owner only) | to create |
| System | `spaces.js`: drag and drop, first-party script, `textContent` only | to create |
| System | Spaces page, work panel, director's spaces list and actions | to change |

## 5. Functional Domain Changes

- **State:** two fixed sections sorted by name → the owner's groups in the owner's order.
- **Rules:**
  - R1. Only the owner's own spaces and groups. A move names a group of the same owner, or none.
  - R2. Positions are whole numbers, kept dense. A move renumbers its group in one transaction, so two moves never mix.
  - R3. No inline style or script (CSP). Dragging uses the HTML drag events and classes.
  - R4. Data changes are recorded in the data changelog (spec 004) like every other change.
- **Resilience:** a move that fails to save puts the card back and says so. A reload always shows the saved order.
- **Data:** a migration creates `space_groups` and adds `spaces.space_group_id` (nullable, deleting the group sets it null) and `spaces.position`. Existing spaces start with no group, in name order. Back up production first.

## 6. Critical Path

1. Model tests: groups, moves, renumbering, deleting a group (S3, R2).
2. Endpoints with ownership tests (S5).
3. The page, the script, the work panel; a browser check of dragging (S1, S2).
4. The director's list and actions (S4).
5. B20, CHANGELOG, README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | moves and positions; delete keeps the spaces | model tests | commit | a space cannot join another user's group |
| Integration | endpoints, page, panel, chat actions | request and runner tests | commit | 404 for another user's space or group; no inline style |
| Manual | S1, S2 by mouse in the browser | browser on demo data | release | — |

## 8. Expected Outcome

- **Direct effect:** the owner sees their spaces arranged the way they think about them.
- **Side effects:** the Spaces page loses its fixed "Project / Team" split; the kind stays on each card.
- **Rollback:** revert the code. The columns stay unused.

## 9. Additional Information

- **Rejected alternatives:** tags on spaces, because one group per space is what the owner described.
- **Sources and questions:** none open.
- **Implementation (2026-11-23):**
  - Migration `20261123090000`: `space_groups`, `spaces.space_group_id` (null on delete), `spaces.position`. Existing spaces keep their name order.
  - `SpaceGroup.layout` (groups, then "Bez grupy"; archived last), `SpaceGroup.arrange!`, `Space#place!` (renumbers both groups in one transaction).
  - Endpoints: `PATCH /spaces/:id/place`, `PATCH /space_groups/order`, and create, rename and delete for groups.
  - `spaces.js` (HTML drag events; only at 640 px and wider).
  - The work panel's JSON has `groups`; the panel shows group headings.
  - Chat actions `add_group`, `rename_group`, `delete_group`, `move_space`. A move may name a group added in the same reply.
  - Tests: `space_group_test.rb` (7), `space_groups_test.rb` (3); spec 014's list test adapted (groups replace the kind sections).
  - Browser check on demo data:
    - groups and "Bez grupy" shown;
    - the browser tool's mouse drag does not carry the HTML drag events across the page, so dragging was checked with the page's own drag events. A space moved into a group, the order within it was set, the order of groups was set, and all of it held after a reload;
    - no console errors. A drag with a real mouse is left for the owner.
- **Security analysis (B20, after specs 001–051):**
  - Every endpoint looks up the space and the group among the owner's own (404 otherwise, tested); `arrange!` ignores other users' ids.
  - A space cannot join another user's group (validation).
  - The script writes no markup and uses no inline style (the page test checks for none).
  - Brakeman 0 warnings.

