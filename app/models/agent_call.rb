require "net/http"

# Specs 010, 011: calls an agent once — its executor with a prompt, in the run's own folder (spec 010, G3/G4).
# Used by task steps (TaskRunner) and by the management (ManagementRunner). Never raises.
class AgentCall
  NOT_RUNNABLE = "running %s is not supported yet (spec 010, Q3)"
  WEB_TOOLS = "WebSearch WebFetch"

  Outcome = Data.define(:state, :output, :error, :exit_status)

  Prompt = Data.define(:system, :user) do
    def text = "#{system}\n\n---\n\n#{user}"
  end

  def initialize(run, agent, prompt, timeout: Rails.application.config.x.run_timeout, runs_dir: Rails.application.config.x.runs_dir)
    @run, @agent, @prompt = run, agent, prompt
    @timeout = timeout
    @runs_dir = Pathname(runs_dir)
  end

  # Marks the run as running (what ran is kept on the run, spec 010 R3) and returns the outcome.
  # on_text (spec 017): called with the answer so far while it streams — Claude Code, the Ollama API and
  # OpenAI-compatible APIs; other executors answer once at the end. The returned outcome is the same either way.
  def call(on_text: nil)
    @on_text = on_text
    return Outcome.new("skipped", nil, "#{@agent.name} is not available (disabled agent or executor).", nil) unless @agent.usable?

    executor = @agent.executor
    model = @agent.model || executor.default_model
    @run.update!(state: "running", started_at: @run.started_at || Time.current, agent_name: @agent.name, executor_name: executor.name,
                 preset: executor.preset, model: model, prompt: @prompt.text)
    preset = executor.preset_definition
    return Outcome.new("skipped", nil, format(NOT_RUNNABLE, preset.label), nil) unless preset.runnable?

    preset.cli? ? run_cli(preset, executor, model, @prompt) : run_api(preset, executor, model, @prompt)
  rescue StandardError => e
    Rails.logger.error("[runs] run #{@run.id} failed: #{e.class}: #{e.message}")
    Outcome.new("failed", nil, "#{e.class}: #{e.message}", nil)
  end

  private

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
    program = ExecutorCheck.locate(preset.program)
    return Outcome.new("failed", nil, "#{preset.program} was not found on this computer.", nil) unless program

    space = working_space
    return Outcome.new("failed", nil, "Working folder not found: #{space.working_dir}", nil) if space && !File.directory?(space.working_dir)

    @chdir = space ? space.working_dir : work_dir.to_s # spec 018: the space's folder, else the run's own empty folder
    args, stdin, answer_file = cli_call(preset.key, model, prompt, space)
    return Outcome.new("failed", nil, "Choose a model for #{executor.name} (agent or executor default).", nil) if args.nil?

    stream = @on_text && preset.key == "claude_code" ? ClaudeStream.new(@on_text) : nil
    args = stream.arguments(args) if stream
    result = HostProcess.run(program, args, stdin: stdin, chdir: @chdir, timeout: @timeout, max_output: (stream ? 4 : 1) * TaskRun::MAX_OUTPUT + 1024, # a bit more, so the cut is marked
                             on_stdout: stream&.method(:feed))
    answer = answer_file && File.exist?(answer_file) ? File.read(answer_file) : (stream ? stream.answer(result.stdout) : result.stdout)
    if result.timed_out
      Outcome.new("timed_out", ExecutorCheck.clean_text(answer), "Stopped after #{@timeout.to_i / 60} minutes.", nil)
    elsif result.success?
      Outcome.new("succeeded", ExecutorCheck.clean_text(answer), nil, 0) # standard error holds progress logs only
    else
      Outcome.new("failed", ExecutorCheck.clean_text(answer).presence, ExecutorCheck.clean_text(result.stderr).presence || "Exited with status #{result.exit_status}.", result.exit_status)
    end
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
            @on_text.call(text)
          end
        end
      end
    end
    return Outcome.new("failed", nil, "Answered #{status.code} #{status.message}.", status.code.to_i) unless status.is_a?(Net::HTTPSuccess)

    Outcome.new("succeeded", text, nil, nil)
  end

  def stream_piece(preset, line)
    if preset.protocol == "ollama"
      JSON.parse(line).dig("message", "content") if line.start_with?("{")
    elsif line.start_with?("data:") && line != "data: [DONE]"
      JSON.parse(line.delete_prefix("data:").strip).dig("choices", 0, "delta", "content")
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
      [ args, prompt.text, nil ]
    when "codex"
      answer = folder.join("answer.txt").to_s
      args = [ "--search", "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--ephemeral", "--color", "never", "-C", @chdir, "-o", answer ]
      args.insert(5, "-c", "sandbox_workspace_write.network_access=true") if space # spec 018, Q5: network in a working folder (reads not limited: F17)
      args += [ "-m", model ] if model
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
    stream = @on_text.present?
    path, body = preset.protocol == "ollama" ? [ "/api/chat", { model: model, messages: messages, stream: stream } ] : [ "/chat/completions", { model: model, messages: messages, stream: stream } ]
    uri = URI.parse(executor.base_url + path)
    return stream_api(preset, uri, body) if stream

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
