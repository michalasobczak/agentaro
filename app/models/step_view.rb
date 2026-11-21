# Spec 038: what the view beside the work panel shows for one step of the owner's own epic — its state, its live log
# while it runs (LiveLog), the same log from the trace when it ended (R4), its answer, error or question, or what it
# waits for. Entries are cut to 300 characters, the latest 200 are shown (R3), secrets replaced (R5).
class StepView
  ENTRY_CHARS = 300
  MAX_ENTRIES = 200
  TEXT_CHARS = 4000
  ANSWER_CHARS = 4000
  LOG_PRESETS = %w[claude_code codex].freeze
  TEXT_PRESETS = %w[ollama_cli lm_studio_cli ollama_api lm_studio_api openai_compatible_api].freeze
  ARGUMENT_KEYS = %w[command file_path path notebook_path pattern query url description prompt changes tool].freeze

  # The step to show for an epic (G1, G4): the running one, else the latest that started, else the first.
  def self.step_for(item)
    steps = item.active_steps.order(:position).to_a
    steps.find { |s| s.state.in?(%w[queued running]) } || steps.reverse.find { |s| s.state != "pending" } || steps.first
  end

  def initialize(step, runs_dir: Rails.application.config.x.runs_dir, now: Time.current)
    @step, @item, @runs_dir, @now = step, step.work_item, runs_dir, now
  end

  def to_h
    run = StepChain.attempt_of(@step, columns: %i[id state started_at finished_at preset output error retry_at])
    running = run&.state == "running"
    preset = run&.preset.presence || @step.agent&.executor&.preset
    live = run && LiveLog.read(LiveLog.dir_for(run.id, runs_dir: @runs_dir))
    events = live ? live[:events] : trace_events(run)
    entries = events.flat_map { |event| entry(event) }
    {
      epic: { id: @item.id, title: @item.title, state: @item.board_state, url: helpers.work_item_path(@item) },
      step: { id: @step.id, position: @step.position, of: @item.active_steps.maximum(:position), title: @step.title,
              state: @step.state, label: @step.state_label, agent: @step.agent&.name, description: cut(@step.description, ANSWER_CHARS) },
      run: run && { id: run.id, state: run.state, url: helpers.task_run_path(run), started_at: run.started_at&.iso8601,
                    elapsed: (((run.finished_at || @now) - run.started_at).round if run.started_at),
                    interrupted: run.finished? && live.present? },
      running: running || run&.state == "queued",
      stream: LOG_PRESETS.include?(preset) ? "log" : (TEXT_PRESETS.include?(preset) ? "text" : "none"),
      entries: entries.last(MAX_ENTRIES), earlier: [ entries.size - MAX_ENTRIES, 0 ].max,
      text: (tail(live[:text]) if live && live[:text].present?),
      answer: (cut(TaskRun.prompt_text(run.output), ANSWER_CHARS) if run&.state == "succeeded" && run.output.present?),
      error: (cut(run.error, ANSWER_CHARS) if run&.finished? && run.state != "succeeded" && run.error.present?),
      question: question,
      waits: waits(run)
    }
  end

  private

  def trace_events(run)
    return [] unless run

    ModelCall.where(task_run_id: run.id).order(:position).flat_map(&:event_list)
  end

  # R2: the agent's text, an action (tool and its main argument) or the action's result.
  def entry(event)
    case event["kind"]
    when "text"
      text = event["text"].to_s.strip
      text.empty? ? [] : [ { kind: "text", text: cut(text) } ]
    when "tool_use"
      [ { kind: "action", label: event["name"].to_s, text: cut(argument(event["input"])) } ]
    when "tool_result"
      [ { kind: "result", label: event["name"].to_s, source: event["source"], error: event["error"] == true, text: cut(event["content"]) } ]
    else
      []
    end
  end

  def argument(input)
    data = JSON.parse(input.to_s)
    return input.to_s unless data.is_a?(Hash)

    key = ARGUMENT_KEYS.find { |k| data[k].present? }
    value = key ? data[key] : data.values.first
    value.is_a?(Array) ? value.join(", ") : value.to_s
  rescue JSON::ParserError
    input.to_s
  end

  def question
    return unless @step.state == "waiting"

    @item.step_decisions.pending.where(epic_step_id: @step.id).order(:id).last&.then { |d| cut(d.question, ANSWER_CHARS) }
  end

  # G3: what a step that has not run (or waits to run again) waits for.
  def waits(run)
    return @step.retry_note if @step.state == "queued" && run&.retry_at
    return unless @step.state == "pending"

    holder = @item.waits_for
    return "“#{holder.title}” in this space (one epic at a time)" if holder # spec 037
    return "your approval of the plan" if @item.awaiting_approval
    return "the epic's start at #{@item.starts_at.in_time_zone.strftime("%-d %b %H:%M")}" if @item.starts_at && !@item.started_at && @item.starts_at > @now
    return "your answer or Try again on the epic" if @item.state == "blocked"

    earlier = @item.active_steps.where(position: ...@step.position).where.not(state: "succeeded").order(:position).first
    "step #{earlier.position} “#{earlier.title}”" if earlier
  end

  # R3, R5: secrets replaced, then cut with a mark.
  def cut(value, chars = ENTRY_CHARS)
    text = RunTrace.redact(value.to_s.strip).first
    text.length > chars ? "#{text[0, chars]}…" : text
  end

  def tail(value)
    text = RunTrace.redact(value.to_s).first
    text.length > TEXT_CHARS ? "…#{text[-TEXT_CHARS..]}" : text
  end

  def helpers = Rails.application.routes.url_helpers
end
