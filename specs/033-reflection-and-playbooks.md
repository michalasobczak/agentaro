# 033 — Reflection and playbooks: agents learn from rated results

Status: **draft**
Date: 2026-11-21
Depends on: [031](031-brain-memory.md), [032](032-ratings-and-sentiment.md)

## 1. TL;DR

After each rated epic, a reflection pass writes what worked and what did not. A curator then turns that into small edits of the agent's playbook and the space brief (core blocks of spec 031). An edit applies only if it does not lower the score on a replay set of the owner's past rated cases. Each playbook is versioned and can be rolled back in one click.

## 2. Abstract

- **Current state:**
  - An agent's behaviour changes only when the owner edits its master prompt.
- **Gap or problem:**
  - The owner's corrections are lost.
  - The same mistakes come back in the next epic.
- **Rationale:**
  - Reflection-based learning (Reflexion) and evolving playbooks (ACE, GEPA) improve agents without training model weights. This is the "reinforcement" that is possible with hosted models.
  - ACE showed that small incremental edits beat rewriting the whole context, which loses knowledge over time.
- **Decision history:** the owner accepted automatic changes after a gate (2026-11-21, decision 2). Profile changes stay with the owner (spec 031, R2).

## 3. Objective

**Goals**
- G1. **Reflection.** It runs when an epic or step gets a reward with confidence ≥ 0.5 (spec 032), and once a day for the rest. It uses the director's model, which decides how well the lesson is written.
  - **Input:**
    - the plan, the step outputs (truncated);
    - the reward and its breakdown;
    - the owner's comments and the relevant messages.
  - **Output:** at most 3 lessons. Each lesson has:
    - a rule in one sentence;
    - its scope (agent, space, or task type);
    - its evidence (episode ids);
    - "do" or "avoid".
- G2. **Curator.** It turns lessons into playbook edits:
  - **add** a rule, **sharpen** an existing rule, or **remove** a rule that newer evidence contradicts;
  - each rule keeps counters (helped, hurt) and its sources;
  - the playbook stays within its size limit; the weakest rules leave first.
- G3. **Replay gate.**
  - The replay set holds the owner's past cases with explicit ratings: the task, the result and the rating.
  - Before an edit applies, a judge (spec 034; until then, a rubric from the owner's comments) scores a sample of up to 10 cases twice: with the old playbook and with the new one.
  - The edit applies only if it does not lower the mean and fixes the case it came from.
  - While the set has fewer than 5 cases, edits apply directly and are marked "unverified".
- G4. **Versions.** Every playbook and brief change is a new version, with its diff, its lessons and the gate result. The Brain page shows the history; Roll back restores any version.
- G5. **Weekly digest.** In the chat, once a week: what each agent learned, with links. It is short and fits the director's language.

**Out of scope**
- Changing master prompts. Playbooks sit beside them.
- Changing models or which agent does what: spec 035.

**Success criteria**
- S1. After the owner rates an epic 2/5 with "brak źródeł", the researcher's playbook gains a rule about sources. The next research epic follows it.
- S2. An edit that lowers the replay score is rejected and logged with the reason.
- S3. Rolling back a playbook restores the earlier text in the next run.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `lessons` (scope, rule, kind, evidence, counters, state) | to create |
| Data | `memory_blocks` versions (diff, lessons, gate result) | to change (spec 031) |
| Data | `replay_cases` (task, result reference, rating) | to create |
| System | `Learning::Reflector`, `Learning::Curator`, `Learning::ReplayGate` | to create |
| System | Brain page: playbook history, Roll back | to change |
| System | weekly digest message | to create |

## 5. Functional Domain Changes

- **State:** static agents → agents whose playbooks evolve from the owner's feedback.
- **Rules:**
  - R1. **Evidence only from the owner.** A lesson must cite at least one episode that comes from the owner: a rating, a comment or a message. Agent output can be context, never evidence.
  - R2. **Small steps.** At most 3 edits per epic and 10 per agent per day.
  - R3. **The gate decides.** No edit without passing G3, except while bootstrapping, as described there.
  - R4. **Visible.** Every edit is in the data changelog and the digest; none is silent.
  - R5. **Bounded cost.**
    - Replay runs use the judge, not full re-runs of agents.
    - At most N judge calls a day (Q2).
- **Resilience:** reflection and the gate are background jobs. On failure, the edit waits; nothing changes.
- **Data:** new tables; versions on memory blocks.

## 6. Critical Path

1. Spec 031 and 032 in place.
2. Reflector.
3. Curator with versions.
4. Replay set and gate.
5. Digest.
6. Tests, demo (S1–S3), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | lessons need owner evidence; curator edits within limits; gate accepts or rejects by score | `test/models/learning/*_test.rb` with stub models | merge | a lesson from agent text alone is rejected |
| Integration | a rated epic leads to a playbook version used in the next step prompt; rollback restores | `test/integration/learning_test.rb` | merge | other users' playbooks untouched |
| E2E | S1–S3 on demo data | browser | release | — |
| Manual | owner reads two weekly digests and judges the lessons right | owner | — | — |

## 8. Expected Outcome

- **Direct effect:** mistakes the owner pointed out stop coming back.
- **Measurable effect:**
  - mean reward per agent rises over 4 weeks;
  - fewer "redo" signals.
- **Side effects:** extra director-model calls for reflection and judging (bounded by R5).
- **Rollback:** turn learning off; roll playbooks back to their first version.

## 9. Additional Information

- **Rejected alternatives:**
  - Rewriting the whole prompt each time (loses knowledge).
  - Fine-tuning (not available for hosted models; local fine-tuning is a later option).
- **Technical debt:** the replay judge is approximate until spec 034 calibrates it.
- **Sources and questions:**
  - Reflexion (arXiv 2303.11366); ACE, Agentic Context Engineering (arXiv 2510.04618); GEPA (arXiv 2507.19457).
  - Q1. [TO BE DETERMINED] Should reflection use the director's model (proposed: better lessons) or the local model (free, weaker)?
  - Q2. [TO BE DETERMINED] Daily limit of judge calls. Proposed: 50.
  - Q3. [TO BE DETERMINED] Weekly digest in the chat: which day? Proposed: Monday morning.
