# 035 — Learning which agent and strategy work best

Status: **draft**
Date: 2026-11-21
Depends on: [011](011-list-and-management.md), [022](022-model-lists-and-check.md), [032](032-ratings-and-sentiment.md), [033](033-reflection-and-playbooks.md)

## 1. TL;DR

For each task type in each space, Agentaro learns which agent, model, effort and playbook version give the highest reward. It uses Thompson sampling, a contextual bandit, which is real reinforcement learning at the level of choices. It mostly picks the best option and sometimes tries another. The director sees the ranking when planning. Tests with simulated rewards and a report confirm it.

## 2. Abstract

- **Current state:** the director assigns steps to agents by their descriptions only.
- **Gap or problem:**
  - Nothing tells the director which agent, model or effort actually pleased the owner for a kind of task.
  - Cost and time are not weighed.
- **Rationale:**
  - A bandit learns from rewards with very few samples, needs no training and stays explainable.
  - It is the classic, safe form of reinforcement learning for choosing among options.
- **Decision history:** owner's experiment framing, 2026-11-21.

## 3. Objective

**Goals**
- G1. **Task types.**
  - Each step gets a type, chosen by the director from a short list: research, writing, code, analysis, planning, other.
  - The list can grow, by the owner or by approved proposals.
- G2. **Arms.** An arm is a combination of agent, model, effort and playbook version. Only enabled agents in the team count.
- G3. **Learning.**
  - Per space and task type, each arm keeps a Beta distribution of reward (spec 032).
  - Each finished step updates its arm, weighted by reward confidence.
  - Old evidence decays slowly (Q2), so changes in models and playbooks count.
- G4. **Choosing.**
  - When planning a step, Agentaro samples the arms and gives the director a ranking with expected reward, cost and time.
  - The director keeps the final say and must state a reason when it skips the top arm.
  - Exploration is at most 10% of steps, never for irreversible work (spec 034).
- G5. **Cost-aware.** The score is reward minus a small cost and time penalty, which the owner sets (Q3).
- G6. **Report.** On the Brain page: per space and type, the arms with their mean reward, number of tries, cost and time, and the current favourite.

**Out of scope**
- Creating new agents automatically.
- Changing master prompts.

**Success criteria**
- S1. In a simulation with one clearly better arm, the favourite is that arm after 20 steps in at least 95% of runs.
- S2. In use, the report shows a favourite per task type after 4 weeks, and the mean reward of new steps is not lower than before.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `epic_steps.task_type` | to create |
| Data | `strategy_arms` (space, type, agent, model, effort, playbook version, alpha, beta, tries, cost, time) | to create |
| System | `Learning::Bandit` (Thompson sampling, decay) | to create |
| System | director planning prompt: ranking and the reason rule | to change |
| System | Brain page: strategy report | to change |

## 5. Functional Domain Changes

- **State:** the director chooses by description → by description and measured results.
- **Rules:**
  - R1. **The director decides.** The ranking is advice, and the reason is logged when the director skips the favourite.
  - R2. **Safe exploration.**
    - Never on irreversible or costly steps.
    - Never more than 10%.
    - Never with a disabled agent.
  - R3. **Explainable.** Every choice records the ranking it saw.
  - R4. **Own data only.** Arms are per user and space.
- **Resilience:** without enough data, the ranking is empty and the director chooses as today.
- **Data:** one column and one table. Rollback drops them.

## 6. Critical Path

1. Spec 032 in place.
2. Task types.
3. Arms and updates.
4. Ranking in planning.
5. Report.
6. Simulation tests (S1), security analysis; S2 after 4 weeks.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | Thompson sampling converges in simulation (S1); decay; exploration limit | `test/models/learning/bandit_test.rb` with a fixed seed | merge | no exploration on irreversible steps |
| Integration | a finished step updates its arm; planning prompt carries the ranking | `test/integration/strategy_test.rb` | merge | others' arms never used |
| Manual | S2 after 4 weeks | owner | — | — |

## 8. Expected Outcome

- **Direct effect:** steps go to the agent and model that do that kind of work best for this owner.
- **Measurable effect:** mean reward per task type; cost per epic.
- **Side effects:** about 10% of steps try a non-favourite option.
- **Rollback:** turn the ranking off; the director chooses as today.

## 9. Additional Information

- **Rejected alternatives:**
  - Full reinforcement learning or fine-tuning: not possible with hosted models and far too data-hungry.
  - Fixed routing rules: they do not learn.
- **Technical debt:** task types are coarse; refine after the report shows where they mix.
- **Sources and questions:**
  - Thompson sampling for Bernoulli/Beta bandits (standard method).
  - Q1. [TO BE DETERMINED] Is the task type list in G1 a good start?
  - Q2. [TO BE DETERMINED] Decay: half the weight after about 60 days?
  - Q3. [TO BE DETERMINED] Should cost and time matter at all, and how much? Proposed: a small penalty, so quality decides.
