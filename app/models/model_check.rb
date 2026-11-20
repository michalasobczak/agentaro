# Spec 022, G4/R3: one short question to a model, the way a step would ask it — same program, arguments and
# minimal environment, its own temporary folder (removed afterwards), no working folder, a 60-second timeout.
# Not a task run: nothing appears on the calendar. Never raises.
class ModelCheck
  TIMEOUT = 60
  QUESTION = AgentCall::Prompt.new("You are being checked by Agentaro. Answer briefly.", "Reply with the single word: ok")

  Result = Data.define(:ok, :output, :seconds)

  # Stands in for a task run: AgentCall records nothing on it.
  CheckRun = Struct.new(:id) do
    def update!(*) = true
    def started_at = nil
  end

  def initialize(executor, model:, effort:, timeout: TIMEOUT, runs_dir: Rails.application.config.x.runs_dir)
    @executor, @model, @effort, @timeout, @runs_dir = executor, model, effort, timeout, Pathname(runs_dir)
  end

  def run
    return Result.new(false, "Choose a model first (or set the executor's default).", nil) if @model.blank? && needs_model?
    return Result.new(false, "The model name #{Executor::MODEL_NAME_RULE}.", nil) unless Executor.valid_model_name?(@model.presence)

    agent = Agent.new(name: "Model check", executor: @executor, model: @model.presence, effort: @effort.presence, enabled: true)
    check_run = CheckRun.new("check-#{SecureRandom.hex(8)}")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = AgentCall.new(check_run, agent, QUESTION, timeout: @timeout, runs_dir: @runs_dir).call
    seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    label = [ agent.effective_model || "tool's default", agent.effective_effort && "effort #{agent.effective_effort}" ].compact.join(", ")
    if outcome.state == "succeeded" && outcome.output.present?
      Result.new(true, ExecutorCheck.clean("#{label}: answered in #{seconds} s — #{outcome.output.truncate(200)}"), seconds)
    else
      Result.new(false, ExecutorCheck.clean("#{label}: #{outcome.error.presence || "no answer"}"), seconds)
    end
  ensure
    FileUtils.rm_rf(@runs_dir.join(check_run.id)) if check_run
  end

  private

  def needs_model? = !%w[claude_code codex].include?(@executor.preset) # those two have their own default
end
