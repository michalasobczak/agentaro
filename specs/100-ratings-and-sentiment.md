# 100 — Ratings and sentiment: one reward per result

Status: **closed** 2026-11-21 (the owner accepted the proposals for Q1–Q3, based on current market practice).
Date: 2026-11-21
Renumbered: was 032 until 2026-11-21 (set aside to return to later; numbers 032–099 stay for the work in between).
Depends on: [016](016-sequential-steps.md), [019](019-verifier.md), [031](031-brain-memory.md)

## 1. TL;DR

The user can rate an epic and each step with thumbs up or down; a thumbs down offers ready reasons ("too long", "wrong"…), and a comment is optional. Every user message about a result is also tagged with sentiment by the local model. Together with behaviour (accepted, corrected, retried, cancelled) and objective signals (verifier, failures, time), each epic and step gets one reward between 0 and 1: the mean of a Beta distribution, whose spread is also its confidence. Tests and demo data confirm the reward and its breakdown.

## 2. Abstract

- **Current state:**
  - Results are judged only by whether steps succeed.
  - The user's opinion is lost in the chat.
- **Gap or problem:** learning (specs 101–103) needs a signal that says how good a result was in the owner's eyes.
- **Rationale:**
  - An explicit rating is the strongest signal, but the owner will not rate everything.
  - Sentiment and behaviour fill the gaps automatically, including from voice.
- **Decision history:**
  - the owner accepted thumbs and ratings and sentiment of the owner's messages (2026-11-21);
  - the owner accepted thumbs with reasons, separately stored signals with a Beta reward, and rating inside the report (Q1–Q3, 2026-11-21);
  - sentiment runs on the local model (decision 1 of spec 031).

## 3. Objective

**Goals**
- G1. **Explicit ratings.**
  - On the epic page and its finished steps: 👍/👎 (Q2: no stars).
  - After 👎, ready reasons to click (more than one allowed): `too_long`, `wrong`, `not_what_i_asked`, `no_sources`, `too_slow`, `other`, shown in the user's language. After 👍 no reasons are asked.
  - An optional comment of at most 500 characters, either way.
  - In the chat, the same thumbs are part of the director's message that reports a finished epic (G6).
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
- G4. **Reward** (Q1).
  - Every signal is stored separately, with its source (`human`, `behaviour`, `verifier`, `sentiment`), value, weight, comment and time, as evaluation tools such as Langfuse and LangSmith do. The reward is derived from them, so weights can change later without losing data.
  - Per epic and per step, the reward is a Beta distribution starting at Beta(1, 1). Each signal adds its weight to α (positive) or β (negative); a signal between, such as weak sentiment, splits its weight.
  - The reward is the mean α / (α + β). Its confidence comes from the evidence: (α + β − 2) / (α + β), capped at 1.
  - α and β are stored, so spec 103 can sample from the same distribution (Thompson sampling).
  - The breakdown is stored and shown on hover.
- G5. **Episodes.** Every rating and tagged message becomes a memory episode (spec 031), so lessons can cite it.
- G6. **Rating in the report, rarely** (Q3). When an epic finishes, the director's report message carries the thumbs, with no separate question and nothing blocking. Limits:
  - at most once per epic and at most 3 times a day;
  - not when the user already said something about the result and sentiment caught it;
  - not for small epics: one step that took under 2 minutes;
  - unanswered, it fades by itself; no reminders;
  - it can be switched off in settings.

**Out of scope**
- Using the reward to change behaviour: specs 101–103.
- Rating other users' results.

**Success criteria**
- S1. Rating an epic 👎 with the reason "za długie" stores the rating, gives the epic a low reward and creates an episode.
- S2. Writing "świetna robota z backupami" after the Backups epic gives positive sentiment targeted at that epic.
- S3. An epic with no explicit rating still gets a reward from behaviour, with low confidence.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `ratings` (user, target type and id, thumbs, reasons, comment, created_at) | to create |
| Data | `feedback_signals` (user, target, kind, value, confidence, source message) | to create |
| Data | `rewards` (target, alpha, beta, value, confidence, breakdown JSON, computed_at) | to create |
| System | setting to switch the rating in reports off | to create |
| System | rating controls on the epic page, steps and the chat report message | to create |
| System | `Brain::Extractor`: sentiment fields | to change |
| System | `Reward.compute(target)`; recomputed on each new signal | to create |

## 5. Functional Domain Changes

- **State:** no feedback → feedback and reward per epic and step.
- **Rules:**
  - R1. **Weights** (Q1), added to α or β:
    - thumbs: 1.0;
    - correction or redo: 0.6, always negative;
    - sentiment: 0.4 × confidence, split by valence (−2..+2 maps to 0..1);
    - verifier: 0.3;
    - failure or timeout: 0.3, always negative;
    - accepted without changes: 0.2 (silence says little: often "not looked at", not "good").
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
- **Technical debt:** the weights are hand-set. Once about 30 thumbs exist, spec 102 can fit them to the owner's thumbs with a simple logistic regression.
- **Later:** a choice between two answer versions ("which is better?"), as ChatGPT and Claude do, gives the cleanest signal for learning; it belongs to specs 103–104.
- **Sources and questions:**
  - Q1. Weights: each signal stored separately; reward as a Beta distribution with the R1 weights; "accepted" lowered from 0.3 to 0.2. (Owner, 2026-11-21: as proposed.)
  - Q2. Thumbs only, with ready reasons after 👎 and an optional comment; no stars. Market practice: ChatGPT, Claude, Gemini and Copilot use thumbs; star scales for model answers are read differently by each person and cost more effort. (Owner: as proposed.)
  - Q3. Yes, but as thumbs inside the director's report, not a separate question, with the G6 limits and a switch. (Owner: as proposed.)
  - Sources: feedback controls of ChatGPT, Claude, Gemini and Copilot; score models of Langfuse and LangSmith; Beta–Bernoulli rewards as used for Thompson sampling.
