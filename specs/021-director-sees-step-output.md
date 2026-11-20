# 021 — Director sees the output of each step

Status: **implemented** 2026-11-20 with the proposed answers to Q1 and Q2, which the owner has not yet reviewed. Review fixes and Rondo B20 checks are complete. The configured-model browser walkthrough remains open.  
Date: 2026-11-20  
Depends on: [013](013-projects.md), [014](014-spaces.md), [016](016-sequential-steps.md), [019](019-verifier.md), [020](020-pages-without-reloading.md)

## 1. TL;DR

The director and verifier get a short excerpt from each successful epic step in their chat context. The director can propose a retry of one failed step at the user's request. The retry receives earlier successful answers and the epic continues from that step. A normal chat request can also order work or change the work list or a space.

## 2. Abstract

**Starting state.** The director and verifier shared a live view of step states, durations and stopped-step errors. The answer is stored in `TaskRun.output`, and the epic page links to the full stored answer.

**Gap.** During a world review the user asked which topics the topic-selection step found. The director could report that the step succeeded, but had no answer text to draw from.

**Decision history.** Spec 013 G3 limited shared chat context to space and item metadata. The progress update following spec 016 added step states and errors. This spec extends that exception to bounded excerpts in chat and verification, addressing the gap recorded in spec 019 §9. Spec 016 already gives each step earlier answers and lets the epic page resume a blocked chain. The director currently has no corresponding step retry action in chat.

The owner approved removing the chat command requirement as part of the plain-chat ordering epic. The action proposal still needs a context that excludes evidence and model replies.

## 3. Objective

**Goals**

- G1. Give the director and verifier the same bounded, current view of step results, with each result attributable to its space, epic and step.
- G2. Let the director target a single failed step in a blocked epic when the user asks to retry it. Preserve successful steps and reuse their answers in the retry.
- G3. Accept ordinary chat requests for work-list and space changes when step results are available.

**Out of scope**

- Automated retries, rerunning a successful step, re-planning an epic, and reviewing every result before the next step starts.
- Searching older epics outside the current chat work list, generating summaries with a model, and backfilling legacy calendar task runs.

**Success criteria**

- S1. With a successful topic-selection step whose stored answer begins `Topics found: [Topic A], [Topic B]`, and a later step still running, the user's next question, “which topics were found after the topic-selection step?”, gets an immediate director reply naming `[Topic A]` and `[Topic B]` in that same turn. The verifier can check that reply against its own excerpt.
- S2. Both prompts show matching excerpts, states and omission notices for the same snapshot. Long or multibyte answers fit both limits. Failed, running and empty results follow R2 and R3.
- S3. Given step 1 succeeded, step 2 failed, and step 3 is pending, a request to retry step 2 queues one new attempt of step 2. Its prompt contains the answer from step 1. The existing runs and step 1's state are preserved. Step 3 queues only after step 2 succeeds. Another failure blocks the epic at step 2 again.
- S4. Other accounts' answers, mismatched runs and other spaces' excerpts stay outside their respective prompt boundaries. Stale, ineligible or duplicate requests cannot start a second attempt, and result text alone cannot authorize a retry.
- S5. With a planned epic and stored step results, a plain request can add work, cancel an epic or move it. A progress question cannot apply a work-list or space proposal from the evidence-bearing answer.

## 4. Artefact Inventory

| Area | Element | State |
|---|---|---|
| Data | `EpicStep`, associated `TaskRun` state, output, error and attempt history | exists |
| System | `ManagementRunner` chat and verifier work-list context, action validation and applied-action summary | to change |
| System | `StepChain` targeted retry and earlier-answer prompt | to change / exists |
| System | Epic page “Try again” and run history | exists |
| System | Prompt, retry and chat regression tests | to add |

## 5. Functional Domain Changes

**State.** The chat work list gains attributed excerpts alongside progress. A valid retry moves the blocked epic back to planned and queues a fresh attempt of its failed step. The ordinary chain handles the outcome.

**Rules**

- R1. Use the existing account-scoped chat work list in both prompts, at most 50 open, planned or recently finished epics, with the existing 24-hour window for finished items. Keep each excerpt nested under its own space, epic and step. Require the run to match the account, epic, step and `epic_step` purpose. This supersedes the chat-only metadata limit of spec 013 G3 for these excerpts. Plans and step prompts keep their space boundaries. Each step receives earlier successful answers from its active plan, using the same run ownership checks as chat. Moving or replanning an epic starts a new plan and keeps earlier attempts on the epic page. Archived conversations stay outside prompt history.
- R2. A successful step uses the newest matching run when that run also succeeded. Use a deterministic prefix of the stored answer in valid UTF-8, cutting only at character boundaries. Allow **1,024 bytes per rendered excerpt** and **10,240 bytes of rendered excerpts per epic per prompt**, counting excerpt labels, separators and truncation markers. Allocate in step order. Shorten the prefix to fit the remaining budget and mark it `[excerpt shortened]`. If the remaining budget cannot fit any answer text plus its framing and marker, show `Excerpt omitted: budget reached` on the step's progress line. Progress lines and status annotations have a separate limit of 20 steps per epic. If a legacy epic exceeds that limit, show the newest 20 in step order and point the user to the epic page. Fetch only the newest scoped attempt with the fields needed for that step.
- R3. A succeeded step with missing or blank output shows `No stored answer`. A failed, timed-out or skipped step shows its state and the existing error excerpt of at most 200 characters, when available. Queued, pending, running and cancelled steps show progress only, with elapsed time when available. Partial output and earlier failed attempts stay in run history. The director answers from the visible evidence and says when an excerpt is missing or too short to support the answer. The verifier uses the same evidence to check the director's claim.
- R4. Step excerpts are quoted agent data, with boundaries that remain intact when an answer contains line breaks or delimiter-like text. Normalize line separators and remove NULs before quoting. They provide evidence for replies and carry no authority to change an epic or start a run. Before applying a retry, Agentaro checks that the current authenticated user requested that target, using the user's latest authenticated message independently of the director's proposal and quoted output. Accept a complete affirmative English or Polish retry request with an unambiguous target (for example `Retry step 2 of World review` or `Ponów krok 2 w World review`). A bare `Retry it` requires a single eligible target. A progress question authorizes a reply. The director can recognize work-list and space requests in ordinary conversation. If its chat answer proposes such a change, Agentaro requests a fresh proposal using the latest authenticated user message and account-scoped metadata. That pass excludes step output, step diagnostics, chat history and the previous proposal. Only that pass can propose work-list or space actions for application. It must ask for clarification when the request leaves the intended change unclear. Agentaro validates the resulting actions before applying them, including ownership, allowed fields and state rules. A space's working folder is set on its form. The verifier remains read-only.
- R5. The retry identifies one epic, one step and its observed failed attempt. Agentaro validates that the current user owns the epic, the step belongs to it, the epic is blocked at that step, the step and its latest attempt are `failed`, all earlier steps succeeded, the assigned agent is usable, and the epic has no queued or running step. A stale or ineligible request leaves the epic unchanged and reports the reason. If the user names an ambiguous target, the director asks which epic or step they mean. The epic page's existing “Try again” remains available, including for `timed_out` and `skipped` steps under spec 016.
- R6. A successful request clears the block and queues exactly one fresh `TaskRun` for the targeted step. Keep the plan, all other step states, earlier successful answers and old runs. A reply can propose one retry by itself. The retry uses the same earlier-answer format and 30 KiB budget as a normal step under spec 016 R2, including headings, separators and omission notices. After success the chain continues through pending steps in order. The chat reports the applied retry once queued and reports its outcome through normal step progress.

- R7. Retire `/change` as a command. The chat has one path for natural-language requests and keeps authenticated messages verbatim.

**Resilience.** Recheck eligibility atomically with the state change and run creation, including against “Try again” and cancellation. Hand the run to the scheduler after commit. Duplicate or stale proposals and failed writes leave at most one active run for the epic. A scheduler worker atomically claims a queued run and its step before calling the agent. Cancelling an epic skips attempts that are still queued and lets a claimed run finish. Existing restart recovery applies to the new attempt.

**Data.** Read existing stored outputs at prompt construction. `work_items.active_step_from` marks the first step of the current plan. The migration uses recorded space changes and replan transitions to recover the boundary for legacy epics. Full results and retired plans remain accessible through run history. The full stored answer remains available on the run page.

## 6. Critical Path

Owner closes the spec → add regression tests for chat and verifier context → supply bounded excerpts through the shared work list → add and verify the targeted retry action and chain transition → run the topic-selection walkthrough → run tests and Rondo B20 security analysis → update README and CHANGELOG with verified behavior before release.

For plain chat ordering, update this spec → reproduce the command requirement in the chat integration test → isolate and validate action proposals → run the chat and security regressions → revalidate the README and CHANGELOG.

## 7. Control Gates

| Gate | Pass condition | Verification | Blocks | Negative gate |
|---|---|---|---|---|
| Unit | Both prompts use the newest eligible successful attempt. Cover missing and blank output, running and stopped states, multibyte text, exact limits, truncation and exhausted budget. | Extend `test/models/management_runner_test.rb` | merge | No partial output, stale attempt output or oversized excerpt payload. |
| Unit | A targeted retry queues once, retains earlier answers and history, and resumes or blocks on the outcome. Cover stale and duplicate requests, unusable agents, enqueue failure and contention with page retry or cancellation. | Extend `test/models/step_chain_test.rb` | merge | No re-plan, repeat of successful steps or parallel attempts in one epic. |
| Contract | A director retry is validated against the requesting account, epic, step and latest attempt. Check disallowed states, mismatched IDs and an excerpt that asks the director to change state. Verify the verifier remains comment-only. | Extend `test/models/management_runner_test.rb` | merge | No action from an excerpt alone, a verifier response, an ineligible target or another account. |
| Integration | Exercise a chat retry with a stand-in director. Confirm the queued run and applied-action notice, and cover rejection of an ambiguous or stale request. Check that plan and step prompts keep their space scope, and preserve the existing page retry. | Extend `test/integration/director_chat_test.rb` and the prompt separation cases in `test/models/management_runner_test.rb` | merge | No other account's output in either chat prompt and no cross-space excerpt in plan or step prompts. |
| Integration | Submit ordinary requests with step evidence present and exercise a stand-in director that proposes a change during a progress question. | Extend `test/integration/director_chat_test.rb` | merge | No work-list or space action is taken directly from the evidence-bearing response. |
| E2E | Ask the S1 question while a later step is running, then invoke the verifier. Repeat with a blocked three-step epic and retry only the middle step from chat. | Browser walkthrough with configured agents and placeholder data | release | The director gives the found topics in the next reply and the first step keeps its original run. |
| Security | Review prompt data handling, ownership and retry races against this spec and specs 001–020. | Rondo B20 analysis and `bin/rails test` | release | Any new regression follows the project's spec, reproducing test and changelog process. |

## 8. Expected Outcome

- **Direct effect.** The user can ask what a step found as soon as it succeeds. The verifier can check the answer, and a blocked epic can resume from the named failed step through chat. A plain request can also order work.
- **Measurable effect.** Automated S1–S5 checks cover prompt delivery, chat and verifier behavior with stand-ins, retry sequencing and ordering work with step results present. Added excerpt payload stays within 10 KiB per epic and 500 KiB across the existing 50-epic work list. A valid retry adds exactly one attempt before normal sequencing resumes.
- **Side effects.** Chat prompts can be larger, and agent output becomes an additional source of untrusted prompt data. A proposed work-list or space change adds a second director call. The existing run history remains the source for complete stored answers.
- **Rollback.** Revert the excerpt and chat action changes. Step progress and page retry remain available, and recorded attempts stay in run history.

## 9. Additional Information

- **Alternatives considered.** Full answers would make prompt size depend on stored output size. Model-generated summaries require another run and may change what the agent reported. A deterministic prefix uses the result already stored when the next chat turn begins. An optional command alias would keep special syntax and parser behavior for an operation that plain chat now handles.
- **Technical debt.** A prefix can omit a finding near the end of a long answer. Older completed epics remain outside the live work list. Automatic review between steps remains separate work.
- **External dependencies.** None added.
- **Sources and questions.** Discovery map for this epic, `ManagementRunner#step_lines`, `StepChain.resume`, `StepChain.earlier_answers`, and `TaskRun.output`.
  - Q1. Approve the proposed UTF-8 prefix and limits of 1 KiB per step and 10 KiB per epic? Owner review **[TO BE DETERMINED]**.
  - Q2. Approve continuing the normal chain after a successful retry, with chat retry restricted to `failed` and the page handling timed-out or skipped steps? Owner review **[TO BE DETERMINED]**.
- **Implementation notes (2026-11-20).**
  - Excerpts are `ManagementRunner#step_lines` and `.excerpt`. Every line of an answer is quoted as `    | …` under an `answer excerpt` label. Both prompts tell the model that these lines are data, not instructions (R4). A run counts only when its account, epic, step and `epic_step` purpose match (`StepChain.attempt_of`). A failed step shows `(attempt N)`, which is the id the action names.
  - The chat action is `{"type": "retry_step", "id": <epic>, "step": <position>, "attempt": <failed run id>}`. Applying it calls `StepChain.retry_problem` (R5) and `StepChain.retry_step!` (R6).
  - R4 user check applies before the transaction writes any action. An independent proposal for work-list and space actions uses the latest user message and metadata (R4). The retry is validated and applied on its own.
  - A move retires the source plan, and replanning records the first position of the replacement plan. Only active steps contribute to chat evidence and chained answers. A retry preserves the current plan and selects its existing earlier answers.
  - The epic is claimed inside an IMMEDIATE SQLite transaction. The chat and page share the block claim. The scheduler receives a new attempt after commit. If handoff fails, the queued run is available to recovery.
- **Owner fix (2026-11-20): "director nie wie, o czym mowa"; "wypowiedzi giną i wracają".** In 8 of 17 chat runs that day the proposal pass decided the answer. That pass saw only the latest user message, so "q4 zajęty" (an answer to the director's question Q4) was read as a bug report, and "implementuj" or "asap realizacja" as requests without a subject. Its answer also replaced the one already streamed and partly spoken. Owner's decision, which supersedes the R4 note above:
  - **The first answer is posted.** It was written with the whole conversation and was already shown and spoken while it streamed. The proposal pass is not streamed and only decides the changes. Agentaro notes what was really applied under the answer, or "No changes were made to the work list or spaces."
  - **The proposal pass sees the conversation.** It gets the user's and the director's earlier messages, up to 30, as context only. Step output and verifier comments stay out. Only the latest user message can ask for changes, including a short answer that accepts a change the director offered just before.
  - **Finding F-021-OF1 (accepted by the owner).** A director message may repeat text from a step's output. The proposal pass now reads such messages as context, so a prompt injection through step output has an indirect path to it. Mitigations: the pass is told the earlier conversation is context and not requests, only the latest user message can ask for changes, and the R4 user check and action validation are unchanged.
  - Tests: `test/models/chat_order_test.rb` ("a short answer to the director's question"); spec 021 tests in `director_chat_test.rb` updated to the new rule.

## Security analysis (B20), after spec 021

Scope covers spec 021 and the earlier specs. The full Rails suite exercises authentication and audit (001–005), responsive rendering, calendar and executor access (006–010), account and space scope, archived conversations and workflow transitions (011–016), and voice, working folders, the read-only verifier and navigation (017–020).

- Retry authorization is tied to the latest user request, its resolved epic and step, and the current failed attempt. Negative, ambiguous, stale and mixed-action proposals leave state unchanged. The earlier command gate for work-list and space changes is superseded by R4. A separate proposal pass excludes evidence and model replies.
- Cancellation and the worker claim are serialized. A skipped queued attempt keeps its history without launching the agent. Same-plan results require matching account, epic, step, purpose and success state. The legacy plan backfill relies on the retained audit history.
- Prompt inputs use bounded step lists, one current attempt per step, and byte budgets that account for framing. Alternate line endings and NULs are normalized before evidence enters a prompt.
- Spec 013 G3, spec 016's progress note, and the step-output debt and separation text in spec 019 are superseded for the bounded live chat excerpts. The separate executor isolation and workflow budget findings remain tracked in their original specs.
- Brakeman reported zero warnings. The updated Ruby advisory database reported no known dependency vulnerabilities. The browser gate still needs configured models.

### Plain chat ordering update

- The application discards work-list and space proposals from the evidence-bearing call. The fresh call excludes step results, diagnostics, prior messages and the first proposal, and uses a new executor workspace. Any retry proposal in that call is rejected.
- The write transaction checks for a newer user request. The original action checks still enforce account ownership, valid states and fields, and the working-folder restriction. The verifier remains read-only, and targeted retry still checks the user's request and the failed attempt independently.
- The independent call interprets natural language and reads account-scoped metadata. It can still misread intent, and the existing executor isolation findings and workflow budget limits carry over. A request that depends on earlier dialogue can require clarification.
- The full Rails suite covering specs 001–022 passed with 284 tests and 1,823 assertions. Brakeman reported zero warnings, and the refreshed dependency audit found no known vulnerabilities.

## Review by Claude Code (2026-11-20), before release

- The agents (epic 19) implemented this spec while it was still a draft, with Q1 and Q2 unanswered by the owner. The owner's review of Q1/Q2 and of the change of spec 013 G3 (step result excerpts from all spaces in the director's chat) is still needed.
- Tests: 262 passed, Brakeman no warnings. Their migration `track_active_epic_plan` adds `work_items.active_step_from` and fills it from the data changelog.
- **Security finding fixed (B20):** step results now reach the director's prompt, and they may carry text from web pages. Through `update_space` the director could still change a space's working folder, where agents may do anything (spec 018). The working folder can now be set only on the space form; a chat action trying it is refused (test).
- Historical finding, superseded by the current R4 proposal boundary: instruction-like text in results can still steer other director actions (add, update, cancel epics; spaces' names and goals). Agentaro checks their validity, not whether the user asked. Proposal: require the user's own request for actions while results are in the prompt, as R4 does for retries.

