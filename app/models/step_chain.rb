# Spec 016: runs an epic's steps one after another. At the epic's start the first pending step is queued; when a
# step's run succeeds, the next one is queued at once (G3); a failed, timed-out or skipped step blocks the epic
# (G5); when the last step succeeds the epic is done (G6, Q5). Each step's prompt carries the answers of the
# earlier steps (G4, R2). Agentaro decides everything here; agents only answer.
class StepChain
  HISTORY_BUDGET = 30 * 1024 # bytes of earlier answers in a step's prompt (R2)
  HISTORY_HEADING = "\nAnswers of the earlier steps (oldest first):\n\n"

  # Planned epics whose start has come and that have not started yet: start them. Called by the scheduler tick and
  # right after planning.
  def self.start_due(now: Time.current, user: nil)
    scope = WorkItem.where(state: "planned", started_at: nil).where("starts_at IS NULL OR starts_at <= ?", now)
                    .where(id: EpicStep.select(:work_item_id))
    scope = scope.where(user: user) if user
    scope.find_each.map { |item| start(item, now: now) }
  end

  def self.start(item, now: Time.current)
    queue_next(item, started_at: now)
  end

  # R1: one step at a time, and only while the epic is planned. Returns the queued run, or nil.
  def self.queue_next(item, started_at: Time.current)
    run = item.transaction do
      item.reload
      next unless item.state == "planned"
      next if item.active_steps.where(state: %w[queued running]).exists?

      step = item.active_steps.find_by(state: "pending")
      next finish!(item) unless step

      item.update!(started_at: started_at, finished_at: nil) unless item.started_at
      step.update!(state: "queued")
      TaskRun.create!(user: item.user, work_item: item, epic_step: step, agent: step.agent, purpose: "epic_step",
                      trigger: "scheduled", occurrence_start: Time.current, state: "queued")
    end
    hand_over(run.id) if run
    run
  end

  # G6, Q5: every step of the active plan succeeded.
  def self.finish!(item)
    steps = item.active_steps.to_a
    return unless steps.any? && steps.all? { |step| step.state == "succeeded" }

    item.done!
    say(item, "system", "Done: \"#{item.title}\" — all #{steps.size} step#{"s" unless steps.size == 1} finished. The results are on the epic's page.")
    nil
  end

  # Called when a step's run has finished (also for runs interrupted by a restart).
  def self.after_run(run)
    item = run.work_item or return
    continued = item.transaction do
      item.reload
      step = item.active_steps.find_by(id: run.epic_step_id)
      next unless step && step.state.in?(%w[queued running]) && attempt_of(step, columns: %i[id])&.id == run.id

      step.update!(state: run.state)
      next unless item.state == "planned"
      next true if run.ok?

      reason = "Step #{step.position} \"#{step.title}\" #{run.state_label}: #{run.error.to_s.truncate(300).presence || "no answer"}"
      item.block!(reason)
      say(item, "system", "\"#{item.title}\" stopped at step #{step.position} of #{item.active_steps.maximum(:position)}: #{run.error.to_s.truncate(300).presence || run.state_label}. Press Try again on the epic to resume from this step.")
      false
    end
    queue_next(item) if continued
  end

  # G5: Try again on a blocked epic with steps resumes from the stopped step.
  # Spec 021, resilience: the epic is claimed atomically (blocked → planned), so Try again, a chat retry and a
  # cancellation cannot both start it; a lost race changes nothing and returns nil.
  def self.resume(item)
    claimed = item.transaction do
      next false unless claim_blocked(item)

      item.active_steps.select(&:stopped?).each { |step| step.update!(state: "pending") }
      true
    end
    return unless claimed

    item.reload.started_at ? queue_next(item) : start_due(user: item.user)
  end

  # --- Spec 021: retrying one failed step from the chat -------------------------------------------------------------

  Ineligible = Class.new(StandardError)

  # The newest run of a step that really belongs to it: same account, epic and step, purpose "epic_step" (R1).
  def self.attempt_of(step, columns:)
    item = step.work_item
    runs = step.runs.where(purpose: "epic_step", work_item_id: item.id, user_id: item.user_id)
    runs.select(*columns).order(id: :desc).first
  end

  # R5: why this step cannot be retried now, or nil. attempt: the id of the failed attempt the director observed.
  def self.retry_problem(item, step, attempt)
    item.reload
    return "the step is not in the active plan of \"#{item.title}\"" unless step.is_a?(EpicStep) && step.work_item_id == item.id

    step = item.active_steps.find_by(id: step.id)
    return "the step is not in the active plan of \"#{item.title}\"" unless step
    return "\"#{item.title}\" is #{item.state_label}, not blocked" unless item.state == "blocked"
    return "step #{step.position} is #{step.state_label}; only a failed step can be retried from the chat#{" (Try again on the epic's page resumes it)" if step.stopped?}" unless step.state == "failed"

    last = attempt_of(step, columns: %i[id state])
    return "the latest attempt of step #{step.position} is not failed" unless last&.state == "failed"
    return "attempt #{attempt.inspect} is not the latest attempt of step #{step.position} (#{last.id})" unless attempt.to_s == last.id.to_s
    return "an earlier step has not succeeded" if item.active_steps.where(position: ...step.position).where.not(state: "succeeded").exists?
    return "a later step has already started" if item.active_steps.where(position: (step.position + 1)..).where.not(state: "pending").exists?
    return "the step has no agent" unless step.agent
    return "#{step.agent.name} is not available" unless step.agent.usable?
    return "a run of this epic is still queued or running" if item.active_run? || item.active_steps.where(state: %w[queued running]).exists?

    nil
  end

  # R6: clears the block and queues exactly one fresh attempt of the step; everything else is kept. The checks and
  # the state change happen in one transaction with an atomic claim; the run goes to the scheduler after commit.
  # Raises Ineligible (nothing changed) when the request is stale or not allowed.
  # enqueue: false when the caller is inside a larger transaction and hands the run over after its commit.
  def self.retry_step!(item, step, attempt, enqueue: true)
    run = item.transaction do
      problem = retry_problem(item, step, attempt)
      raise Ineligible, problem if problem
      raise Ineligible, "\"#{item.title}\" was changed meanwhile" unless claim_blocked(item)

      step.reload.update!(state: "queued")
      TaskRun.create!(user: item.user, work_item: item, epic_step: step, agent: step.agent, purpose: "epic_step",
                      trigger: "manual", occurrence_start: Time.current, state: "queued")
    end
    hand_over(run.id) if enqueue
    run
  end

  def self.hand_over(run_id)
    Agentaro::TaskScheduler.enqueue(run_id)
  rescue StandardError => e # the queued run stays queued and is picked up at the next start (TaskScheduler.recover!)
    Rails.logger.error("[runs] could not hand run #{run_id} to the scheduler: #{e.class}: #{e.message}")
  end

  # Blocked → planned, only if it is still blocked (one winner under contention). Called inside a transaction:
  # SQLite transactions are IMMEDIATE (Rails 8), so the read and the write hold the write lock together, and the
  # change goes through the model, so the data changelog records it (spec 004).
  def self.claim_blocked(item)
    return false unless item.reload.state == "blocked"

    item.update!(state: "planned", blocked_reason: nil, finished_at: nil)
  end

  def self.say(item, author, content)
    ChatMessage.create!(user: item.user, author: author, content: content)
  end

  # --- Running one step (a TaskRun with purpose "epic_step") ------------------------------------------------------

  def initialize(run, **call_options)
    @run = run
    @call_options = call_options
  end

  def perform!
    step = claim_run
    return @run unless step

    agent = step.agent
    outcome = if agent
      AgentCall.new(@run, agent, self.class.prompt_for(step, agent), **@call_options).call
    else
      AgentCall::Outcome.new("skipped", nil, "The step has no agent (it was deleted).", nil)
    end
    TaskRunner.finish!(@run, outcome)
    self.class.after_run(@run)
    @run
  rescue StandardError => e
    Rails.logger.error("[runs] step run #{@run.id} failed: #{e.class}: #{e.message}")
    TaskRunner.finish!(@run, AgentCall::Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil)) unless @run.reload.finished?
    self.class.after_run(@run)
    @run
  end

  # A queued run and cancellation compete for the same write lock before any agent call.
  def claim_run
    @run.transaction do
      next unless @run.reload.state == "queued"

      item = @run.work_item
      step = item&.active_steps&.find_by(id: @run.epic_step_id)
      unless item&.state == "planned" && step&.state == "queued" && self.class.attempt_of(step, columns: %i[id])&.id == @run.id
        @run.update!(state: "skipped", error: "The step is no longer queued in an active epic.", finished_at: Time.current)
        next
      end

      @run.update!(state: "running", started_at: Time.current)
      step.update!(state: "running")
      step
    end
  end
  private :claim_run

  # G4: the agent's master prompt, then the step, its epic and space, and the earlier steps' answers.
  def self.prompt_for(step, agent)
    item = step.work_item
    last_position = item.active_steps.maximum(:position)
    # Spec 030, G1: each line is a named part of the prompt.
    lines = [ [ "task", "Your task: #{step.title}" ] ]
    lines << [ "task", "\nDetails:\n#{step.description}" ] if step.description.present?
    lines << [ "epic", "\nThis is step #{step.position} of #{last_position} of the epic \"#{item.title}\", planned by your director, in the space \"#{item.space.name}\" (#{item.space.purpose_line})." ]
    lines << [ "epic", "Epic details: #{item.description}" ] if item.description.present?
    if (dir = item.space.working_dir) # spec 018, G6
      lines << [ "workspace", "\nYou work in the space's folder #{dir} (your current directory). You may read and change files there, run commands and tools (git, docker, package managers, a browser) and use the network. Folders of other projects are not accessible." ]
    end
    earlier = earlier_answers(step)
    lines << [ "earlier_answers", "#{HISTORY_HEADING}#{earlier}" ] if earlier.present?
    lines << [ "instructions", "\nDo the task now and answer with the result." ]
    AgentCall::Prompt.new(system: agent.master_prompt, sections: lines, joiner: "\n")
  end

  # R2: newest answers whole first, within the budget; older ones are shortened, the oldest dropped with a note.
  def self.earlier_answers(step)
    previous = step.work_item.active_steps.where(state: "succeeded", position: ...step.position).includes(:agent).reverse_order
    omitted = "[older answers left out: over the budget of #{HISTORY_BUDGET / 1024} KB]"
    separator = "\n\n"
    answers = previous.lazy.filter_map do |earlier|
      run = attempt_of(earlier, columns: %i[id state output])
      next unless run&.ok?

      answer = TaskRun.prompt_text(run.output)
      [ earlier, answer ] if answer.present?
    end
    parts = []
    budget = HISTORY_BUDGET - HISTORY_HEADING.bytesize
    answers.chain([ nil ]).each_cons(2) do |(earlier, answer), older|
      header = "--- Step #{earlier.position}: #{earlier.title} (#{earlier.agent&.name || "agent removed"}) ---\n"
      budget -= separator.bytesize if parts.any?
      available = budget - header.bytesize
      available -= omitted.bytesize + separator.bytesize if older
      if available <= 0
        parts << omitted
        break
      end

      marker = "\n[… cut at #{available / 1024} KB]"
      text = answer
      if answer.bytesize > available
        if available <= marker.bytesize
          parts << omitted
          break
        end
        text = answer.byteslice(0, available - marker.bytesize).scrub("") + marker
      end
      parts << header + text
      budget -= (header + text).bytesize
    end
    parts.reverse.join(separator)
  end
end
