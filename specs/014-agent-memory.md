# 014 — Agent memory and context

Status: **draft**
Date: 2026-11-19
Depends on: [009](009-agents.md), [010](010-task-execution.md), [011](011-list-and-management.md)

## 1. TL;DR

Each agent (spec 009) gets a **memory graph** that holds what it has learned, and the context for a task is assembled from its master prompt and the most relevant memories. The memory is designed so that the self-improvement spec (015) can reorganize it on a schedule. Confirmed by tests of the memory model, revisions and context assembly, and by a browser walk-through.

## 2. Abstract

**Current state.** Agents with a master prompt and an executor, assignable to tasks (spec 009); running tasks comes in spec 010.

**Need (owner, 2026-11-19).** Split off from spec 009 by the owner ("memory/context next next"). Original request: "I wanna create agents with executor as runtime parameter. agent should be assignable to the task. agent by itself should have its own master prompt like a definiton who it is. But true identity of that person should come from its memories stored as optimal as possible. I dont like that KV is optimal, let it be more like graph … remember that later onwards (next spec) i will require you to implement self improvement, so its memory database should be reorganized once a while (like a schedule, maybe nighly or after each task done)."

**Industry practice (2026).** Agent memory systems converge on the same layers:
- **Core memory**, always in the prompt: a short description of who the agent is (Letta's "core memory blocks").
- **Episodic memory**: what happened, when, with whom; a stream of events (Generative Agents' "memory stream", Letta's recall memory).
- **Semantic memory**: facts, people, preferences and beliefs as a **temporal knowledge graph**, where each fact has a validity period, and outdated facts are invalidated instead of deleted (Zep/Graphiti). Graphs beat flat key-value or vector-only memory on long-term memory benchmarks, though the published numbers are mostly vendors' own.
- **Procedural memory**: how the agent does things; lessons learned.
- **Reflection / consolidation**: a periodic pass that turns episodes into facts, merges duplicates, resolves contradictions, lowers the weight of what is never used and rewrites the self-description ("reflection" in Generative Agents, "sleep-time" processing in Letta).

Retrieval mixes relevance (text search, optionally embeddings), graph neighbourhood, recency and importance.

**Proposal.** Keep this inside Agentaro, in SQLite, with no memory vendor:
- the memory stays with the agent when its executor changes (vendor-agnostic);
- the memory is never handed to a tool's own memory feature (Claude's, ChatGPT's).

**Edge cases the owner asked about ("is this enough").** The design matches current practice. Self-improvement also needs four things this spec prepares for:
- **(a) a signal** of what "better" means: task outcome, owner feedback;
- **(b) guardrails:** the master prompt is changed only by people (Q4); every memory has its source;
- **(c) rollback:** every reorganization is a revision that can be undone;
- **(d) protection against memory poisoning:** text from task results or web pages must not silently become identity.

## 3. Objective

**Goals**
- G3. Memory graph per agent:
  - **nodes** of kinds: `episode` (what happened), `entity` (person, place, thing), `fact`, `preference`, `skill` (how to do something), `self` (the agent's own description of itself);
  - **edges**: named relations between nodes (e.g. `works_with`, `prefers`, `learned_from`, `contradicts`), with weight;
  - every node and edge has content, importance (0–1), confidence (0–1), source (owner, task, consolidation), validity (`valid_from`, `valid_to`: outdated memories are closed, not deleted), created and last-used times.
- G4. Memory revisions: every change to the memory is part of a revision (who or what made it, when, why). A revision can be undone. This prepares the scheduled reorganization of the next spec.
- G5. Memory page per agent: the self-description, recent episodes, facts and preferences with their links, and the revisions; owner can add, correct or close a memory by hand.
- G6. Context assembly, used by task runs (spec 010): a function that builds what the agent would get for a task — master prompt, the self node, the most relevant memories (text search, embeddings (Q3), graph neighbours, recency and importance, within a size budget). Shown on the task page as a preview.

**Out of scope**
- Self-improvement and the scheduled reorganization (spec 015).
- Teams of agents; agents talking to each other; tools and permissions of agents.
- Agents and assignment (spec 009); running tasks (spec 010).

**Success criteria**
- S3. Closing a memory keeps it in history (`valid_to` set); undoing a revision restores the previous state exactly.
- S4. The context preview fits its budget and prefers relevant, important, recent memories.
- S5. A memory is visible only to those who may see its agent (spec 009).

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `memory_nodes`, `memory_edges`, `memory_revisions` (per agent); full-text index (SQLite FTS5) on node content | to create |
| System | `MemoryNode`, `MemoryEdge`, `MemoryRevision`, `AgentContext` (context assembly) | to create |
| System | Memory page per agent; context preview on the task page | to create |
| System | Embeddings through an Ollama executor (Q3), stored per node | to create |

## 5. Functional Domain Changes

**Rules**
- R1. The master prompt is written by people only, never by self-improvement (Q4); the agent's own view of itself lives in its `self` node, which spec 015 lets it rewrite.
- R2. Memories are never deleted by the system: they are closed (`valid_to`) or superseded via an edge; the owner may purge them for good, e.g. personal data (Q5).
- R3. Every memory carries its source; memories from task results are marked as such and start with lower confidence than the owner's own.
- R4. An agent's memory belongs to that agent only; no agent reads another's memory.
- R5. Deleting an agent removes its memory after confirmation.
- R6. Every change is recorded by the data changelog (spec 004); memory contents count as personal data and are filtered from the audit log bodies.

**Data:** new tables in the main database; FTS5 is built into SQLite (no new gem). Embedding storage and similarity search: [TO BE DETERMINED] (Q6).

**Resilience:** when the embedding executor is down, search falls back to text, graph, recency and importance.

## 6. Critical Path

Memory schema with revisions → memory page → context assembly and preview → tests → browser walk-through → security analysis.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | memory validity and revisions, undo, context ranking and budget | `test/models/memory_test.rb` | merge | undo of a revision with later changes is refused or handled; budget never exceeded |
| Integration | memory page, manual edits, purge, permissions | `test/integration/agent_memory_test.rb` | merge | memories of agents one may not see → 404 |
| Manual | browser walk-through | owner | release | — |

## 8. Expected Outcome

- **Direct effect:** agents with a memory and a context built from it.
- **Measurable effect:** S1–S5 pass.
- **Side effects:** the database now holds personal data in memories; backups of `storage/` matter more.
- **Rollback:** drop the memory tables.

## 9. Additional Information

- **Rejected alternatives:** key-value memory (owner); an external memory service (Zep, Mem0, Letta server: not on-prem by default, or another runtime to run); a graph database such as Neo4j (heavy for a single small machine; SQLite tables for nodes and edges cover the needed queries); the tools' own memory features (vendor lock-in).
- **Technical debt:** graph queries in SQL are limited to a few hops; enough for context assembly.
- **External dependencies:** SQLite FTS5; an Ollama executor with an embedding model (Q3).
- **Sources:** Letta memory blocks; Zep/Graphiti temporal knowledge graph; Generative Agents (Park et al., 2023) memory stream and reflection; CoALA (Sumers et al., 2023) episodic / semantic / procedural memory.
- **Questions:**
  - Q3. Memory search — **also embeddings via Ollama** (owner).
  - Q4. Master prompt — **fixed**: changed only by people (owner).
  - Q5. Purge — **allowed** for the owner (owner).
  - Q6. Where embeddings live: a BLOB column with similarity computed in Ruby (fine for thousands of memories per agent), or the `sqlite-vec` extension (faster, one more native dependency). [TO BE DETERMINED]
  - Q7. Which embedding model and executor: chosen per agent, or one system-wide setting. [TO BE DETERMINED]
