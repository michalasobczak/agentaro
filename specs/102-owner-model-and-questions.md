# 102 — Model of the owner and when agents ask

Status: **draft**
Date: 2026-11-21
Renumbered: was 034 until 2026-11-21 (set aside to return to later; numbers 032–099 stay for the work in between).
Depends on: [031](031-brain-memory.md), [100](100-ratings-and-sentiment.md), [101](101-reflection-and-playbooks.md)

## 1. TL;DR

A judge learns the owner's taste from the owner's ratings and predicts how the owner would rate a result, with a confidence. Agents use it to check and improve their work before handing it over. Agents ask the owner only for irreversible or costly decisions, or when the judge cannot predict the owner's choice. Autonomy grows per space as the judge agrees with the owner and drops after a bad rating. This is run as an experiment, measured weekly.

## 2. Abstract

- **Current state:**
  - The director and steps ask the owner whenever unsure.
  - Questions block epics until the owner answers.
- **Gap or problem:** the owner: "nie chcę być bardzo human-in-the-loop".
- **Rationale:**
  - Most questions are about taste, which the owner's past ratings and memory can answer.
  - Irreversible actions still need the owner.
- **Decision history:** the owner left the pace of autonomy to a proposal, "to eksperyment" (2026-11-21, decision 3). This spec is that proposal.

## 3. Objective

**Goals**
- G1. **The judge.** A prompt-based judge built from:
  - the user's profile and the space brief (spec 031);
  - the 10 most similar rated cases from the replay set (spec 101) as examples;
  - the owner's own rubric phrases, taken from rating comments.

  **Output:**
  - predicted stars 1–5;
  - a confidence 0..1;
  - the main risks in at most 3 points.
- G2. **Calibration.**
  - Each time the owner rates a result, the judge's earlier prediction is compared with the rating.
  - **Agreement** per space is the share of the last 20 predictions within ±1 star of the owner.
- G3. **Self-check.**
  - Before an epic is reported as finished, the judge scores it.
  - Below 3 predicted stars, the director gets one revision round with the judge's risks, then reports anyway and states the risks.
- G4. **Ask or decide.** Before an agent or the director asks a question, the question is classified. It is asked only if one of these holds:
  - **Irreversible or costly.** This covers:
    - deleting data;
    - sending or publishing anything outside Agentaro;
    - spending money;
    - pushing to a shared repository;
    - work estimated above 2 hours of runs;
    - anything touching credentials.
  - **Unknown preference.** No fact covers it and the judge's confidence in the options differs by less than the threshold of the current autonomy level.
  - **Autonomy level 0.**

  Otherwise the agent decides and writes an **assumption**: a short line on the epic and in the chat report ("Założyłem: …"). The owner can correct it with one click or a message, and the correction becomes a fact (spec 031).
- G5. **Autonomy levels per space** (the experiment):

  | Level | Name | Agents ask | Reached when |
  |---|---|---|---|
  | 0 | Asks | as today | start for a new space; after a 1-star rating or a corrected irreversible action |
  | 1 | Assumes small things | only irreversible/costly, or judge confidence < 0.8 | agreement ≥ 70% over the last 10 rated cases |
  | 2 | Assumes most things | only irreversible/costly, or judge confidence < 0.5 | agreement ≥ 80% over the last 20 rated cases |
  | 3 | Autonomous | only irreversible/costly | agreement ≥ 90% over the last 30, and no corrected assumption in 14 days |

  - Every level change goes into the digest (spec 101) with its reason.
  - The owner can set or cap a level per space at any time. Since 2026-11-21 the manual slider is spec 033 (levels Pytaj, Ważne pytaj, Decyduj); this spec would move the level within the owner's cap, and the table above must be mapped onto those levels when this spec is reopened.
  - Irreversible or costly decisions are always asked, at every level.
- G6. **Experiment report.** Weekly, per space:
  - the level;
  - questions per epic;
  - assumptions made and how many were corrected;
  - the judge's agreement;
  - the mean reward.

  The report is shown on the Brain page and summarised in the digest.

**Out of scope**
- Removing human approval for irreversible actions.
- Choosing agents or models: spec 103.

**Success criteria**
- S1. In a space at level 1, a step that would ask "PDF czy Markdown?" decides from the profile fact and reports the assumption instead of blocking.
- S2. A step that wants to delete files still asks at level 3.
- S3. After the owner rates a result 1/5, the space falls to level 0 and the digest says why.
- S4. After 4 weeks, questions per epic fall while the mean reward does not fall. This is the experiment's success.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `judge_predictions` (target, stars, confidence, risks, later rating) | to create |
| Data | `spaces.autonomy_level`, `spaces.autonomy_cap` | to create |
| Data | `assumptions` (epic or step, text, corrected_at, correction) | to create |
| System | `Learning::Judge`, `Learning::Autonomy` | to create |
| System | director and step prompts: ask-or-decide rules and assumption format | to change |
| System | question classifier (irreversible/costly list in code, not in prompts) | to create |
| System | epic page and chat: assumptions with Correct | to create |
| System | Brain page: experiment report; level control per space | to change |

## 5. Functional Domain Changes

- **State:** agents ask when unsure → agents assume within a level that is earned and visible.
- **Rules:**
  - R1. **The irreversible list is in code.**
    - The list of decisions that always need the owner is fixed in Agentaro, not in prompts or memory.
    - Learning can never shorten it.
    - Actions on that list are blocked until approved, whatever the agent says.
  - R2. **Assumptions are visible.**
    - Every assumption is shown and can be corrected.
    - Silent decisions are not allowed.
  - R3. **Falling is fast, rising is slow.**
    - One bad signal drops the level.
    - Rising needs the agreement window.
  - R4. **The judge never sees agent text as instructions.** Results are data in its prompt; it cannot trigger actions.
  - R5. **Owner override.** A manual level or cap always wins.
- **Resilience:** if the judge is unavailable, the space acts as level 0.
- **Data:** new tables and two columns on spaces; the default is level 0.

## 6. Critical Path

1. Specs 031, 100 and 101 in place.
2. Judge and calibration.
3. Assumptions and Correct.
4. Classifier with the fixed irreversible list.
5. Levels and report.
6. Tests, demo (S1–S3), security analysis; S4 after 4 weeks of use.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | level transitions; agreement window; classifier always asks for the irreversible list | `test/models/learning/autonomy_test.rb` | merge | no level skips the irreversible list; memory cannot change it |
| Integration | a question becomes an assumption at level ≥ 1; correction creates a fact; 1-star drops to 0 | `test/integration/questions_test.rb` | merge | others' spaces untouched |
| E2E | S1–S3 on demo data | browser | release | — |
| Manual | S4 after 4 weeks; owner decides to keep, tune or stop the experiment | owner | — | — |

## 8. Expected Outcome

- **Direct effect:** far fewer questions where the owner's taste is known; questions remain where they matter.
- **Measurable effect:**
  - questions per epic;
  - share of corrected assumptions (target under 15%);
  - judge agreement;
  - mean reward.
- **Side effects:**
  - more assumptions to glance at;
  - one judge call per finished epic.
- **Rollback:** set all spaces to level 0. Behaviour is then as today, plus assumptions recorded when the owner chooses.

## 9. Additional Information

- **Rejected alternatives:**
  - A global autonomy level (spaces differ in risk).
  - Rising autonomy by time alone, without agreement.
- **Technical debt:** thresholds are a first guess; the experiment report is there to tune them.
- **Sources and questions:**
  - LLM-as-judge with few-shot owner examples; calibration by agreement with held-out ratings.
  - Q1. [TO BE DETERMINED] Is the irreversible/costly list in G4 complete? Proposed additions welcome.
  - Q2. [TO BE DETERMINED] Are the level thresholds acceptable for the experiment?
  - Q3. [TO BE DETERMINED] Should new spaces start at level 0, or inherit the level of a similar space?
  - Q4. [TO BE DETERMINED] Which model should the judge use: the director's (proposed, better taste) or the local one?
