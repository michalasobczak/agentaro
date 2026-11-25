require "test_helper"

# Spec 055: opencode as an executor — the preset, finding the CLI, its models, a run and its event stream.
class OpencodeExecutorTest < ActiveSupport::TestCase
  # Events as opencode 2.4.1 wrote them on this computer (shortened).
  EVENTS = [
    { type: "step_start", part: { type: "step-start" } },
    { type: "tool_use", part: { type: "tool", callID: "c1", tool: "write", state: { status: "completed", input: { path: "hello.txt", content: "hi\n" }, output: "Created file successfully: hello.txt" } } },
    { type: "tool_use", part: { type: "tool", callID: "c2", tool: "shell", state: { status: "error", input: { command: "false" }, error: "exit 1" } } },
    { type: "step_finish", part: { type: "step-finish", reason: "tool-calls", cost: 0, tokens: { input: 6687, output: 138, reasoning: 2, cache: { read: 2688, write: 0 } } } },
    { type: "step_start", part: { type: "step-start" } },
    { type: "text", part: { type: "text", text: "Utworzyłem plik hello.txt — gotowe." } },
    { type: "step_finish", part: { type: "step-finish", reason: "stop", cost: 0, tokens: { input: 333, output: 39, reasoning: 0, cache: { read: 9344, write: 0 } } } }
  ].map(&:to_json).join("\n") + "\n"

  setup do
    @user = create_user
    @bin = Dir.mktmpdir("opencode-bin")
    @executor = Executor.create!(name: "opencode", preset: "opencode")
    @agent = Agent.create!(user: @user, name: "Tani", master_prompt: "You work.", executor: @executor)
  end

  teardown { FileUtils.rm_rf(@bin) }

  # A stand-in opencode: prints its arguments and standard input to files, then the given output.
  def fake_opencode(stdout, exit_code: 0)
    path = File.join(@bin, "opencode-cli")
    File.write(File.join(@bin, "out.jsonl"), stdout)
    File.write(path, <<~SH)
      #!/bin/sh
      if [ "$1" = "--version" ]; then echo "opencode v2.4.1"; exit 0; fi
      if [ "$1" = "models" ]; then printf 'opencode/deepseek-v4.1-flash-free\\nopencode/big-pickle\\n-bad\\nollama/qwen3:8b\\n'; exit 0; fi
      printf '%s\\n' "$@" > "#{@bin}/args"
      cat > "#{@bin}/stdin"
      cat "#{@bin}/out.jsonl"
      exit #{exit_code}
    SH
    File.chmod(0o755, path)
    path
  end

  def with_env(value)
    original = ENV["AGENTARO_OPENCODE_BIN"]
    ENV["AGENTARO_OPENCODE_BIN"] = value
    yield
  ensure
    ENV["AGENTARO_OPENCODE_BIN"] = original
  end

  def chat_run = TaskRun.create!(user: @user, agent: @agent, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "running")

  test "G1: the preset, with opencode's free DeepSeek as the default model; it says it has no sandbox" do
    assert_equal [ "opencode", "cli", "opencode" ], [ @executor.label, @executor.kind, @executor.preset_definition.program ]
    assert_equal "opencode/deepseek-v4.1-flash-free", @executor.default_model
    assert @executor.unsandboxed?
    assert_not Executor.create!(name: "Claude", preset: "claude_code").unsandboxed?
  end

  test "G2: AGENTARO_OPENCODE_BIN first; then the path; then the newest CLI of the desktop app" do
    app = Dir.mktmpdir("opencode-app")
    %w[2.3.9-arm64 2.4.1-arm64 2.10.0-arm64].each do |version|
      FileUtils.mkdir_p(File.join(app, version))
      File.write(File.join(app, version, "opencode-cli"), "#!/bin/sh\n").then { File.chmod(0o755, File.join(app, version, "opencode-cli")) }
    end
    glob = File.join(app, "*", "opencode-cli")
    assert_equal File.join(app, "2.10.0-arm64", "opencode-cli"), ExecutorCheck.opencode(path: "", env: nil, app: glob), "numeric versions"
    on_path = File.join(@bin, "opencode").tap { |f| File.write(f, "#!/bin/sh\n"); File.chmod(0o755, f) }
    assert_equal on_path, ExecutorCheck.opencode(path: @bin, env: nil, app: glob)
    assert_equal on_path, ExecutorCheck.opencode(path: "", env: on_path, app: glob)
    assert_nil ExecutorCheck.opencode(path: @bin, env: File.join(@bin, "missing"), app: glob), "a wrong setting is not silently replaced"
  ensure
    FileUtils.rm_rf(app) if app
  end

  test "S1, S2: Check shows the version; Refresh models lists opencode's models, without names that look like options" do
    with_env(fake_opencode("")) do
      assert_equal [ true, "opencode v2.4.1" ], @executor.check!.then { |r| [ r.ok, r.output ] }
      @executor.refresh_models!
    end
    assert_equal [ "opencode/deepseek-v4.1-flash-free", "opencode/big-pickle", "ollama/qwen3:8b" ], @executor.reload.model_choices.map { |m| m["name"] }
  end

  test "G4, R2: a run passes fixed arguments, the model as one argument and the prompt on standard input only" do
    with_env(fake_opencode(EVENTS)) do
      outcome = AgentCall.new(chat_run, @agent, AgentCall::Prompt.new(system: "s", user: "SEKRETNY prompt")).call
      assert_equal [ "succeeded", "Utworzyłem plik hello.txt — gotowe." ], [ outcome.state, outcome.output ]
    end
    assert_equal %w[run --standalone --archived --auto --format json -m opencode/deepseek-v4.1-flash-free], File.read(File.join(@bin, "args")).lines.map(&:chomp)
    assert_match "SEKRETNY prompt", File.read(File.join(@bin, "stdin"))
  end

  test "G4: the trace keeps the tool calls and the summed tokens (spec 030)" do
    with_env(fake_opencode(EVENTS)) { AgentCall.new(chat_run, @agent, AgentCall::Prompt.new(system: "s", user: "u")).call }
    call = ModelCall.order(:id).last
    assert_equal [ 7020, 179, 12_032, 2 ], [ call.input_tokens, call.output_tokens, call.cache_read_tokens, call.turns ]
  end

  test "an error event is the run's error; an empty answer is a failure" do
    error = { type: "error", error: { type: "provider.no-route", message: "Model unavailable: opencode/x" } }.to_json + "\n"
    with_env(fake_opencode(error, exit_code: 1)) do
      outcome = AgentCall.new(chat_run, @agent, AgentCall::Prompt.new(system: "s", user: "u")).call
      assert_equal "failed", outcome.state
      assert_match "Model unavailable: opencode/x", outcome.error
    end
    with_env(fake_opencode(EVENTS.lines.first)) do
      outcome = AgentCall.new(chat_run, @agent, AgentCall::Prompt.new(system: "s", user: "u")).call
      assert_equal [ "failed", "opencode gave no answer." ], [ outcome.state, outcome.error ]
    end
  end

  test "the stream: tools become tool_use and tool_result; a chunk that ends inside a Polish letter waits for its half" do
    seen = []
    texts = []
    stream = OpencodeStream.new(on_text: ->(t) { texts << t }, on_event: ->(e) { seen << e })
    bytes = EVENTS.b
    cut = bytes.index("ł".b) + 1
    stream.feed(bytes.byteslice(0, cut))
    stream.feed(bytes.byteslice(cut..))
    assert_equal %w[tool_use tool_result tool_use tool_result text], seen.map { |e| e["kind"] }
    assert_equal [ "Write", "Bash" ], seen.select { |e| e["kind"] == "tool_use" }.map { |e| e["name"] }
    assert_equal true, seen[3]["error"]
    assert_equal [ "Utworzyłem plik hello.txt — gotowe." ], texts
    assert_equal "Utworzyłem plik hello.txt — gotowe.", stream.answer("")
  end

  test "G6: the director's context says which members work on opencode, without a sandbox" do
    @user.team_roles.create!(agent: @agent, role: "member")
    text = ManagementRunner.new(chat_run).send(:member_line, @user.team_roles.find_by(agent: @agent))
    assert_match "on opencode with opencode/deepseek-v4.1-flash-free: files, commands and the web, no sandbox", text
  end
end
