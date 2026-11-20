# Spec 016: runs an epic's steps one after another. At the epic's start the first pending step is queued; when a
# step's run succeeds, the next one is queued at once (G3); a failed, timed-out or skipped step blocks the epic
# (G5); when the last step succeeds the epic is done (G6, Q5). Each step's prompt carries the answers of the
# earlier steps (G4, R2). Agentaro decides everything here; agents only answer.
class StepChain
  HISTORY_BUDGET = 30 * 1024 # bytes of earlier answers in a step's prompt (R2)

  # Planned epics whose start has come and that have not started yet: start them. Called by the scheduler tick and
  # right after planning.
  def self.start_due(now: Time.current, user: nil)
    scope = WorkItem.where(state: "planned", started_at: nil).where("starts_at IS NULL OR starts_at <= ?", now)
                    .where(id: EpicStep.select(:work_item_id))
    scope = scope.where(user: user) if user
    scope.find_each.map { |item| start(item, now: now) }
  end

  def self.start(item, now: Time.current)
    item.update!(started_at: now, finished_at: nil) unless item.started_at
    queue_next(item)
  end

  # R1: one step at a time, and only while the epic is planned. Returns the queued run, or nil.
  def self.queue_next(item)
    item.reload
    return unless item.state == "planned"
    return if item.epic_steps.where(state: %w[queued running]).exists?

    step = item.epic_steps.where(state: "pending").order(:position).first
    return finish!(item) unless step

    step.update!(state: "queued")
    run = TaskRun.create!(user: item.user, work_item: item, epic_step: step, agent: step.agent, purpose: "epic_step",
                          trigger: "scheduled", occurrence_start: Time.current, state: "queued")
    Agentaro::TaskScheduler.enqueue(run.id)
    run
  end

  # G6, Q5: every step succeeded.
  def self.finish!(item)
    return unless item.epic_steps.exists? && item.epic_steps.all? { |s| s.state == "succeeded" }

    item.done!
    say(item, "director", "Done: \"#{item.title}\" — all #{item.epic_steps.size} step#{"s" unless item.epic_steps.size == 1} finished. The results are on the epic's page.")
    nil
  end

  # Called when a step's run has finished (also for runs interrupted by a restart).
  def self.after_run(run)
    step = run.epic_step or return
    step.update!(state: run.state)
    item = step.work_item
    if run.ok?
      queue_next(item)
    elsif item.reload.state == "planned" # G5: stop and block; a cancelled epic stays cancelled
      reason = "Step #{step.position} \"#{step.title}\" #{run.state_label}: #{run.error.to_s.truncate(300).presence || "no answer"}"
      item.block!(reason)
      say(item, "system", "\"#{item.title}\" stopped at step #{step.position} of #{item.epic_steps.size}: #{run.error.to_s.truncate(300).presence || run.state_label}. Press Try again on the epic to resume from this step.")
    end
  end

  # G5: Try again on a blocked epic with steps resumes from the stopped step.
  def self.resume(item)
    item.transaction do
      item.epic_steps.select(&:stopped?).each { |step| step.update!(state: "pending") }
      item.update!(state: "planned", blocked_reason: nil, finished_at: nil)
    end
    item.started_at ? queue_next(item) : start_due(user: item.user)
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
    step = @run.epic_step
    agent = step&.agent
    outcome = if step.nil? then AgentCall::Outcome.new("skipped", nil, "The step no longer exists.", nil)
    elsif agent.nil? then AgentCall::Outcome.new("skipped", nil, "The step has no agent (it was deleted).", nil)
    else
      step.update!(state: "running")
      AgentCall.new(@run, agent, self.class.prompt_for(step, agent), **@call_options).call
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

  # G4: the agent's master prompt, then the step, its epic and space, and the earlier steps' answers.
  def self.prompt_for(step, agent)
    item = step.work_item
    total = item.epic_steps.size
    lines = [ "Your task: #{step.title}" ]
    lines << "\nDetails:\n#{step.description}" if step.description.present?
    lines << "\nThis is step #{step.position} of #{total} of the epic \"#{item.title}\", planned by your director, in the space \"#{item.space.name}\" (#{item.space.purpose_line})."
    lines << "Epic details: #{item.description}" if item.description.present?
    earlier = earlier_answers(step)
    lines << "\nAnswers of the earlier steps (oldest first):\n\n#{earlier}" if earlier.present?
    lines << "\nDo the task now and answer with the result."
    AgentCall::Prompt.new(system: agent.master_prompt, user: lines.join("\n"))
  end

  # R2: newest answers whole first, within the budget; older ones are shortened, the oldest dropped with a note.
  def self.earlier_answers(step)
    previous = step.work_item.epic_steps.select { |s| s.position < step.position && s.state == "succeeded" }
    budget = HISTORY_BUDGET
    parts = previous.reverse.filter_map do |s|
      answer = s.last_run&.output.to_s
      next if answer.empty?

      header = "--- Step #{s.position}: #{s.title} (#{s.agent&.name || "agent removed"}) ---\n"
      if budget <= header.bytesize + 200
        budget = 0
        next "#{header}[answer left out: over the budget of #{HISTORY_BUDGET / 1024} KB]"
      end
      text = TaskRun.limit_text(answer, budget - header.bytesize - 100)
      budget -= header.bytesize + text.bytesize
      header + text
    end
    parts.reverse.join("\n\n")
  end
end
