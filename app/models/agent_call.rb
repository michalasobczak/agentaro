require "net/http"

# Specs 010, 011: calls an agent once — its executor with a prompt, in the run's own folder (spec 010, G3/G4).
# Used by task steps (TaskRunner) and by the management (ManagementRunner). Never raises.
class AgentCall
  NOT_RUNNABLE = "running %s is not supported yet (spec 010, Q3)"
  WEB_TOOLS = "WebSearch WebFetch"

  Outcome = Data.define(:state, :output, :error, :exit_status)

  # Spec 030, G1: a prompt keeps its named sections ([kind, text]) so the trace can store what the model saw part by
  # part; the user text is always the sections joined by the joiner, so text is exactly what is sent.
  PROMPT_SEPARATOR = "\n\n---\n\n"
  Prompt = Data.define(:system, :user, :sections, :joiner) do
    def initialize(system:, user: nil, sections: nil, joiner: "\n\n")
      sections = sections ? sections.map { |kind, value| [ kind.to_s, value.to_s ] } : [ [ "user", user.to_s ] ]
      joined = sections.map(&:last).join(joiner)
      # A changed user text must come as a changed section (prompt.with(sections: …)); otherwise it would be lost.
      raise ArgumentError, "user differs from its sections; change the sections" if user && user != joined
      super(system: system.to_s, user: joined, sections: sections.freeze, joiner: joiner)
    end

    # The user text follows the sections; changing it alone would be lost, so only sections may change.
    def with(**changes)
      raise ArgumentError, "change the sections, not the user text" if changes.key?(:user)

      super(**changes, user: nil)
    end

    def text = "#{system}#{PROMPT_SEPARATOR}#{user}"
  end

  # pass (spec 030): which call of the run this is, when a run makes more than one ("proposal").
  # schema (spec 044, G2): the JSON schema of the answer, for the director's calls; local servers are held to it.
  def initialize(run, agent, prompt, timeout: Rails.application.config.x.run_timeout, runs_dir: Rails.application.config.x.runs_dir, pass: nil, schema: nil)
    @run, @agent, @prompt, @pass, @schema = run, agent, prompt, pass, schema
    @timeout = timeout
    @runs_dir = Pathname(runs_dir)
  end

  # Marks the run as running (what ran is kept on the run, spec 010 R3) and returns the outcome.
  # on_text (spec 017): called with the answer so far while it streams — Claude Code, the Ollama API and
  # OpenAI-compatible APIs; other executors answer once at the end. The returned outcome is the same either way.
  def call(on_text: nil)
    @on_text = on_text
    @live = LiveLog.new(folder) if @run.is_a?(TaskRun) && @run.purpose == "epic_step" # spec 038: steps of epics
    started_at, clock = Time.current, Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = perform
    if @called # spec 030: every call that reached its executor leaves a trace; recording never breaks the run (R7)
      recorded = RunTrace.record(run: @run, agent: @agent, prompt: @prompt, outcome: outcome, pass: @pass, started_at: started_at,
                                 duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - clock, model: @model, effort: @effort,
                                 usage: @stream ? @stream.usage : @usage.to_h, events: @stream&.events, events_cut: @stream&.events_cut)
      @live&.clear! if recorded # spec 038: the trace is the record from now on; without one the live log stays
    end
    outcome
  end

  private

  def perform
    return Outcome.new("skipped", nil, "#{@agent.name} is not available (disabled agent or executor).", nil) unless @agent.usable?

    executor = @agent.executor
    model = @model = @agent.effective_model
    @effort = @agent.effective_effort # spec 022, G5
    @run.update!(state: "running", started_at: @run.started_at || Time.current, agent_name: @agent.name, executor_name: executor.name,
                 preset: executor.preset, model: model, prompt: @prompt.text)
    @called = true
    preset = executor.preset_definition
    return Outcome.new("skipped", nil, format(NOT_RUNNABLE, preset.label), nil) unless preset.runnable?
    unless Executor.valid_model_name?(model) # spec 022, R1: a name saved before the rule never reaches the tool
      return Outcome.new("failed", nil, "The model name #{model.inspect} #{Executor::MODEL_NAME_RULE}; fix it on the agent or executor.", nil)
    end

    preset.cli? ? run_cli(preset, executor, model, @prompt) : run_api(preset, executor, model, @prompt)
  rescue StandardError => e
    Rails.logger.error("[runs] run #{@run.id} failed: #{e.class}: #{e.message}")
    Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil)
  end

  def folder
    @folder ||= @runs_dir.join(@run.id.to_s).tap { |dir| FileUtils.mkdir_p(dir.join("work")) }
  end

  def work_dir = folder.join("work")

  # Spec 018: the space whose working folder this step runs in (steps of epics only; nil otherwise).
  def working_space
    space = @run.epic_step&.work_item&.space if @run.respond_to?(:epic_step)
    space if space&.working_dir.present?
  end

  # --- Command-line tools: prompt on standard input, fixed arguments, the run folder as working folder ---

  def run_cli(preset, executor, model, prompt)
    result = nil
    program = ExecutorCheck.locate(preset.program)
    return Outcome.new("failed", nil, "#{preset.program} was not found on this computer.", nil) unless program

    space = working_space
    return Outcome.new("failed", nil, "Working folder not found: #{space.working_dir}", nil) if space && !File.directory?(space.working_dir)

    @chdir = space ? space.working_dir : work_dir.to_s # spec 018: the space's folder, else the run's own empty folder
    args, stdin, answer_file = cli_call(preset.key, model, prompt, space)
    return Outcome.new("failed", nil, "Choose a model for #{executor.name} (agent or executor default).", nil) if args.nil?

    # Spec 030, G2: Claude Code always streams JSON, so its tool calls, usage and cost reach the trace.
    # Spec 038, G6: so does Codex (--json); its events reach the live log and the trace.
    on_event = @live && @live.method(:add)
    stream = @stream = case preset.key
                       when "claude_code" then ClaudeStream.new(@on_text, on_event: on_event)
                       when "codex" then CodexStream.new(on_event: on_event)
                       end
    args = stream.arguments(args) if stream
    on_stdout = stream ? stream.method(:feed) : (live_stdout if @live) # spec 038, G7: Ollama and LM Studio print their text
    result = begin
      HostProcess.run(program, args, stdin: stdin, chdir: @chdir, timeout: @timeout, max_output: (stream ? 4 : 1) * TaskRun::MAX_OUTPUT + 1024, # a bit more, so the cut is marked
                      on_stdout: on_stdout, on_spawn: ->(pid) { spawned(pid) }) # spec 025: can be stopped
    ensure
      RunControl.finished(@run.id)
      clean_up_processes # spec 040, G3: whatever the step left running
    end
    answer = answer_file && File.exist?(answer_file) ? File.read(answer_file) : (stream ? stream.answer(result.stdout) : result.stdout)
    if result.timed_out
      Outcome.new("timed_out", ExecutorCheck.clean_text(answer), "Stopped after #{@timeout.to_i / 60} minutes.", nil)
    elsif result.success?
      Outcome.new("succeeded", ExecutorCheck.clean_text(answer), nil, 0) # standard error holds progress logs only
    else
      log = ExecutorCheck.clean_text(result.stderr).presence
      error = limit_error(preset, executor, answer, log) || [ log, "#{preset.program} ended: #{result.ending}." ].compact.join("\n\n")
      Outcome.new("failed", ExecutorCheck.clean_text(answer).presence, error, result.exit_status)
    end
  ensure
    read_limits(preset, executor) if result
  end

  # Spec 043, G1: after every Claude Code or Codex call, the subscription's limit as the tool reported it.
  def read_limits(preset, executor)
    case preset.key
    when "claude_code" then UsageLimit.record!(executor, @stream&.limit_reading) unless @limit_recorded
    when "codex"
      reading, at = UsageLimit.codex_session_reading
      UsageLimit.record!(executor, reading, at: at) if reading && !@limit_recorded
    end
  end

  # Spec 043, G3: a call that ended on a usage limit says so plainly ("Claude Code: 5-hour usage limit reached until
  # 15:10.") and marks its executor; the text is the tool's own output, never a successful agent's words (R6).
  def limit_error(preset, executor, answer, log)
    return unless %w[claude_code codex].include?(preset.key)

    text = preset.key == "codex" ? [ log, *@stream&.errors ].compact.join("\n") : [ answer, log ].compact.join("\n")
    failure = UsageLimit.failure(preset.label, text, reading: (@stream&.limit_reading if preset.key == "claude_code")) or return
    UsageLimit.record!(executor, failure[:reading])
    @limit_recorded = true
    failure[:message]
  end

  # Spec 038, G7: the text a command-line tool prints, as it prints it (terminal codes removed).
  def live_stdout
    text = +""
    lambda do |chunk|
      text << chunk.dup.force_encoding(Encoding::UTF_8)
      text = text.byteslice(-LiveLog::MAX_TEXT * 2, LiveLog::MAX_TEXT * 2).scrub("") if text.bytesize > LiveLog::MAX_TEXT * 2
      @live.text(text.gsub(/\e\[[0-9;?]*[A-Za-z]/, ""))
    end
  end

  # Spec 017: the answer so far, to whoever reads it — the chat (on_text) and the live log of a step (spec 038, G7).
  def emit_text(text)
    @on_text&.call(text)
    @live&.text(text)
  end

  # Spec 025: the run can be stopped; spec 036, R5: its process is saved, so a restart waits for it to end.
  # Spec 040, G3: a step's processes are followed from here on.
  def spawned(pid)
    RunControl.started(@run.id, pid)
    @tracker = ProcessTracker.new(folder, pid).start if @live
    @run.update!(pid: pid)
  rescue StandardError => e
    Rails.logger.error("[runs] could not save the process of run #{@run.id}: #{e.class}: #{e.message}")
  end

  # Spec 040, G3, R4: stops every process the step started that is still alive; the step's log says which.
  def clean_up_processes
    stopped = @tracker&.finish! or return
    return if stopped.empty?

    event = { "kind" => "text", "text" => "Agentaro stopped #{stopped.size} process#{"es" unless stopped.size == 1} the step left running: #{stopped.first(10).join("; ")}" }
    @live&.add(event)
    @stream.events << event if @stream && @stream.events.size < ClaudeStream::MAX_EVENTS
  rescue StandardError => e
    Rails.logger.error("[processes] run #{@run.id}: #{e.class}: #{e.message}")
  end

  # Spec 017: a streamed API answer — Ollama sends JSON lines, OpenAI-compatible servers send "data:" lines.
  def stream_api(preset, uri, body)
    text = +""
    buffer = +""
    status = nil
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: @timeout, write_timeout: 30) do |http|
      http.request(Net::HTTP::Post.new(uri, "Content-Type" => "application/json"), body.to_json) do |response|
        status = response
        next unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          buffer << chunk
          while (line = buffer.slice!(/\A[^\n]*\n/))
            piece = stream_piece(preset, line.strip) or next
            text << piece
            raise IOError, "answer too long" if text.bytesize > TaskRun::MAX_OUTPUT
            emit_text(text)
          end
        end
        if (piece = stream_piece(preset, buffer.strip)) # a last line without its newline
          text << piece
          emit_text(text)
        end
      end
    end
    return Outcome.new("failed", nil, "Answered #{status.code} #{status.message}.", status.code.to_i) unless status.is_a?(Net::HTTPSuccess)

    Outcome.new("succeeded", text, nil, nil)
  end

  # Spec 030, G3: tokens as the local servers report them (Ollama: prompt_eval_count/eval_count; OpenAI: usage).
  def api_usage(preset, data)
    return {} unless data.is_a?(Hash)

    if preset.protocol == "ollama"
      { input_tokens: data["prompt_eval_count"], output_tokens: data["eval_count"] }.compact
    else
      usage = data["usage"].is_a?(Hash) ? data["usage"] : {}
      { input_tokens: usage["prompt_tokens"], output_tokens: usage["completion_tokens"] }.compact
    end
  end

  def stream_piece(preset, line)
    if preset.protocol == "ollama"
      return unless line.start_with?("{")

      data = JSON.parse(line)
      @usage = api_usage(preset, data) if data["done"]
      note_tool_calls(data.dig("message", "tool_calls"))
      data.dig("message", "content")
    elsif line.start_with?("data:") && line != "data: [DONE]"
      delta = JSON.parse(line.delete_prefix("data:").strip).dig("choices", 0, "delta") || {}
      note_tool_calls(delta["tool_calls"])
      delta["content"]
    end
  rescue JSON::ParserError
    nil
  end

  # [arguments, standard input, answer file]; nil arguments when a needed model is missing.
  def cli_call(key, model, prompt, space = nil)
    case key
    when "claude_code"
      # Web search and fetch are allowed (owner fix: "Claude said, that it couldnt use web search"); in print
      # mode every tool that is not allowed up front is refused.
      args = [ "-p", "--output-format", "text", "--no-session-persistence", "--permission-mode", "acceptEdits",
               "--allowedTools", (space ? "Bash #{WEB_TOOLS}" : WEB_TOOLS), "--settings", claude_settings(space) ]
      args += [ "--model", model ] if model
      args += [ "--effort", @effort ] if @effort # spec 022, G5
      [ args, prompt.text, nil ]
    when "codex"
      answer = folder.join("answer.txt").to_s
      args = [ "--search", "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--ephemeral", "--color", "never", "-C", @chdir, "-o", answer ]
      args.insert(5, "-c", "sandbox_workspace_write.network_access=true") if space # spec 018, Q5: network in a working folder (reads not limited: F17)
      args += [ "-m", model ] if model
      args += [ "-c", "model_reasoning_effort=#{@effort}" ] if @effort # spec 022, G5
      [ args + [ "-" ], prompt.text, answer ]
    when "ollama_cli"
      model ? [ [ "run", model ], prompt.text, nil ] : nil
    when "lm_studio_cli"
      model ? [ [ "chat", model, "-p", prompt.user, "-s", prompt.system ], nil, nil ] : nil # LM Studio reads no stdin (accepted, spec 010)
    end
  end

  # R4: writes and commands sandboxed to the run folder; Agentaro's storage (databases, secrets) unreadable.
  # Spec 018, G3/G4: in a space's working folder — writes there and in temp folders, any command, any host, the
  # Docker socket (Q6); reads of other spaces' folders, Agentaro's storage and other runs denied for both Claude's
  # tools and its commands (checked on the host).
  def claude_settings(space = nil)
    return folder_settings(space) if space

    storage = Rails.root.join("storage").realpath.to_s
    { permissions: { deny: [ "Read(/#{storage}/**)", "Edit(/#{storage}/**)" ] },
      sandbox: { enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false, filesystem: { denyRead: [ storage ] } } }.to_json
  end

  def folder_settings(space)
    denied = space.denied_dirs
    sockets = [ Rails.application.config.x.docker_socket ].compact
    { permissions: { allow: [ "Bash", "WebFetch", "WebSearch" ],
                     deny: denied.flat_map { |dir| [ "Read(/#{dir}/**)", "Edit(/#{dir}/**)" ] } },
      sandbox: { enabled: true, failIfUnavailable: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false,
                 filesystem: { denyRead: denied },
                 network: { allowedDomains: [ "*" ], allowUnixSockets: sockets } } }.to_json
  end

  # --- Local APIs without a key: one chat request ---

  def run_api(preset, executor, model, prompt)
    return Outcome.new("failed", nil, "Choose a model for #{executor.name} (agent or executor default).", nil) unless model

    messages = [ { role: "system", content: prompt.system }, { role: "user", content: prompt.user } ]
    stream = @on_text.present? || @live.present? # spec 038, G7: a step's text streams for its live view
    path, body = preset.protocol == "ollama" ? [ "/api/chat", { model: model, messages: messages, stream: stream } ] : [ "/chat/completions", { model: model, messages: messages, stream: stream } ]
    uri = URI.parse(executor.base_url + path)
    @api_tools = []
    if @schema # spec 044, G2: the whole prompt fits, the answer has the schema's shape, no thinking
      outcome = api_request(preset, uri, body.merge(structured(preset, prompt)), stream)
      return checked_api_answer(outcome, executor) unless outcome.state == "failed" && outcome.exit_status.to_i.between?(400, 499) # resilience: once more without
    end
    checked_api_answer(api_request(preset, uri, body, stream), executor)
  end

  # Owner fix: a plain chat API has no tools (files, commands, web). A model that only asked for one, or answered
  # nothing, did not do the work — never a success with an empty answer.
  def checked_api_answer(outcome, executor)
    return outcome unless outcome.state == "succeeded" && outcome.output.to_s.strip.empty?

    if @api_tools.any?
      Outcome.new("failed", nil, "The model asked to use the tool #{@api_tools.uniq.first(3).join(", ")}, but #{executor.label} has no tools: " \
                                 "it cannot read files, run commands or use the web, only answer in text. Give such work to a member on Claude Code or Codex.", nil)
    else
      Outcome.new("failed", nil, "The model gave an empty answer.", nil)
    end
  end

  def note_tool_calls(calls)
    Array(calls).each { |c| @api_tools << (c.is_a?(Hash) ? (c.dig("function", "name") || c["name"]).to_s.presence : nil) || "a tool" } if calls.present?
  end

  # Spec 044, G2: what a director call adds for a local server.
  CONTEXT_MIN = 16_384
  CONTEXT_MAX = 32_768
  ANSWER_TOKENS = 3072 # a director's answer is short; a held model that keeps writing (whitespace) stops here
  def structured(preset, prompt)
    if preset.protocol == "ollama"
      tokens = (prompt.text.bytesize / 3.0).ceil + 4096 # room for the answer; Polish text is about 3 bytes a token or more
      { format: @schema, think: false, options: { num_ctx: (tokens.clamp(CONTEXT_MIN, CONTEXT_MAX) / 1024.0).ceil * 1024, num_predict: ANSWER_TOKENS } }
    else
      { response_format: { type: "json_schema", json_schema: { name: "answer", schema: @schema } }, max_tokens: ANSWER_TOKENS }
    end
  end

  def api_request(preset, uri, body, stream)
    return stream_api(preset, uri, body) if stream

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: @timeout, write_timeout: 30) do |http|
      http.request(Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "application/json"), body.to_json)
    end
    raw = response.body.to_s.byteslice(0, TaskRun::MAX_OUTPUT * 2)
    return Outcome.new("failed", nil, "Answered #{response.code} #{response.message}. #{ExecutorCheck.clean(raw)}", response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(raw)
    @usage = api_usage(preset, data)
    message = preset.protocol == "ollama" ? data["message"] : data.dig("choices", 0, "message")
    note_tool_calls(message["tool_calls"]) if message.is_a?(Hash)
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
