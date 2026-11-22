# 043 — Usage limits of Claude and Codex, and a deputy director

Status: **closed** 2026-11-22 (owner: "Zamknij i buduj"); **implemented** 2026-11-22.
Date: 2026-11-22
Depends on: [011](011-list-and-management.md), [022](022-model-lists-and-check.md), [032](032-automatic-step-retry.md), [040](040-director-controls-failed-and-hung-steps.md)

## 1. TL;DR

Agentaro will:
- read how much of each Claude Code and Codex subscription limit is used, and show it;
- say plainly when a limit is reached, and until when;
- let the owner choose a deputy director, who answers while the director's tool is at its limit.

The director learns which agents wait for a limit and can hand their steps to another member when the owner asks.

## 2. Abstract

- **Current state:**
  - Claude Code at its limit ends with exit status 1 and writes "You've hit your 5-hour limit · resets 3:10pm (Europe/Warsaw)" as its answer.
  - Agentaro shows only "claude ended: exit status 1." This was seen on 2026-11-22 in runs of every purpose: chat, step and step review.
  - Spec 032 already classifies a step's failure as a usage limit and retries the step after the reset time.
  - The director's step reviews (spec 040) still start against the limited tool and fail one after another.
  - Nothing shows how much of a limit is used.
- **Gap or problem:**
  - The owner's words: "jest jakiś nieokreślony błąd … pobieraj info o limicie i pokazuj to gdzie w agentaro i obsługuj ten komunikat".
  - On the deputy: "tylko Dyrektor powinien mieć zastępcę żeby móc przegadać status. jeśli agenci się wyczerpali no to trudno, ale dyrektor powinien o tym móc wiedzieć, że to z tego powodu i móc przekierować zadanie do innego".
- **Facts checked on this computer (2026-11-22):**
  - Claude Code 2.1.327 sends a `rate_limit_event` line in its stream-json output on every call. The line holds `status`, `resetsAt` and, for the `five_hour` and `seven_day` windows, `utilization` (0–1) and `resetsAt`.
  - Codex 0.170.0 writes `rate_limits` to its session log: `primary` and `secondary` windows, each with `used_percent`, `window_minutes` and `resets_at`. Whether `codex exec --json` also streams them is checked first in implementation (Q1).
- **Decision history:** the owner chose (2026-11-22): only the director gets a deputy. Agents at their limit wait; the director knows why and can redirect.

## 3. Objective

**Goals**
- G1. **Reading the limit.** Every Claude Code and Codex call records what its tool reported about the limit, per executor:
  - each window (5 hours, 7 days, or what the tool names);
  - its use in percent and its reset time;
  - whether the limit is reached;
  - when this was read.
- G2. **Showing the limit.**
  - The Executors page shows, for each Claude Code and Codex executor, its windows ("5 h: 42 %, resets 15:10 · 7 days: 18 %") and when they were read.
  - A reached limit is marked.
  - The chat settings panel shows the director's executor in the same way.
- G3. **A plain message.** A run that ended on a usage limit has the error "Claude Code: 5-hour usage limit reached, resets at 15:10" instead of "exit status 1". This is what the chat, the step, the epic and the run page show.
- G4. **The deputy director.**
  - On the Team page the owner may choose a deputy director: one agent, ideally on another tool (for example Codex or a local model, spec 044).
  - While the director's executor is at a reached limit whose reset is still ahead, the director's work goes to the deputy. That work is the chat, planning and step reviews.
  - When a director call ends on a usage limit, the same work is sent once more, to the deputy.
  - The chat marks such answers: "Odpowiada zastępca (Codex), bo Claude Code ma limit do 15:10".
  - After the reset, work goes back to the director.
- G5. **No pointless calls.** With no deputy, or with the deputy at its limit too:
  - a chat message gets a system reply with the reset time and does not call the tool;
  - a step review waits until the reset instead of failing.
- G6. **The director knows.** The director's status list shows, for each member whose executor is at a reached limit, "limit until 15:10". A step that waits for a limit retry says so.
- G7. **Redirecting a step.**
  - A new chat action `reassign_step` hands a step to another team member and starts it now, when the owner asks ("przekaż to Codexowi").
  - It works on a step that waits for a usage-limit retry, or on a failed step.
  - The step's instructions and its earlier results stay.

**Out of scope**
- Switching agents' steps to another member by itself (the owner chose: agents wait).
- Reading a limit without a call (neither tool offers that in print mode), and buying extra usage.
- Limits of API executors (Ollama, LM Studio, OpenAI-compatible).

**Success criteria**
- S1. A recorded Claude Code stream with `rate_limit_event` produces the stored windows. The Executors page shows them.
- S2. A recorded run that hit the limit shows "5-hour usage limit reached, resets at 15:10" in the chat and on the step.
- S3. With a deputy set and the director's executor at a reached limit:
  - a chat message is answered by the deputy;
  - the answer carries the mark;
  - no call is made to the director's tool.
- S4. Without a deputy:
  - the same message gets the system reply with the reset time;
  - a pending step review waits until the reset.
- S5. "przekaż krok 2 Codexowi" on a step waiting for a limit starts that step with the Codex member.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `executors`: the last limit reading (windows, read at) | to create |
| Data | team role `deputy` (one per user, like the director and the verifier) | to create |
| System | `ClaudeStream`, `CodexStream`: read the limit events | to change |
| System | `UsageLimit` (reading, message, "at limit until") | to create |
| System | `AgentCall`: the plain limit error | to change |
| System | `ManagementRunner`, `StepReviewer`: deputy and waiting | to change |
| System | `reassign_step` action | to create |
| System | Executors page, Team page, chat settings panel | to change |

## 5. Functional Domain Changes

- **State:**
  - an unclear exit status → a plain limit message;
  - no view of limits → windows on the Executors page;
  - the director stuck at its limit → the deputy answers.
- **Rules:**
  - R1. A reading belongs to the executor (one subscription per executor). A newer reading replaces an older one.
  - R2. "At limit" means: the tool said the limit is reached, and the reset time is in the future. With no reset time known, it means one hour after the failed call.
  - R3. The deputy gets the same prompt as the director. Its master prompt is the deputy agent's own.
  - R4. A deputy cannot also be the director or the verifier. A deputy on the same executor as the director is refused, because it would hit the same limit.
  - R5. `reassign_step`:
    - only for a member of the owner's team whose executor is not at a limit;
    - only on the owner's request in the latest message (like `retry_step`);
    - the step's waiting retry is cancelled.
  - R6. The limit message comes from the tool's own output, never from an agent's text: the stream event, or the final answer of a run that exited with an error.
- **Resilience:**
  - a stream without a limit event leaves the last reading unchanged;
  - an unknown event format is ignored.
- **Data:** a migration adds the executor's reading (JSON, read at) and allows the `deputy` role. Back up production before it.

## 6. Critical Path

1. Q1: check whether `codex exec --json` streams `rate_limits`.
2. Unit tests on recorded streams (G1, G3); store the reading.
3. The plain error and the stop on pointless calls (G3, G5).
4. The deputy role, the routing and the chat mark (G4).
5. The director's status lines and `reassign_step` (G6, G7).
6. The views (G2).
7. A browser check on demo data, a B20 analysis, then CHANGELOG and README.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | streams → readings; limit text → plain message; "at limit" rule | model tests on recorded lines | commit | an agent's text saying "limit reached" in a successful run does not mark a limit |
| Integration | S3, S4, S5 | runner tests with fake tools | commit | `reassign_step` without a request in the latest message is refused |
| Manual | S1, S2 on the Executors page and in the chat | browser on demo data | release | — |

## 8. Expected Outcome

- **Direct effect:**
  - the owner sees how much of each limit is used;
  - a reached limit is said plainly;
  - the owner can always talk to a director.
- **Measurable effect:** no "exit status 1" for limit failures; no step review fails on a known limit.
- **Side effects:** the deputy may be a weaker model, so its answers may be simpler.
- **Rollback:** revert the code. The added column and the role stay unused.

## 9. Additional Information

- **Rejected alternatives:**
  - switching every agent to a backup tool automatically. The owner chose to have agents wait.
  - polling the limit with extra calls, because that costs part of the same limit.
- **External dependencies:** the stream formats of Claude Code 2.1.x and Codex 0.170 may change. Readings are optional, and failures are still classified by their text (spec 032).
- **Sources and questions:**
  - Q1. Does `codex exec --json` carry `rate_limits`? If not, read the run's session log by its id. [TO BE DETERMINED in implementation, step 1]

- **Implementation (2026-11-22):**
  - Q1 answered: `codex exec --json` does not stream `rate_limits`, and Agentaro's Codex calls are ephemeral (no session log). The Codex reading comes from Codex's newest session log on this computer (`~/.codex/sessions`, written by any Codex session; only `rate_limits` is read) and from the limit message of a failed call.
  - `UsageLimit` reads the stream event and the session log, writes the plain message and stores the reading on the executor (`executors.usage_limits`, `usage_read_at`; not recorded as data changes).
  - `DirectorRoute` decides who works: the director, or the deputy (team role `deputy`) while the director's tool is at its limit. Chat, planning, step reviews and summaries (spec 045) go through it.
  - With no deputy, a step review waits as a queued run with `retry_at`; the scheduler hands it over at the reset.
  - A review after the reset reads the reset time as of the failure (before, "resets 3pm" read after 3 pm meant tomorrow).
  - Tests: `usage_limit_test.rb` (7), `deputy_director_test.rb` (8), `usage_limits_test.rb` (2); `step_review_test.rb` S2 and `task_run_test.rb` S3 adapted to the new behaviour.
- **Security analysis (B20):**
  - A reset time read from text is not believed beyond 7 days (the longest window), and a stored reached limit never lasts longer. Without this, an output saying "try again in 99 days" could block the director for 99 days. Fixed with a test.
  - Process tracker (spec 040): a saved list naming the server gathered the server's children before dropping the server, so it could stop other runs' processes, which have their own process groups. The server is now dropped first. The existing test caught it only in some test orders.
