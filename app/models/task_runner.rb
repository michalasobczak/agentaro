# Spec 010: runs one step TaskRun — reads the task and its agent at run time (R2), builds the prompt (G2) and
# calls the agent (AgentCall). Never raises: every outcome is a state.
class TaskRunner
  NOT_RUNNABLE = AgentCall::NOT_RUNNABLE
  WEB_TOOLS = AgentCall::WEB_TOOLS
  Outcome = AgentCall::Outcome
  Prompt = AgentCall::Prompt

  def initialize(run, timeout: Rails.application.config.x.run_timeout, runs_dir: Rails.application.config.x.runs_dir)
    @run = run
    @timeout = timeout
    @runs_dir = runs_dir
  end

  def perform!
    task = @run.task
    agent = task.agent
    return finish!(Outcome.new("skipped", nil, "The task has no agent.", nil)) unless agent

    prompt = self.class.prompt_for(task, agent, @run.occurrence_start)
    finish!(AgentCall.new(@run, agent, prompt, timeout: @timeout, runs_dir: @runs_dir).call)
  rescue StandardError => e
    Rails.logger.error("[runs] run #{@run.id} failed: #{e.class}: #{e.message}")
    finish!(Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil))
  end

  # G2: the agent's master prompt, then the task in the app's time zone.
  def self.prompt_for(task, agent, occurrence_start)
    occurrence = task.occurrence_at(occurrence_start) || Task::Occurrence.new(task: task, starts_at: task.starts_at, ends_at: task.ends_at, original_start: task.starts_at)
    starts, ends = occurrence.starts_at.in_time_zone, occurrence.ends_at.in_time_zone
    lines = [ "Your task: #{task.title}",
              "When: #{starts.strftime("%A %-d %B %Y, %H:%M")} – #{ends.strftime(starts.to_date == ends.to_date ? "%H:%M" : "%A %-d %B %Y, %H:%M")} (#{Time.zone.name})" ]
    lines << "Location: #{task.location}" if task.location.present?
    lines << "\nDetails:\n#{task.description}" if task.description.present?
    if task.work_item # specs 011–014: a step of an epic, in its space only
      space = task.work_item.space
      lines << "\nThis is one step of the epic \"#{task.work_item.title}\" planned by your director, in the space \"#{space.name}\" (#{space.purpose_line})."
    end
    lines << "\nDo the task now and answer with the result."
    Prompt.new(system: agent.master_prompt, user: lines.join("\n"))
  end

  # Stores the outcome on the run (output and errors limited, spec 010 G4/G5).
  def self.finish!(run, outcome)
    run.update!(state: outcome.state, output: TaskRun.limit_text(outcome.output, TaskRun::MAX_OUTPUT).presence,
                error: TaskRun.limit_tail(outcome.error, TaskRun::MAX_ERROR).presence,
                exit_status: outcome.exit_status, started_at: run.started_at || Time.current, finished_at: Time.current)
    run
  end

  private

  def finish!(outcome) = self.class.finish!(@run, outcome)
end
