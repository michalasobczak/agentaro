require "net/http"

# Spec 010: runs one TaskRun — reads the task and its agent at run time (R2), builds the prompt (G2) and
# sends it to the executor (G3) in the run's own folder (G4). Never raises: every outcome is a state.
class TaskRunner
  NOT_RUNNABLE = "running %s is not supported yet (spec 010, Q3)"
  WEB_TOOLS = "WebSearch WebFetch"

  Outcome = Data.define(:state, :output, :error, :exit_status)

  def initialize(run, timeout: Rails.application.config.x.run_timeout, runs_dir: Rails.application.config.x.runs_dir)
    @run = run
    @timeout = timeout
    @runs_dir = Pathname(runs_dir)
  end

  def perform!
    task = @run.task
    agent = task.agent
    return finish!(Outcome.new("skipped", nil, "The task has no agent.", nil)) unless agent
    return finish!(Outcome.new("skipped", nil, "#{agent.name} is not available (disabled agent or executor).", nil)) unless agent.usable?

    executor = agent.executor
    model = agent.model || executor.default_model
    prompt = self.class.prompt_for(task, agent, @run.occurrence_start)
    @run.update!(state: "running", started_at: Time.current, agent_name: agent.name, executor_name: executor.name,
                 preset: executor.preset, model: model, prompt: prompt.text)
    preset = executor.preset_definition
    return finish!(Outcome.new("skipped", nil, format(NOT_RUNNABLE, preset.label), nil)) unless preset.runnable?

    finish!(preset.cli? ? run_cli(preset, executor, model, prompt) : run_api(preset, executor, model, prompt))
  rescue StandardError => e
    Rails.logger.error("[runs] run #{@run.id} failed: #{e.class}: #{e.message}")
    finish!(Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil))
  end

  Prompt = Data.define(:system, :user) do
    def text = "#{system}\n\n---\n\n#{user}"
  end

  # G2: the agent's master prompt, then the task in the app's time zone.
  def self.prompt_for(task, agent, occurrence_start)
    occurrence = task.occurrence_at(occurrence_start) || Task::Occurrence.new(task: task, starts_at: task.starts_at, ends_at: task.ends_at, original_start: task.starts_at)
    starts, ends = occurrence.starts_at.in_time_zone, occurrence.ends_at.in_time_zone
    lines = [ "Your task: #{task.title}",
              "When: #{starts.strftime("%A %-d %B %Y, %H:%M")} – #{ends.strftime(starts.to_date == ends.to_date ? "%H:%M" : "%A %-d %B %Y, %H:%M")} (#{Time.zone.name})" ]
    lines << "Location: #{task.location}" if task.location.present?
    lines << "\nDetails:\n#{task.description}" if task.description.present?
    lines << "\nDo the task now and answer with the result."
    Prompt.new(system: agent.master_prompt, user: lines.join("\n"))
  end

  private

  def finish!(outcome)
    @run.update!(state: outcome.state, output: TaskRun.limit_text(outcome.output, TaskRun::MAX_OUTPUT).presence,
                 error: TaskRun.limit_text(outcome.error, TaskRun::MAX_ERROR).presence,
                 exit_status: outcome.exit_status, started_at: @run.started_at || Time.current, finished_at: Time.current)
    @run
  end

  def folder
    @folder ||= @runs_dir.join(@run.id.to_s).tap { |dir| FileUtils.mkdir_p(dir.join("work")) }
  end

  def work_dir = folder.join("work")

  # --- Command-line tools: prompt on standard input, fixed arguments, the run folder as working folder ---

  def run_cli(preset, executor, model, prompt)
    program = ExecutorCheck.locate(preset.program)
    return Outcome.new("failed", nil, "#{preset.program} was not found on this computer.", nil) unless program

    args, stdin, answer_file = cli_call(preset.key, model, prompt)
    return Outcome.new("failed", nil, "Choose a model for #{executor.name} (agent or executor default).", nil) if args.nil?

    result = HostProcess.run(program, args, stdin: stdin, chdir: work_dir.to_s, timeout: @timeout, max_output: TaskRun::MAX_OUTPUT + 1024) # a bit more, so the cut is marked
    answer = answer_file && File.exist?(answer_file) ? File.read(answer_file) : result.stdout
    if result.timed_out
      Outcome.new("timed_out", ExecutorCheck.clean_text(answer), "Stopped after #{@timeout.to_i / 60} minutes.", nil)
    elsif result.success?
      Outcome.new("succeeded", ExecutorCheck.clean_text(answer), nil, 0) # standard error holds progress logs only
    else
      Outcome.new("failed", ExecutorCheck.clean_text(answer).presence, ExecutorCheck.clean_text(result.stderr).presence || "Exited with status #{result.exit_status}.", result.exit_status)
    end
  end

  # [arguments, standard input, answer file]; nil arguments when a needed model is missing.
  def cli_call(key, model, prompt)
    case key
    when "claude_code"
      # Web search and fetch are allowed (owner fix: "Claude said, that it couldnt use web search"); in print
      # mode every tool that is not allowed up front is refused.
      args = [ "-p", "--output-format", "text", "--no-session-persistence", "--permission-mode", "acceptEdits",
               "--allowedTools", WEB_TOOLS, "--settings", claude_settings ]
      args += [ "--model", model ] if model
      [ args, prompt.text, nil ]
    when "codex"
      answer = folder.join("answer.txt").to_s
      args = [ "--search", "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--ephemeral", "--color", "never", "-C", work_dir.to_s, "-o", answer ]
      args += [ "-m", model ] if model
      [ args + [ "-" ], prompt.text, answer ]
    when "ollama_cli"
      model ? [ [ "run", model ], prompt.text, nil ] : nil
    when "lm_studio_cli"
      model ? [ [ "chat", model, "-p", prompt.user, "-s", prompt.system ], nil, nil ] : nil # LM Studio reads no stdin (accepted, spec 010)
    end
  end

  # R4: writes and commands sandboxed to the run folder; Agentaro's storage (databases, secrets) unreadable.
  def claude_settings
    storage = Rails.root.join("storage").realpath.to_s
    { permissions: { deny: [ "Read(/#{storage}/**)", "Edit(/#{storage}/**)" ] },
      sandbox: { enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false, filesystem: { denyRead: [ storage ] } } }.to_json
  end

  # --- Local APIs without a key: one chat request ---

  def run_api(preset, executor, model, prompt)
    return Outcome.new("failed", nil, "Choose a model for #{executor.name} (agent or executor default).", nil) unless model

    messages = [ { role: "system", content: prompt.system }, { role: "user", content: prompt.user } ]
    path, body = preset.protocol == "ollama" ? [ "/api/chat", { model: model, messages: messages, stream: false } ] : [ "/chat/completions", { model: model, messages: messages } ]
    uri = URI.parse(executor.base_url + path)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: @timeout, write_timeout: 30) do |http|
      http.request(Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "application/json"), body.to_json)
    end
    raw = response.body.to_s.byteslice(0, TaskRun::MAX_OUTPUT * 2)
    return Outcome.new("failed", nil, "Answered #{response.code} #{response.message}. #{ExecutorCheck.clean(raw)}", response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(raw)
    answer = preset.protocol == "ollama" ? data.dig("message", "content") : data.dig("choices", 0, "message", "content")
    answer.is_a?(String) ? Outcome.new("succeeded", answer, nil, nil) : Outcome.new("failed", nil, "The answer had no message.", nil)
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    Outcome.new("timed_out", nil, "No answer within the time limit.", nil)
  rescue JSON::ParserError
    Outcome.new("failed", nil, "The answer was not JSON.", nil)
  rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError => e
    Outcome.new("failed", nil, "Could not connect: #{e.message}", nil)
  end
end
