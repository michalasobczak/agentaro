# 033 — Autonomy slider: how often agents ask the owner

Status: **closed** 2026-11-21 (the owner accepted the proposals for Q1–Q4).
Date: 2026-11-21
Depends on: [011](011-list-and-management.md), [016](016-sequential-steps.md), [021](021-director-sees-step-output.md), [031](031-brain-memory.md)

## 1. TL;DR

The owner sets how independent the director and the agents are, globally and per space. More autonomy means no questions: the agent picks its own recommended option and writes down what it assumed. Less autonomy means more questions: the director clarifies before planning, shows the plan for approval and steps stop to ask. Tests and a demo of the same epic at each level confirm it.

## 2. Abstract

- **Current state:**
  - The director plans an epic alone. If it cannot, it blocks the epic with one question (`{"blocked": …}`), and the owner answers in the chat.
  - Steps never ask: they do the task and answer, whatever they had to guess.
  - Chat changes happen only when the owner's latest message asks for them (spec 021). That stays.
- **Gap or problem:**
  - There is no way to say "decide yourself" or "check with me first". The behaviour is fixed somewhere in the middle.
  - When a step guesses, the guess is buried in its answer.
- **Rationale:** the owner wants to choose, like Karpathy's "autonomy slider": tight control for new or risky work, full independence for routine work.
- **Decision history:**
  - Draft spec 102 proposed autonomy levels earned automatically through a judge of the owner's taste. This spec gives the owner the manual slider first. Spec 102 can later move the slider by itself, within the owner's cap.
  - Actions that need the owner by the safety rules (sending, publishing, paying, deleting outside the run's folder) never become automatic.

## 3. Objective

**Goals**
- G1. **Three levels** (Q1):

  | Level | Name | Before planning | The plan | During steps | Choices |
  |---|---|---|---|---|---|
  | 1 | **Pytaj** (Ask) | the director asks up to 3 clarifying questions when anything is unclear | shown for approval; the epic starts after **Approve** | a step that needs a decision stops and asks | the owner chooses |
  | 2 | **Ważne pytaj** (Ask about important things), default | asks only when it cannot plan (as today) | starts at once | a step asks only about important decisions (G4); otherwise assumes | the agent picks its recommendation for small choices |
  | 3 | **Decyduj** (Decide) | never asks; plans with assumptions | starts at once | a step never stops, except for G4's always-ask list | the agent always picks its recommendation |

- G2. **Where it is set** (Q2):
  - a default for the owner, on the Director page beside the chat header;
  - an optional level per space, on the space form, which wins over the default;
  - in the chat: "w przestrzeni Backupy decyduj sam" sets the space level (an action checked like other chat actions).
- G3. **Steps can ask.** A step's answer may end with a decision block (a fixed JSON format, documented in the step prompt):
  - the question;
  - 2–4 options;
  - the recommended option and why;
  - whether it is important (costly, hard to undo, or about the owner's taste).

  Agentaro then follows the level:
  - **Pytaj**, or **Ważne pytaj** with an important decision: the epic blocks with the question in the chat. The owner's answer (a button per option or free text) resumes the step with the answer as a `decision` prompt section.
  - Otherwise: Agentaro records the recommended option as an **assumption** and runs the step again with it as its decision, without asking.
- G4. **Always ask.** At every level, the agent must ask before:
  - sending, publishing or posting anything outside Agentaro;
  - spending money or buying anything;
  - deleting or overwriting data outside the run's own folder;
  - pushing to a shared repository;
  - anything touching passwords, keys or tokens.

  The list is in code and in every step prompt; the brain or the director cannot shorten it (Q3).
- G5. **Assumptions are visible.**
  - Each one is a line "Założyłem: …" on the epic page, under its step, and in the director's report of the finished epic.
  - **Popraw** (Correct) lets the owner give the right answer. The epic does not rerun by itself; the correction becomes a fact in the brain (spec 031) for next time, and the owner can press Try again.
- G6. **The director follows the level in the chat.** At **Decyduj** it does not end answers with questions ("Czy mam…?") when a recommendation is clear; it says what it will do. Changes still need the owner's request (spec 021 rule kept).

**Out of scope**
- Levels that change by themselves from ratings (spec 102).
- Technical blocking of what a step does inside its working folder: the limits of spec 018 stay as they are; G4 is an instruction to the agent plus the check in G3.

**Success criteria**
- S1. At **Pytaj**, "Przygotuj raport o backupach" gets clarifying questions, then a plan waiting for **Approve**; nothing runs before it.
- S2. At **Decyduj**, the same request is planned and run without a question, and the report lists "Założyłem: format Markdown".
- S3. At **Ważne pytaj**, a step that wants to choose between PDF and Markdown assumes; a step that wants to e-mail the report stops and asks.
- S4. At **Decyduj**, a step that wants to publish something still asks (G4).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `users.autonomy_level`, `spaces.autonomy_level` (null = the owner's default) | to create |
| Data | `step_decisions` (step, question, options, recommended, important, answer, answered_by owner or assumption, corrected) | to create |
| Data | `work_items.state` gains `awaiting_approval` | to change |
| System | `Autonomy.level_for(space)`, decision-block parser | to create |
| System | planning prompt: clarifying questions and plan approval at level 1; assumptions at level 3 | to change |
| System | step prompt: decision format and always-ask list | to change |
| System | chat prompt: level rules (G6); action `set_autonomy` | to change |
| System | epic page: Approve plan, decisions, assumptions with Correct | to change |
| System | Director page and space form: the slider | to change |
| Spec | 102 G5 points to this slider as the owner's cap | to change |

## 5. Functional Domain Changes

- **State:** fixed behaviour → behaviour per level; epics may wait for plan approval; steps may wait for a decision.
- **Rules:**
  - R1. **The safest wins.** If the space level and the owner's default differ, the space level counts; the G4 list counts at every level.
  - R2. **Questions are counted.** At **Pytaj** the director asks at most 3 clarifying questions per epic, then plans.
  - R3. **An answer resumes, it does not restart.** A decided step reruns only that step, with earlier answers carried forward (spec 021).
  - R4. **Assumption is not consent.** An assumption never covers a G4 action; a G4 decision always waits for the owner.
  - R5. **Decision blocks are data.** Options and recommendations from a step are shown escaped and never run as actions; only the owner's click or message, or the level rule, picks one.
  - R6. **Level changes are recorded** in the data changelog (spec 004).
- **Resilience:** an unanswered decision keeps the epic blocked, with the pop-up of spec 026; nothing is chosen on a timeout.
- **Data:** two columns, a new table and a new epic state; default level 2 keeps today's behaviour for planning.

## 6. Critical Path

1. Level settings and the slider.
2. Decision format in steps and its handling per level.
3. Planning: clarifying questions and approval at level 1, assumptions at level 3.
4. Assumptions on the epic page and in the report; Correct into the brain.
5. Tests, demo (S1–S4), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | level resolution; decision parser; G4 list | `test/models/autonomy_test.rb` | merge | a G4 decision is never assumed; malformed blocks are ignored safely |
| Integration | S1–S4 with stand-in tools; approve plan; answer a decision; correct an assumption | `test/integration/autonomy_test.rb` | merge | another user's epic cannot be approved or answered; CSRF |
| E2E | S1 and S2 on demo data | browser | release | — |

## 8. Expected Outcome

- **Direct effect:** the owner chooses between control and independence, per space.
- **Measurable effect:** questions per epic and assumptions corrected, per level (feeds spec 102).
- **Side effects:** at **Pytaj** epics start later; at **Decyduj** some assumptions will be wrong, which Correct and the brain fix for the future.
- **Rollback:** every space back to level 2; hide the slider.

## 9. Additional Information

- **Rejected alternatives:**
  - A free-form slider 0–100: hard to say what each value does.
  - Letting the agent decide what is important without a fixed list: the important cases are the ones that must not depend on the model.
- **Technical debt:** "important" beyond the G4 list is the agent's judgement; spec 102's judge can check it later.
- **Sources and questions:**
  - Q1. Three levels with these names and behaviours, and **Ważne pytaj** as the default? (Owner, 2026-11-21: as proposed.)
  - Q2. A default for you plus an optional level per space (proposed), or only one global slider? (Owner, 2026-11-21: as proposed.)
  - Q3. Is the always-ask list in G4 complete? Anything to add, for example work above some time or cost? (Owner, 2026-11-21: as proposed.)
  - Q4. At **Pytaj**, should every finished step also wait for your OK before the next one starts, or is plan approval enough (proposed)? (Owner, 2026-11-21: as proposed.)
  - Background: Karpathy, "Software 3.0" talk (2025): partial autonomy with an autonomy slider; Anthropic, "Building effective agents" (2024).
