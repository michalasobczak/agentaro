require "test_helper"
require "socket"

# Spec 049: Codex with a local model — the arguments (S1), a missing model (S3), the model list and the director's
# view of the member (G4).
class CodexLocalTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Codex lokalny", preset: "codex_local", default_model: "mimo-v2.6")
    @agent = Agent.create!(user: @user, name: "Lokalny inżynier", master_prompt: "You build.", executor: @executor)
    @log = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@log) }

  # An Ollama that answers /api/tags with the given models, for as many requests as come.
  def with_ollama(models)
    server = TCPServer.new("127.0.0.1", 0)
    body = { models: models.map { |m| { name: m } } }.to_json
    thread = Thread.new do
      loop do
        client = server.accept
        while (line = client.gets) && line != "\r\n"; end
        client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    rescue IOError, SystemCallError
      nil
    end
    original = ENV["AGENTARO_OLLAMA_URL"]
    ENV["AGENTARO_OLLAMA_URL"] = "http://127.0.0.1:#{server.addr[1]}"
    yield
  ensure
    ENV["AGENTARO_OLLAMA_URL"] = original
    server&.close
    thread&.kill
  end

  def with_codex
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "codex"), <<~SH)
        #!/bin/sh
        echo "$@" > "#{@log}/args"
        cat > /dev/null
        out=""; prev=""
        for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
        echo '{"type":"item.completed","item":{"id":"1","type":"command_execution","command":"sed -n 1p README.md","aggregated_output":"# Projekt","exit_code":0}}'
        echo '{"type":"item.completed","item":{"id":"2","type":"agent_message","text":"Pierwszy wiersz: # Projekt"}}'
        printf 'Pierwszy wiersz: # Projekt' > "$out"
      SH
      File.chmod(0o755, File.join(bin, "codex"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def call
    run = TaskRun.create!(user: @user, agent: @agent, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
    AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "s", user: "Przeczytaj README.md")).call
  end

  test "S1, G2: Codex runs the local model, with Codex's sandbox and without web search" do
    @user.update!(relaxed_sandbox: false) # the strict sandbox as before; spec 053 adds the network (below)
    with_ollama([ "mimo-v2.6:latest", "qwen3:8b" ]) do
      with_codex do
        outcome = call
        assert_equal [ "succeeded", "Pierwszy wiersz: # Projekt" ], [ outcome.state, outcome.output ]
      end
    end
    args = File.read(File.join(@log, "args"))
    assert_match "exec --json --oss --local-provider ollama --skip-git-repo-check --sandbox workspace-write --ephemeral", args # --json: the stream, as for Codex
    assert_match "-m mimo-v2.6", args
    assert_no_match(/--search/, args)
    assert_no_match(/model_reasoning_effort/, args)

    @user.update!(relaxed_sandbox: true) # spec 053, G2: with the relaxed sandbox, network access outside a folder too
    with_ollama([ "mimo-v2.6:latest" ]) { with_codex { call } }
    assert_match "--sandbox workspace-write -c sandbox_workspace_write.network_access=true --ephemeral", File.read(File.join(@log, "args"))
  end

  test "S3: a model that is not in the local Ollama fails with a plain reason, and Codex is never asked to pull it" do
    with_ollama([ "qwen3:8b" ]) do
      with_codex do
        outcome = call
        assert_equal "failed", outcome.state
        assert_match "The model mimo-v2.6 is not in the local Ollama", outcome.error
      end
    end
    assert_not File.exist?(File.join(@log, "args")), "Codex did not run"
  end

  test "G1: the executor's models are the local Ollama's" do
    with_ollama([ "mimo-v2.6:latest", "bge-m3:latest" ]) do
      assert_equal %w[mimo-v2.6:latest bge-m3:latest], ModelList.new(@executor).run.models.map { |m| m["name"] }
    end
  end

  test "G4: the director sees the member works with files and commands, slowly" do
    @user.team_roles.create!(agent: @agent, role: "member", role_text: "inżynier")
    line = ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:member_line, @user.team_roles.members.sole)
    assert_match "on Codex (local model): files and commands, but slower — give it time", line
    assert_no_match(/text only/, line)
  end

  test "S1: in a space's working folder the network is on, as for Codex, and the sandbox stays whole" do
    folder = Dir.mktmpdir
    space = @user.spaces.create!(kind: "project", name: "Projekt", goal: "x", working_dir: folder)
    item = @user.work_items.create!(title: "Odczyt", space: space, state: "planned")
    step = item.epic_steps.create!(position: 1, title: "Czytaj", agent: @agent, state: "pending")
    with_ollama([ "mimo-v2.6:latest" ]) do
      with_codex do
        run = StepChain.queue_next(item)
        StepChain.new(run).perform!
        assert_equal "succeeded", run.reload.state
      end
    end
    args = File.read(File.join(@log, "args"))
    assert_match "--sandbox workspace-write -c sandbox_workspace_write.network_access=true --ephemeral", args
    assert_match(/-C \S*#{File.basename(folder)} /, args, "Codex works in the space's folder")
    assert step.reload.state == "succeeded"
  ensure
    FileUtils.rm_rf(folder)
  end

  test "G3: Codex's lines about refreshing its model list are not the step's error" do
    with_ollama([ "mimo-v2.6:latest" ]) do
      Dir.mktmpdir do |bin|
        File.write(File.join(bin, "codex"), "#!/bin/sh\ncat > /dev/null\necho '2026-11-22T20:02:27Z ERROR codex_models_manager::manager: failed to refresh available models' >&2\necho 'Ollama connection refused' >&2\nexit 1\n")
        File.chmod(0o755, File.join(bin, "codex"))
        original = ENV["PATH"]
        ENV["PATH"] = "#{bin}:#{original}"
        outcome = call
        assert_equal "failed", outcome.state
        assert outcome.error.start_with?("Ollama connection refused"), outcome.error
        assert_no_match(/codex_models_manager/, outcome.error)
      ensure
        ENV["PATH"] = original
      end
    end
  end
end
