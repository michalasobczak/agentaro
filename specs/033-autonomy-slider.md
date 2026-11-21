# 033 — Autonomy slider: how often agents ask the owner

Status: **closed** 2026-11-21 (the owner accepted the proposals for Q1–Q4); **implemented** 2026-11-21.
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

## Implementation notes (2026-11-21)

- **Data:** migration `20261121150000`: `users.autonomy_level` (default 2), `spaces.autonomy_level` (empty = the owner's default), `work_items.awaiting_approval` and `work_items.clarifications`, and the table `step_decisions` (pending questions and assumptions of plans and steps).
- **Plan approval** is a flag on a planned epic, not a new epic state, so the board, the panel and every query that knows "planned" keep working; `StepChain` never starts or queues a step of a plan that waits.
- **Steps** get a named prompt section `autonomy` (spec 030) with the level, the always-ask list and two line formats: `AGENTARO-DECISION: {json}` to ask and `AGENTARO-ASSUMED: …` for each choice made. After a successful run:
  - assumption lines become assumptions;
  - a decision waits for the owner when it is on the always-ask list, at **Pytaj**, or important at **Ważne pytaj**: the step becomes `waiting`, the epic blocks with the question, and the chat says it with the options;
  - otherwise the recommended option is recorded as an assumption and the step runs again with a `decision` section (the decisions and its previous answer, as data);
  - a step that asks more than 3 times is taken as it is.
- **Answering** on the epic page (a button per option, or own words) or in the chat (`answer_decision`) resumes the step; one answer wins. Try again, the chat retry and the pop-up's Try again do nothing while a question waits.
- **Planning:** at **Pytaj** the director may ask up to 3 questions in one round, then plans; the plan waits for **Approve plan** on the epic page or `approve_plan` in the chat. At **Decyduj** it plans with `assumptions`. Plan assumptions are listed with the plan's note in the chat.
- **Assumptions** are shown on the epic page with **Correct**; a correction becomes an active fact about the space (spec 031), so the next plans see it. The finished epic's chat note lists them.
- **Slider:** three buttons in the chat header (Pytaj, Ważne pytaj, Decyduj); a select on the space form; `set_autonomy` in the chat.
- **Chat (G6):** the chat prompt carries the owner's level; at **Decyduj** the director is told not to end with "Czy mam…?" questions.
- **Tests:** `test/models/autonomy_test.rb` (12), `test/integration/autonomy_test.rb` (8). Two older tests now expect the `autonomy` prompt section.
- **Browser check on demo data:** a step's question with its options; answering "PDF" resumed the step, which recorded a new assumption and finished the epic; a correction became a space fact; Approve plan started a waiting plan; the slider switched to Decyduj. No horizontal scroll at 719 px.

## Security analysis (B20), after spec 033

- **Injection (R5).** Questions, options and assumptions come from agents. They are printed through ERB escaping (test with `<b>`), sent back to steps only in a section labelled as data, and never run: an option is chosen only by the owner's click or words, or by the level rule. A recommendation that is not one of the options is replaced by the first option. Malformed decision lines are ignored.
- **Consent (R4).** The always-ask list is in code and in every step prompt; a decision marked always-ask waits at every level and is never turned into an assumption (test). Honest limit: Agentaro cannot detect an always-ask action a step does without asking inside its working folder; spec 018's limits still apply.
- **Chat actions.** `approve_plan` and `set_autonomy` need the owner's own latest message to approve or to talk about asking (tests: a plain question changes nothing); `answer_decision` only on the owner's own pending questions.
- **Access.** Answer, correct and approve are limited to the owner's epics (404 otherwise, test); the level is changed only on the signed-in account; CSRF as everywhere.
- **Memory.** A correction becomes a fact only through the brain's checks (secrets refused, test).
- **Concurrency.** Answering and Try again use the same claim; a question blocks the claim, and only one answer wins (test).
- **Earlier specs.** Spec 016 chain unchanged at level 2 when steps do not ask; spec 021 retries refuse while a question waits; spec 026 pop-up hides Try again then; spec 032 retries only failed runs, never a step that asked. No regressions found.
- **Tools.** Brakeman: 0 warnings. No new gems.

