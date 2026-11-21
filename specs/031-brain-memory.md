# 031 — Brain: long-term memory about the user, agents and spaces

Status: **closed** 2026-11-21 (the owner's answers to Q1–Q2 and acceptance of the proposals for Q3–Q5); **implemented** 2026-11-21.
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
  - Memory is the base for learning from ratings (specs 100–103) and for asking fewer questions.
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
  - `agent`: one per agent, the playbook, which spec 101 fills.
- G2. **Facts.**
  - Each fact is a short statement about a subject: the user, a space or an agent. It has a kind (preference, decision, fact about the world, constraint), `valid_from`, `invalid_at`, a confidence, and links to its source episodes.
  - A newer contradicting fact invalidates the older one, which stays in history.
- G3. **Episodes.** These record user messages, director answers, epic outcomes and blocks, and later ratings (spec 100). They are pointers to existing rows plus a short text, not copies of whole runs.
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
- Ratings, sentiment and lessons: specs 100 and 101.
- When to ask the user: spec 102.
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
| External | Ollama with `qwen3:8b` and `bge-m3` | exists (Q1) |
| External | `sqlite-vec` gem (loadable extension; fallback: cosine in Ruby) | to add (Q2) |

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
- **External dependencies:** Ollama with `qwen3:8b` and `bge-m3`; the `sqlite-vec` gem.
- **Sources and questions:**
  - Q1. Models: `qwen3:8b` for extraction, `bge-m3` for embeddings. (Owner, 2026-11-21: yes; pulled into Ollama.)
  - Q2. sqlite-vec. Checked 2026-11-21:
    - the bundled SQLite (3.54.1, `sqlite3` gem 2.10.2) allows loading extensions and has FTS5;
    - the `sqlite-vec` gem (0.1.9) ships a build for Apple Silicon.

    It is expected to work. If it ever does not load (a future gem or SQLite change, or the extension being pre-1.0), the fallback is embeddings as BLOBs with cosine similarity computed in Ruby. That is a few milliseconds for thousands of facts, so meaning search stays. FTS5 alone is only the last resort, when Ollama is down. (Owner asked why it might fail; answered.)
  - Q3. Profile facts are approved in a daily summary in the chat ("I learned these things about you — keep?"), not one by one. (Owner, 2026-11-21: as proposed.)
  - Q4. Prompt budget: at most 12 facts, about 1,500 characters. (Owner: as proposed.)
  - Q5. The chat history from before this spec is imported once, by a one-off job. The resulting profile facts are proposed for approval. (Owner: as proposed.)
    **Withdrawn the same day.** The import ran in production and gave poor facts: one-off requests ("cancel item", "check the latest trends") and wrong invalidations of facts still waiting. The owner: "wycofaj tę historię słabej jakości, możemy popracować nad świeżymi danymi". Its facts, episodes and runs were deleted (backup first), and the page no longer offers it. `bin/rails agentaro:brain:import_history` stays for a later, deliberate try.
  - Research: Letta core memory; Graphiti temporal facts; Mem0 extraction; vstash (arXiv 2604.15484); MemConflict (arXiv 2605.20926); Retrieval-Driven Memory Reconsolidation (arXiv 2609.16053).

## Implementation notes (2026-11-21)

- **Data:** migration `20261121131000`.
  - Tables: `memory_blocks`, `memory_facts` (with `supersedes`/`superseded_by`, pin, use count and a float32 vector), `memory_episodes` (with retry fields) and `memory_fact_sources`.
  - FTS5 table `memory_facts_fts` (unicode61, diacritics removed), kept in step by the fact model.
- **Vectors without sqlite-vec (Q2 fallback, chosen now).**
  - Vectors are BLOBs, and cosine similarity is computed in Ruby over the candidate facts of one prompt (the user's, the space's and the agent's).
  - At this size it takes milliseconds and needs no native extension in the server. sqlite-vec can come later if the memory grows to tens of thousands of facts.
  - Keyword and meaning ranks are fused with RRF (k = 60), plus pinning, confidence and recency.
  - When a scope has at most 12 facts, all of them go in, so a fresh preference is used even when the task's words do not match it (S1).
- **Where memory goes** (a section named `memory`, so the run trace shows it, spec 030):
  - chat answers and proposal passes: the user's facts and facts about every active space;
  - epic planning: the epic's space and the director's playbook;
  - each step: its space and the step agent's playbook.

  The verifier's prompt and old calendar tasks get none.
- **Extraction.**
  - The scheduler starts it in its own thread, up to 5 waiting messages at a time, with `qwen3:8b` in JSON mode, thinking off, temperature 0.
  - Each call is a run with the purpose `memory`, with its trace.
  - If the server is down, it retries after 2, 4, 8… minutes and gives up after 6 attempts.
  - Episodes of director answers and epic outcomes are kept as evidence but not extracted (R1, the stricter reading); spec 101 uses them.
- **R2.**
  - A profile fact added or changed by extraction waits as *proposed*; an update keeps the old fact in force until the new one is kept.
  - An INVALIDATE of the user's own fact applies at once, since it comes from the user's own words.
- **Chat actions** (G8): `remember`, `forget`, `approve_facts`, `reject_facts`.
  - They are accepted only when the user's latest message asks for it (remember, forget, keep, drop, in Polish or English).
  - `forget` makes the fact no longer true (history kept); permanent deletion is on the Brain page (R3).
- **Daily** (G6, Q3):
  - duplicates are merged (same text, or cosine ≥ 0.95);
  - facts unused for 60 days lose 10% confidence, and below 0.2 they are archived, unless pinned;
  - missing vectors are computed;
  - after 09:00, profile facts waiting for approval are listed in the chat, in Polish when the conversation is.

  Contradictions are resolved on arrival: the extractor sees the related facts and updates or invalidates them.
- **History import** (Q5): a button on the Brain page and `bin/rails agentaro:brain:import_history`, once per user.
- **Settings:** `AGENTARO_BRAIN_URL` (localhost only, R7), `AGENTARO_BRAIN_MODEL`, `AGENTARO_BRAIN_EMBEDDING_MODEL`. The Brain page shows whether the server and both models are there.
- **Data changelog.** Facts, blocks and episodes are recorded; use counts and vectors are not (`changelog_ignored`). A deleted space or agent takes its facts and block along.
- **Checks.**
  - Tests: `test/models/brain_test.rb` (15), `test/integration/brain_page_test.rb` (7). Tests use a stand-in model server; the real one is never called.
  - Full suite: 392 runs, 0 failures.
  - Real models on demo data: about 5 s per message. "Raporty zawsze po polsku i krótko…" became a proposed profile fact. A space decision applied at once. "Zmiana: raporty jednak po angielsku" became an update of that fact, and after approval the old one was history (S2). Greetings and one-off requests gave nothing. The step's prompt carried the facts (S1).
  - The Brain page at 719 px had no horizontal scroll.

## Security analysis (B20), after spec 031

- **Injection (R1, R5).**
  - Facts come only from the user's messages, the user's edits and explicit remember requests. Director answers, step outputs, web and file content never create facts.
  - The extractor's context labels earlier messages as context only.
  - In prompts, memory is labelled as data, not instructions. It cannot add actions, and the working folder is still set only on the space form (B20 after spec 021).
  - A remember, forget or approve action is refused unless the user's own latest message asks for it (test).
- **Validation (R6).**
  - Only known operations are accepted, on the user's own spaces and agents and the user's own facts.
  - Statements are at most 300 characters, and secrets are rejected with the run-trace filter (spec 030 R2) (tests).
- **Access.**
  - Facts, blocks and the history import are limited to the signed-in user. Another user's fact is 404, and a block for another user's space is refused (tests).
  - Memory is per user; retrieval queries only the user's rows.
- **Local only (R7).**
  - The model server must be on localhost; another host raises an error before any call (test).
  - Memory, episodes and traces stay in `storage/`, which is never committed.
- **Search.** FTS5 terms are reduced to letters and digits and quoted, so a message cannot inject FTS syntax; values are bound.
- **Rendering.**
  - The page prints through ERB escaping (a test shows `<b>` escaped). There are no inline styles or scripts.
  - The daily summary goes through the chat's existing safe Markdown.
- **Load.**
  - One extraction thread, at most 5 messages per scheduler pass, with exponential retry.
  - Query embeddings have a 3-second limit, after which only keyword search is used.
- **Earlier specs.**
  - Spec 004: usage bookkeeping skips the changelog; real changes do not.
  - Spec 025: space deletion also removes the space's memory.
  - Spec 030: memory runs are traced.
  - No regressions found.
- **Tools.** Brakeman: 0 warnings. No new gems.

## Fixes after deployment (2026-11-21)

- **The worker stayed locked after its first pass.**
  - The mutex was locked in the scheduler thread and unlocked in the worker thread, which raises `ThreadError`, so extraction never ran again.
  - Now a `@running` flag is set and cleared under a short lock.
  - Test: two passes in a row both extract.
- **Ids with copied text.** The model sometimes answered an UPDATE id as the whole known-facts line. The leading number is read as the id (test).
- **Extraction quality, after the import.**
  - The prompt now lists what is never remembered: requests to do, check, cancel, move or plan something, questions, thanks, single-task remarks. It also says "when unsure, remember nothing".
  - Facts below confidence 0.6 are dropped.
  - Extraction may update or invalidate only facts in force, never one waiting for the user (R2).
  - Tests cover both rules.

