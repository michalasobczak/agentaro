# 015 — New conversation with the director

Status: **implemented** 2026-11-20 (closed by owner: Q1 "Nowa rozmowa", Q2 "W nagłówku czatu")
Date: 2026-11-20
Depends on: [011](011-list-and-management.md)

## 1. TL;DR

The user can start a **new conversation** with the director: the chat and the director's view of it start empty. The old messages are moved to an **archive** that the user can read, and nothing else changes. Confirmed by tests and a browser check.

## 2. Abstract

**Current state (spec 011).** There is one endless conversation per user. The director reads its latest 30 messages on every answer, so old topics keep coming back into new answers.

**Need (owner, 2026-11-20).** "chcę móc czat z dyrektorem czyścić".

**Owner decisions.**
- Clearing starts a new conversation and keeps the old one in an archive; nothing is deleted (Q1).
- The button is in the chat header, on the Director page and in the floating chat (Q2).

## 3. Objective

**Goals**
- G1. **New conversation:** a button in the chat header (Director page and floating chat), with a confirmation. It archives every message of the current conversation.
- G2. Afterwards:
  - the chat shows no messages;
  - the director's prompt contains no archived message;
  - the floating chat starts empty.
- G3. Unchanged: epics, spaces, plans, steps, runs and the team. The director still sees the list of spaces and open epics.
- G4. **Archive page** (linked from the Director page): earlier conversations, newest first, each with its dates and message count, readable as bubbles. Read-only.
- G5. A new conversation cannot start while the director is writing an answer: that answer would land in the new conversation.

**Out of scope**
- Deleting messages for good; renaming conversations; going back into an archived conversation.

**Success criteria**
- S1. After a new conversation, the chat page, the JSON messages endpoint and the director's prompt contain none of the earlier messages; the archive shows them.
- S2. While the director is writing, starting a new conversation is refused with a message.
- S3. Users see only their own archive (other users' messages never appear).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `chat_messages.archived_at` (when the conversation was archived; groups an archived conversation) | to create |
| System | Chat page, floating chat, JSON endpoint and director prompt use only the current conversation | to change |
| System | New-conversation action and button; archive page | to create |

## 5. Functional Domain Changes

**Rules**
- R1. Archiving sets the same `archived_at` time on every message of the current conversation. Messages are never deleted (Q1).
- R2. The change is recorded in the data changelog, one entry per message (spec 004).
- R3. The archive shows message text escaped, like the chat.

**Data:** a new nullable, indexed column.

## 6. Critical Path

Column → scopes (current, archived) → chat, JSON and prompt on current → action and button → archive page → tests → browser check → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | the director's prompt has only the current conversation | `test/models/management_runner_test.rb` | merge | an archived message never in the prompt |
| Integration | button, archive, refused while writing, permissions | `test/integration/director_chat_test.rb` | merge | other users' archives never shown |
| Manual | browser check | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** the user can start fresh with the director whenever a topic is done.
- **Measurable effect:** S1–S3 pass.
- **Side effects:** shorter prompts after a new conversation.
- **Rollback:** drop the column; all messages become one conversation again.

## 9. Additional Information

- **Rejected alternatives:** deleting for good (owner chose the archive); the button only on the Director page (owner: in both).
- **Technical debt:** none.
- **External dependencies:** none.
- **Questions:** Q1 — **new conversation with an archive** (owner); Q2 — **button in the chat header, both places** (owner).

## Security analysis (B20), after spec 015

Scope: this spec and specs 001–014.

- **Separation.** The archive and the new-conversation action use only the signed-in user's messages; other users' archived messages never appear (test). The chat page, the JSON endpoint and the director's prompt read only the current conversation (tests).
- **No loss, recorded.** Nothing is deleted; archiving goes through callbacks, so each message gets a data changelog entry (test).
- **Output.** Archived messages are rendered escaped (test with markup); no inline script or style (test).
- **Found on the way.** While building this, a comment placed inside the prompt's history line cut off its formatting; the new prompt test caught it before release. Also fixed: a flash message on the Director page pushed the full-height chat below the screen.
- **Regressions in 001–014.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities.
