# 019 — A verifier in the chat

Status: **implemented** 2026-11-20 (closed by owner: "Akceptuję, buduj" — Q5 accepted)
Date: 2026-11-20
Depends on: [011](011-list-and-management.md), [012](012-remove-managers.md), [017](017-voice-and-streaming.md)

## 1. TL;DR

On demand, the user asks a second model, the **verifier**, to check what the director just said.
- The verifier is an agent on a different model: Codex checks Claude.
- It reads the conversation and the director's latest answer, then posts a short critical **comment** in the chat. It never changes anything.
- In voice mode it speaks with **its own voice**.

Confirmed by tests with stand-in agents and a real check of a Claude director by a Codex verifier.

## 2. Abstract

**Current state.** One model, the director, answers the user. Nobody checks it.

**Need (owner, 2026-11-20).**
- "chcę też opcję, żeby do chatu, rozmowy zaprosić drugi model, żeby mogli ze sobą i ze mną porozmawiać. Jeden model ściemnia, musi mieć weryfikatora"
- "weryfikator na żądanie przyciskiem, tylko komentuje, Codex sprawdza Claude'a — ma to sens, zacznijmy od tego, zobaczymy, czy się sprawdzi; ma uczestniczyć głosowo również, ale z innym głosem"

**Owner decisions.**
- On demand, with a button (Q1).
- It only comments; it cannot change the list, spaces, plans or steps (Q2).
- Codex checks Claude (Q3).
- It takes part in voice mode with a different voice (Q4).

## 3. Objective

**Goals**
- G1. **Verifier role:** on the Team page the user chooses one of their agents as the verifier, next to the director. A hint recommends an agent on another model than the director's (e.g. Codex when the director runs on Claude).
- G2. **Button:** "Ask the verifier" in the chat header (Director page and floating chat) and in the voice panel. It is shown only when a verifier is chosen, and disabled while the director or the verifier is writing.
- G3. **What the verifier sees:**
  - the current conversation (latest 30 messages), including the director's latest answer and the actions Agentaro applied;
  - the names and goals of the user's spaces, and the titles of their open epics;
  - an instruction to check facts, logic and claims of done work, and to say plainly what is wrong, doubtful or unverified.

  The same separation as the chat applies: no descriptions of other spaces (spec 013, G3).
- G4. **What it answers:** plain text, short (at most about 8 sentences), in the conversation language (spec 017 switch). It is posted in the chat as a message from the verifier, with its own name and colour. No JSON and no actions: Agentaro applies nothing from it (Q2).
- G5. **The director reads it:** verifier messages stay in the conversation. The director sees them in its next answer, labelled as the verifier's, and may agree or answer back. The user can then talk to both.
- G6. **Voice:** in voice mode, the verifier's comment is spoken with a second voice (Polish: another Piper voice, Q5; English: a second English voice if installed, otherwise the English voice). The button is also in the voice panel, so the user can say their piece and then press it.
- G7. The verifier runs like the director's chat runs (spec 011): one at a time per user, on its agent's executor, with a timeout. A failure posts an Agentaro notice.

**Out of scope**
- The verifier blocking or changing the director's actions (Q2).
- The verifier checking epic steps or plans automatically.
- More than one verifier.

**Success criteria**
- S1. With a stand-in director and verifier, pressing the button posts the verifier's comment. The director's next prompt contains it, and nothing on the list changes (tests).
- S2. A real check on the host: a Claude director's answer with a false claim, checked by a Codex verifier, gets a comment that points it out.
- S3. In voice mode the comment is spoken in the second voice.
- S4. Users never see or trigger other users' verifiers (tests).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `team_roles.role` adds `verifier`; `chat_messages.author` adds `verifier`; `task_runs.purpose` adds `verify` | to change |
| System | `ManagementRunner` purpose `verify` (plain text, no actions); endpoint `POST /director/verify` (rate-limited) | to change / to create |
| System | Team page (verifier card); chat header and voice panel button; verifier bubble; voice per speaker | to change |
| Host | Second Polish Piper voice `pl_PL-darkman-medium` (about 63 MB, Hugging Face rhasspy/piper-voices) in `storage/voice/` (Q5) | to install |

## 5. Functional Domain Changes

**Rules**
- R1. The verifier's answer is text only: never parsed for actions, never applied (Q2).
- R2. At most 20 verifier requests per user per 10 minutes. One at a time, and not while the director is writing.
- R3. The verifier must be a usable agent of the user, or a shared one (spec 009), like the director.
- R4. The verifier's prompt follows the conversation language (spec 017 switch).

**Resilience:** a failed or timed-out verifier run posts "The verifier could not answer" as an Agentaro notice. The chat goes on.

**Data:** new values in existing columns; no migration besides the role list.

## 6. Critical Path

Role and author values → verifier run (prompt, plain answer) → button and endpoint → director's history includes the verifier → team page → voice per speaker (second voice) → real check on the host → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | verify prompt, plain answer posted, nothing applied, director history includes it | `test/models/management_runner_test.rb` | merge | actions in the verifier's text are never applied |
| Integration | button, endpoint, team role, permissions, limits | `test/integration/director_chat_test.rb` | merge | other users' verifiers unreachable |
| E2E | Codex verifier comments on a Claude director's answer; voice | owner's Mac | release | — |

## 8. Expected Outcome

- **Direct effect:** the user gets a second opinion on demand, from another model, in text and voice.
- **Measurable effect:** S1–S4 pass.
- **Side effects:** one more run per request; a little more subscription use.
- **Rollback:** remove the role and button; old verifier messages stay as text.

## 9. Additional Information

- **Rejected alternatives:** a verifier that is always on (owner: on demand); one that can block actions (owner: comments only).
- **Technical debt:** the verifier sees only the conversation, not the steps' outputs.
- **External dependencies:** a second Piper voice (Q5).
- **Questions:**
  - Q1–Q4 answered by the owner (see Abstract).
  - Q5. The second voice — **pl_PL-darkman-medium** (owner accepted) (a male Polish Piper voice, about 63 MB, from Hugging Face rhasspy/piper-voices), downloaded into `storage/voice/`. English keeps the current voice unless a second one is installed later.

## Security analysis (B20), after spec 019

Scope: this spec and specs 001–018.

- **Comments only (R1).** The verifier's answer is stored as text and never parsed for actions. A test feeds it JSON that looks like an action, and nothing changes.
- **Separation.** The verifier gets the same data as the chat: names and goals of spaces, epic titles, and the conversation. No space descriptions, plans or step outputs (spec 013, G3). Only the user's own verifier can be asked (test).
- **Limits (R2).** At most 20 requests per user per 10 minutes, one at a time, and none while the director writes.
- **Prompt injection between models.** The director reads the verifier's comments and may act on them in its next answer. Its actions are still checked by Agentaro (spec 011, R1), so a misleading comment can change only what the director proposes, never what Agentaro accepts.
- **Output.** Verifier messages are rendered escaped (test with markup).
- **Voice.** The second voice is a local Piper model (`pl_PL-darkman-medium`, 63 MB, Hugging Face), installed with the owner's consent; nothing leaves the host.
- **Verified on the host.** A Claude director's answer with a wrong tax deadline and an unverified "I checked it" was checked by a Codex verifier in 20 seconds. The verifier named both problems and gave official sources; the director's next answer accepted the correction. In the browser the button worked without reloading, and the verifier corrected a wrong multiplication.
- **Regressions in 001–018.** Brakeman: no warnings. `bundle-audit`: no vulnerabilities.
