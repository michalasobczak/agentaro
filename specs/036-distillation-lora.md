# 036 — Distillation into a local model (LoRA)

Status: **draft**
Date: 2026-11-21
Depends on: [030](030-run-traces.md), [031](031-brain-memory.md), [032](032-ratings-and-sentiment.md), [033](033-reflection-and-playbooks.md), [034](034-owner-model-and-questions.md), [035](035-strategy-selection.md)

## 1. TL;DR

The data gathered by specs 031–035 is turned into training sets for a small local model. That data is the owner's messages, ratings, corrections, accepted results, the judge's calibrated cases and the playbooks. The model is trained on this Mac with LoRA adapters (MLX). First it learns the brain's own jobs: extraction, sentiment and the judge of the owner's taste. Later it may learn routine work tasks. An adapter goes live only when it beats the current model on a held-out set of the owner's rated cases. Full training is not proposed.

## 2. Abstract

- **Current state:**
  - Specs 031–035 make the agents better through context (memory, playbooks) and choice (bandit).
  - The local model used for extraction is generic.
- **Gap or problem:** the owner wants the learning to land in model weights as well: "zrobić dystylację… adapter LoRA lub full trening".
- **Rationale:**
  - A model tuned on the owner's own judgements makes the judge and extractor more accurate, cheaper and fully local.
  - Over time it can also take routine tasks from paid models.
- **Constraints found:**
  - The owner's Mac has 16 GB of unified memory. That fits QLoRA (4-bit) training of models up to about 8B parameters, slowly, and of 3–4B models comfortably.
  - Full training of such models does not fit in memory, and a few thousand examples are too few for it.
- **Decision history:** extraction on a local model (031, decision 1).

## 3. Objective

**Goals**
- G1. **Datasets,** built nightly from the run traces (spec 030) and the brain. Each example is tied to its episodes and traces, and uses the exact prompt parts the model saw:
  - **Extraction and sentiment (SFT):** messages paired with the operations and tags the owner approved or did not correct. Corrections give the right answer.
  - **The owner's taste (judge):** a result paired with the owner's explicit rating and comment.
  - **Preferences:**
    - pairs where the owner chose or corrected one version over another (for DPO);
    - single results with 👍/👎 (for KTO, which does not need pairs).
  - **Routine work (SFT, later, Q2):** tasks with results the owner rated 4–5 (rejection sampling: only the best become examples).
- G2. **Training.**
  - LoRA or QLoRA adapters on a local base model with MLX (`mlx-lm`) on this Mac.
  - One adapter per job (extractor, judge, later worker), so each can be tested and rolled back alone.
  - Training runs at night, only when no epic runs and the Mac is on power. The owner can start or stop it.
- G3. **Evaluation gate.**
  - A held-out set (20% of the owner's rated cases, never used for training) scores each new adapter against the current model, on:
    - extraction accuracy;
    - agreement of the judge with the owner (±1 star);
    - for workers, the judge's predicted stars plus the owner's ratings in use.
  - An adapter goes live only if it is better and not worse on any earlier held-out case type.
- G4. **Serving.** Adapters are served by the local runtime: Ollama with a LoRA adapter, or `mlx-lm` serving. The brain switches to the new adapter, and the previous one stays for one-click rollback.
- G5. **Report.** On the Brain page, for each adapter:
  - the dataset size;
  - the training date;
  - the held-out scores against the current model;
  - its state: candidate, live or retired.

**Out of scope**
- Full fine-tuning (see section 9).
- Training on other users' data or on public data.
- Sending any training data off this Mac.

**Success criteria**
- S1. After about 300 rated cases, the judge adapter agrees with the owner more often than the untuned base model on the held-out set.
- S2. The extractor adapter reduces the share of facts the owner deletes as wrong (spec 031).
- S3. Rollback to the previous adapter takes one click and applies to the next call.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `training_examples` (job, input, target or preference, episodes, split train/held-out) | to create |
| Data | `adapters` (job, base model, path, dataset hash, scores, state) | to create |
| Files | `storage/training/` (JSONL datasets, adapters; not tracked) | to create |
| System | `Learning::DatasetBuilder`, `Learning::Trainer` (calls `mlx-lm` as a fixed preset), `Learning::AdapterGate` | to create |
| System | brain settings: which adapter serves which job | to change |
| External | Python venv with `mlx-lm` in `storage/training/venv` (like the voice venv) | [TO BE DETERMINED] Q1 |
| External | base model weights | [TO BE DETERMINED] Q1 |

## 5. Functional Domain Changes

- **State:** a generic local model → local adapters tuned on the owner's judgements.
- **Rules:**
  - R1. **Data the owner stands behind.**
    - Examples come only from the owner's ratings, corrections, approvals and accepted results.
    - Agent text alone and web or file content are never targets.
    - Rejected and deleted facts are negatives or are excluded.
  - R2. **Held-out stays held out.** The 20% evaluation split is fixed per example and never trained on.
  - R3. **Terms of the teacher models.**
    - Using outputs of hosted models (Claude, Codex) as training targets must comply with their providers' terms, so the owner confirms this before any such dataset is built (Q3).
    - Datasets from the owner's own words, ratings and corrections are not affected.
  - R4. **Private by design.**
    - Datasets and adapters stay in `storage/training/`, are never committed, and contain no secrets.
    - The same filters as spec 031 R7 apply.
  - R5. **Forget means forget.** A fact or message the owner deletes is removed from future datasets. An adapter trained on it is marked stale and retrained at the next run.
  - R6. **Fixed programs.**
    - Training is started only through a fixed preset (program and arguments in code), as with executors (spec 008).
    - It runs in its own process group so it can be stopped.
- **Resilience:**
  - If training fails or runs out of memory, the current adapter stays.
  - If a training run would overlap an epic step, it is postponed.
- **Data:** two tables; files outside the repo.

## 6. Critical Path

1. Specs 031–034 running for a few weeks, so enough rated cases exist. Proposed minimum: 200 for the judge, 500 for the extractor.
2. Owner answers Q1–Q4.
3. Dataset builder with splits.
4. Trainer preset and night schedule.
5. Gate and serving with rollback.
6. Tests with a tiny model, then the first real adapter (judge), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | dataset builder respects R1, R2, R5; gate compares scores correctly | `test/models/learning/dataset_test.rb`, `adapter_gate_test.rb` | merge | deleted facts and agent-only text never in a dataset |
| Integration | a candidate adapter with worse held-out scores is not promoted; rollback restores the previous one | stubbed trainer | merge | no training while a step runs |
| Manual | first judge adapter trained on this Mac; S1 measured | owner + report | release | memory and temperature acceptable during the night |

## 8. Expected Outcome

- **Direct effect:** the brain's judge and extractor are tuned to the owner, local and free to run.
- **Measurable effect:**
  - judge agreement with the owner;
  - wrong-fact rate;
  - later, the share of routine steps handled locally.
- **Side effects:**
  - night-time CPU/GPU load;
  - several GB for base models and adapters.
- **Rollback:** switch each job back to the base model; delete adapters.

## 9. Additional Information

- **Proposal: LoRA, not full training.**
  - With hundreds to a few thousand examples, LoRA reaches most of the gain of full fine-tuning. It forgets much less of the base model's general ability, trains on this Mac and can be swapped or removed in a second.
  - Full training of a useful model needs far more data, memory and GPU time than this Mac has. It would also overwrite general skills with a small personal dataset.
  - Revisit only if the data grows to tens of thousands of examples and LoRA stops improving. Then it would mean rented GPUs, which conflicts with keeping data on the Mac.
- **Proposed order:**
  1. The judge (G1 taste): the most valuable, since it drives spec 034's autonomy.
  2. The extractor and sentiment.
  3. KTO/DPO preference tuning of the judge.
  4. Only then a worker adapter for one routine task type that spec 035 shows the local model nearly handles already.
- **Rejected alternatives:**
  - Full fine-tuning (above).
  - Cloud fine-tuning services (data leaves the Mac).
  - Distilling everything into one model (cannot test or roll back per job).
- **Technical debt:** a new base model means retraining all adapters.
- **External dependencies:** MLX and `mlx-lm` (Apple Silicon); Ollama LoRA adapter support; base model licences.
- **Sources and questions:**
  - LoRA (arXiv 2106.09685); QLoRA (arXiv 2305.14314); DPO (arXiv 2305.18290); KTO (arXiv 2402.01306); MLX LoRA fine-tuning in `mlx-lm`.
  - Q1. [TO BE DETERMINED] Base model:
    - proposed `Qwen3-4B` for the judge and extractor (comfortable in 16 GB);
    - `Qwen3-8B` only if 4B is not good enough (QLoRA, slower, tight on memory).

    Install `mlx-lm` in a venv like the voice tools?
  - Q2. [TO BE DETERMINED] Worker adapters for routine tasks: in scope later, or never?
  - Q3. [TO BE DETERMINED] The owner checks the terms of Claude and Codex before their outputs are used as training targets. Until then, only the owner's own data is used (judge and extractor datasets).
  - Q4. [TO BE DETERMINED] Training window: proposed 01:00–06:00, on power, no epic running.
