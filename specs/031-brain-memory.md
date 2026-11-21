# 031 — Brain: long-term memory about the user, agents and spaces

Status: **draft**
Date: 2026-11-21
Depends on: [030](030-run-traces.md), [004](004-data-changelog.md), [011](011-list-and-management.md), [013](013-projects.md), [022](022-model-lists-and-check.md)

## 1. TL;DR

Agentaro gets a local long-term memory, the "brain". It has three layers:
- **core blocks**, always in the prompt: the user's profile, a brief per space and a playbook per agent;
- **temporal facts**, which are superseded instead of deleted;
- **episodes**, the evidence each fact comes from.

A local model through Ollama extracts facts after each conversation turn. Retrieval combines keyword and meaning search. A Brain page shows and edits everything. Tests and a demo conversation confirm that a fact said once is used later without asking again.

## 2. Abstract

- **Current state:**
  - The director sees only the current conversation, the team and the spaces' epics.
  - Nothing the user says is kept beyond the chat history.
  - Agents start every step from their master prompt alone.
- **Gap or problem:**
  - The owner repeats preferences and answers the same questions.
  - Agents do not know what was decided earlier in a space.
  - The owner: "w końcu potrzebujemy mózg… żeby cokolwiek o mnie przechowywać, przechowywać o agentach, projektach/spaces".
- **Rationale:**
  - Memory is the base for learning from ratings (specs 032–035) and for asking fewer questions.
  - The design takes proven patterns and adds no new services:
    - Letta's core blocks;
    - Graphiti's temporal facts;
    - Mem0's ADD/UPDATE/INVALIDATE extraction;
    - local hybrid FTS5 + sqlite-vec retrieval.
- **Decision history (owner, 2026-11-21):**
  - extraction runs on a local model;
  - learned changes may apply automatically after a gate, except changes to the user's profile, which the user approves;
  - Mem0, Zep/Graphiti and Letta as external services were rejected (Python services, extra databases, data outside the audit trail).

## 3. Objective

**Goals**
- G1. **Core blocks.** One block per scope, each at most about 2,000 characters, and each in the prompt of every run in its scope:
  - `user`: the profile;
  - `space`: one per space, with goal, decisions and conventions;
  - `agent`: one per agent, the playbook, which spec 033 fills.
- G2. **Facts.**
  - Each fact is a short statement about a subject: the user, a space or an agent. It has a kind (preference, decision, fact about the world, constraint), `valid_from`, `invalid_at`, a confidence, and links to its source episodes.
  - A newer contradicting fact invalidates the older one, which stays in history.
- G3. **Episodes.** These record user messages, director answers, epic outcomes and blocks, and later ratings (spec 032). They are pointers to existing rows plus a short text, not copies of whole runs.
- G4. **Extraction.**
  - After each director conversation turn and each finished epic, a background job asks the local model for operations on memory: ADD, UPDATE, INVALIDATE or NOOP, each with its source.
  - Agentaro validates the operations against a schema and applies them. Each one is recorded in the data changelog (spec 004).
- G5. **Retrieval.**
  - Before each director run and each step, Agentaro adds the core blocks of the scope and the top facts for the task to the prompt, at most 12 facts or about 1,500 characters.
  - Ranking fuses FTS5 and vector similarity with Reciprocal Rank Fusion, and prefers valid, confident, recent facts.
  - Without embeddings, FTS5 alone is used.
- G6. **Nightly consolidation.** A daily job merges duplicate facts, resolves contradictions, lowers the confidence of facts never used or contradicted, and archives the weakest.
- G7. **The Brain page.**
  - It shows the core blocks and the facts by scope, each fact with its source, history and the time it was last used.
  - The user can edit or delete any of them, and can pin a fact so it is never archived.
- G8. **"Remember" and "forget" in the chat.** "Zapamiętaj, że…" and "zapomnij o…" become operations at once and are confirmed in the reply.

**Out of scope**
- Ratings, sentiment and lessons: specs 032 and 033.
- When to ask the user: spec 034.
- Sharing memory between users. Memory is always per user.
- Memory from web pages or files that agents read.

**Success criteria**
- S1. The owner says in chat "raporty zawsze po polsku i krótko". A day later, a new epic's step prompt carries that preference, and the result follows it without the owner repeating it.
- S2. The owner later says "raporty po angielsku". The old fact is invalid and the new one is used; both appear in the fact's history.
- S3. On the Brain page the owner can see why a fact exists (its source message) and delete it. After deletion it is no longer in prompts.
- S4. With Ollama stopped, conversations and steps work as before. Extraction waits and catches up later.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `memory_blocks` (user, scope type and id, text, version) | to create |
| Data | `memory_facts` (user, subject, kind, statement, confidence, valid_from, invalid_at, superseded_by, pinned, last_used_at) | to create |
| Data | `memory_episodes` (user, kind, source type and id, text, occurred_at) and `memory_fact_sources` | to create |
| Data | FTS5 virtual table over facts; vector table (sqlite-vec) for embeddings | to create |
| System | `Brain::Extractor` (local model, JSON operations, validation) | to create |
| System | `Brain::Retriever` (hybrid ranking, prompt section) | to create |
| System | `Brain::Consolidator` (nightly) | to create |
| System | `ManagementRunner` and step prompts: memory section | to change |
| System | Brain page (`BrainController`, views, `desktop-only` editing on phones if needed) | to create |
| System | Settings: which Ollama executor and models the brain uses | to create |
| External | Ollama with an extraction model and an embedding model | [TO BE DETERMINED] Q1 |
| External | `sqlite-vec` extension available to Ruby | [TO BE DETERMINED] Q2 |

## 5. Functional Domain Changes

- **State:** no memory → per-user memory used in every run.
- **Rules:**
  - R1. **Only the user's own words create facts about the user.**
    - Facts are extracted from user messages, the user's edits and (later) ratings.
    - Director answers and agent outputs can create facts about spaces only as decisions the user confirmed (a user reply such as "ok", or a finished epic the user did not reject). They never create facts about the user.
    - Text that agents read from the web or files never creates facts. This guards against prompt injection.
  - R2. **Profile changes need approval.**
    - Facts about the user that come from extraction start as *proposed* and are not used until the user approves them on the Brain page or in the chat.
    - "Remember…" said by the user is approved at once.
    - Space and agent facts apply directly (the owner's decision 2).
  - R3. **Supersede, do not delete.** A contradiction sets `invalid_at` and `superseded_by`. Only the user deletes, and deletion is permanent.
  - R4. **Bounded prompts.** Core blocks plus facts never exceed the set budget. The lowest-ranked facts are dropped first.
  - R5. **Memory is data, not instructions.** The prompt section is labelled as remembered context. Facts cannot change the director's allowed actions.
  - R6. **Validation.**
    - Extraction output must match the schema: known operation, subject in the user's own scope, statement at most 300 characters.
    - Anything else is rejected and logged.
  - R7. **Privacy.**
    - Memory never leaves the Mac. The local model is called on localhost only.
    - Secrets are not stored: statements that look like keys, passwords or tokens are rejected.
- **Resilience:**
  - Extraction and consolidation are background jobs.
  - If Ollama is down they retry later and nothing else waits.
  - If the vector extension is missing, retrieval uses FTS5 only.
- **Data:**
  - Four new tables, one FTS5 table and one vector table.
  - Episodes point to existing rows and keep a short excerpt.
  - Rollback drops these tables only.

## 6. Critical Path

1. Spec 030 (run traces) in place. Owner answers Q1–Q5; models pulled; sqlite-vec checked.
2. Tables, models, FTS5; core blocks with the Brain page (manual editing first, useful on its own).
3. Retrieval into director and step prompts.
4. Extractor with validation and the data changelog; "remember/forget" in chat.
5. Embeddings and hybrid ranking.
6. Nightly consolidation.
7. Tests, demo conversation (S1–S4), security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | extraction output validated; supersede keeps history; ranking fuses both lists; budget respected | `test/models/brain/*_test.rb` with a stub model | merge | facts from agent output or web text never about the user; secrets rejected |
| Integration | a remembered fact appears in the next director and step prompt; deleted fact disappears; another user's memory never appears | `test/integration/brain_test.rb` | merge | no inline style or script; 404 on others' facts |
| Contract | Ollama request and response shape; down Ollama → retry, no error to the user | stubbed HTTP | merge | no call to a non-local host |
| E2E | S1–S4 on demo data with a real local model | browser + demo DB | release | — |
| Manual | owner reads the Brain page after a week of use and judges the facts useful | owner | — | — |

## 8. Expected Outcome

- **Direct effect:** the director and agents know the owner's preferences and earlier decisions per space.
- **Measurable effect:**
  - fewer repeated questions;
  - the share of facts the owner deletes as wrong is under 20% after a week (the extraction quality check).
- **Side effects:**
  - local model load after each turn, in the background;
  - a little more prompt text per run.
- **Rollback:** turn the brain off in settings; drop the new tables.

## 9. Additional Information

- **Rejected alternatives:**
  - Mem0, Zep/Graphiti, Letta as services;
  - a separate vector database;
  - Claude for extraction (owner's decision 1: local).
- **Technical debt:** no graph traversal between facts (only subject links). Add it if retrieval misses related facts.
- **External dependencies:** Ollama (installed, no models yet); sqlite-vec.
- **Sources and questions:**
  - Q1. [TO BE DETERMINED] Models:
    - proposed `qwen3:8b` for extraction (good at JSON, handles Polish);
    - proposed `bge-m3` for embeddings (multilingual).
    - Pull both (about 6 GB)?
  - Q2. [TO BE DETERMINED] If sqlite-vec cannot be loaded cleanly from Ruby, is FTS5-only acceptable for the first version?
  - Q3. [TO BE DETERMINED] Should the profile be approved fact by fact, or by a daily summary "I learned these 5 things about you — keep?"? Proposed: the daily summary in the chat.
  - Q4. [TO BE DETERMINED] Prompt budget: 12 facts / about 1,500 characters. Is that enough?
  - Q5. [TO BE DETERMINED] Should old chat history (before this spec) be imported into memory once? Proposed: yes, as a one-off job, with the resulting profile facts proposed for approval.
  - Research: Letta core memory; Graphiti temporal facts; Mem0 extraction; vstash (arXiv 2604.15484); MemConflict (arXiv 2605.20926); Retrieval-Driven Memory Reconsolidation (arXiv 2609.16053).
