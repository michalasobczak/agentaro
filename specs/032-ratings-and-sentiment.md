# 032 — Ratings and sentiment: one reward per result

Status: **draft**
Date: 2026-11-21
Depends on: [016](016-sequential-steps.md), [019](019-verifier.md), [031](031-brain-memory.md)

## 1. TL;DR

The user can rate an epic and each step: thumbs up or down, or 1–5, with an optional comment. Every user message about a result is also tagged with sentiment by the local model. Together with behaviour (accepted, corrected, retried, cancelled) and objective signals (verifier, failures, time), each epic and step gets one reward between 0 and 1. Tests and demo data confirm the reward and its breakdown.

## 2. Abstract

- **Current state:**
  - Results are judged only by whether steps succeed.
  - The user's opinion is lost in the chat.
- **Gap or problem:** learning (specs 033–035) needs a signal that says how good a result was in the owner's eyes.
- **Rationale:**
  - An explicit rating is the strongest signal, but the owner will not rate everything.
  - Sentiment and behaviour fill the gaps automatically, including from voice.
- **Decision history:**
  - the owner accepted thumbs and ratings and sentiment of the owner's messages (2026-11-21);
  - sentiment runs on the local model (decision 1 of spec 031).

## 3. Objective

**Goals**
- G1. **Explicit ratings.**
  - On the epic page and its finished steps: 👍/👎 and 1–5 stars, plus an optional comment of at most 500 characters.
  - In the chat, a short form under the director's message that reports a finished epic.
  - The latest rating per item counts; earlier ones stay in history.
- G2. **Sentiment.** The extraction pass of spec 031 also tags each user message with:
  - valence −2..+2;
  - a target: an epic, a step, a director answer or an agent, resolved from the conversation, or "none";
  - a short reason, such as "too long" or "no sources";
  - a confidence.

  Messages with no target do not count.
- G3. **Behaviour signals,** recorded as events:
  - the epic finished and was not reopened within 3 days (accepted);
  - Try again;
  - the user asked to redo or correct the result (from sentiment and director actions);
  - cancelled or deleted while running;
  - the verifier passed or failed;
  - a step failed or timed out.
- G4. **Reward.**
  - Per epic and per step: a weighted mean of the available signals, mapped to 0..1, with a confidence that grows with explicit ratings.
  - The breakdown is stored and shown on hover.
- G5. **Episodes.** Every rating and tagged message becomes a memory episode (spec 031), so lessons can cite it.
- G6. **A short prompt, rarely.** After an epic finishes, the chat may ask "Jak oceniasz?" with the thumbs. It asks at most once per epic and at most 3 times a day; with Q3 it is off.

**Out of scope**
- Using the reward to change behaviour: specs 033–035.
- Rating other users' results.

**Success criteria**
- S1. Rating an epic 2/5 with "za długie" stores the rating, gives the epic a low reward and creates an episode.
- S2. Writing "świetna robota z backupami" after the Backups epic gives positive sentiment targeted at that epic.
- S3. An epic with no explicit rating still gets a reward from behaviour, with low confidence.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `ratings` (user, target type and id, thumbs, stars, comment, created_at) | to create |
| Data | `feedback_signals` (user, target, kind, value, confidence, source message) | to create |
| Data | `rewards` (target, value, confidence, breakdown JSON, computed_at) | to create |
| System | rating controls on the epic page, steps and the chat report message | to create |
| System | `Brain::Extractor`: sentiment fields | to change |
| System | `Reward.compute(target)`; recomputed on each new signal | to create |

## 5. Functional Domain Changes

- **State:** no feedback → feedback and reward per epic and step.
- **Rules:**
  - R1. **Weights** (proposed, Q1):
    - explicit stars or thumbs: 1.0;
    - correction or redo: 0.6;
    - sentiment: 0.4 × confidence;
    - verifier: 0.3;
    - accepted without changes: 0.3;
    - failures and timeouts: 0.3.
  - R2. **Explicit wins.** With an explicit rating, the reward's confidence is high and sentiment cannot move it more than 0.1.
  - R3. **Only the user's own signals.** Sentiment comes only from user messages. Agent text never counts as feedback.
  - R4. **Scope.** Ratings and signals refer only to the user's own items; other users' items give 404.
  - R5. **No nagging.** The rating prompt follows G6 limits and can be switched off.
- **Resilience:**
  - Sentiment tagging is in the same background job as extraction.
  - If the local model is down, rewards use the other signals and update later.
- **Data:** three new tables. Rollback drops them.

## 6. Critical Path

1. Ratings table and controls.
2. Behaviour events.
3. Sentiment fields in extraction.
4. Reward computation and breakdown.
5. Tests, demo (S1–S3), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | reward from each combination of signals; explicit wins; no target → ignored | `test/models/reward_test.rb` | merge | agent text never becomes a signal |
| Integration | rate, re-rate, history; chat prompt limits; JSON and pages show the breakdown | `test/integration/ratings_test.rb` | merge | others' items 404; CSRF on rating |
| E2E | S1–S3 on demo data with the local model | browser | release | — |

## 8. Expected Outcome

- **Direct effect:** every result has a measured value in the owner's eyes.
- **Measurable effect:** share of finished epics with a reward of confidence ≥ 0.5.
- **Side effects:** one extra small control on results; an occasional question in the chat.
- **Rollback:** hide the controls; drop the tables.

## 9. Additional Information

- **Rejected alternatives:**
  - Only explicit ratings: too sparse.
  - Sentiment with Claude: the owner chose local.
- **Technical debt:** the weights are hand-set; spec 034 can calibrate them against explicit ratings.
- **Sources and questions:**
  - Q1. [TO BE DETERMINED] Are the proposed weights acceptable as a start?
  - Q2. [TO BE DETERMINED] Thumbs and stars together, or stars only, where thumbs mean 5 and 1?
  - Q3. [TO BE DETERMINED] Should the chat ask "Jak oceniasz?" after an epic, with the G6 limits?
