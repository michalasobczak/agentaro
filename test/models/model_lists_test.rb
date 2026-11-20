require "test_helper"

# Spec 022: model name rule (R1), effort (G5), model lists (G1, G3, R5) and Check model (G4, R3).
class ModelListsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @codex = Executor.create!(name: "Codex", preset: "codex")
  end

  def with_fake_program(name, script)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, name), "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, File.join(dir, name))
      original = ENV["PATH"]
      ENV["PATH"] = "#{dir}:#{original}"
      yield dir
    ensure
      ENV["PATH"] = original
    end
  end

  def chat_run = TaskRun.create!(purpose: "chat", trigger: "manual", user: @user, occurrence_start: Time.current)

  def agent(**attrs) = Agent.new({ user: @user, name: "Helper", master_prompt: "You help.", executor: @claude }.merge(attrs))

  test "R1: real model names pass; names that look like options or hold odd characters are refused" do
    %w[sonnet opus claude-sonnet-4-5 gpt-6.1-terra qwen3:8b nomic-ai/nomic-embed-text-v1.5 llama3.2@q4].each do |name|
      assert agent(model: name).valid?, name
      assert Executor.new(name: "X #{name}", preset: "ollama_cli", default_model: name).valid?, name
    end
    [ "-x", "--dangerously-skip-permissions", "two words", "a;b", "a\nb", "x" * 201, "ok$(id)" ].each do |name|
      assert_not agent(model: name).valid?, name.inspect
      assert_not Executor.new(name: "Y", preset: "ollama_cli", default_model: name).valid?, name.inspect
    end
    assert_includes agent(model: "-x").tap(&:validate).errors[:model], Executor::MODEL_NAME_RULE
  end

  test "R1: extra names follow the same rule, one per line, at most 50" do
    @claude.update!(extra_models: " claude-opus-4-1 \n\nclaude-opus-4-1\nclaude-haiku-4-5 ")
    assert_equal "claude-opus-4-1\nclaude-haiku-4-5", @claude.extra_models
    @claude.extra_models = "good\n-bad"
    assert_not @claude.valid?
    @claude.extra_models = (1..51).map { |i| "m#{i}" }.join("\n")
    assert_not @claude.valid?
  end

  test "R1: a name saved before the rule never reaches the tool" do
    a = agent(model: "ok").tap(&:save!)
    a.model = "--settings=evil"
    a.save!(validate: false)
    run = chat_run
    with_fake_program("claude", "echo should-not-run") do
      outcome = AgentCall.new(run, a.reload, AgentCall::Prompt.new("s", "u")).call
      assert_equal "failed", outcome.state
      assert_match "must not start with -", outcome.error
    end
  end

  test "G5: effort only from the tool's own list; others take none" do
    assert agent(effort: "high").valid?
    assert_not agent(effort: "ultra").valid?, "Claude Code has no ultra"
    assert agent(executor: @codex, effort: "ultra").valid?
    ollama = Executor.create!(name: "Ollama", preset: "ollama_cli")
    assert_not agent(executor: ollama, effort: "high").valid?
    assert_not Executor.new(name: "Z", preset: "claude_code", effort: "--x").valid?
  end

  test "G5: the agent's effort, else the executor's; never one the tool does not take" do
    @claude.update!(effort: "medium")
    assert_equal "medium", agent.effective_effort
    assert_equal "max", agent(effort: "max").effective_effort
    a = agent(effort: "ultra", executor: @codex).tap(&:save!)
    a.executor = @claude # e.g. the executor changed later
    assert_nil a.effective_effort
    assert_equal "Claude · sonnet · effort high", agent(model: "sonnet", effort: "high").runtime_label
  end

  test "G5: Claude Code gets --effort, Codex gets model_reasoning_effort" do
    run = chat_run
    Dir.mktmpdir do |log|
      with_fake_program("claude", %(echo "$@" > #{log}/args; cat > /dev/null; echo ok)) do
        AgentCall.new(run, agent(model: "sonnet", effort: "high").tap(&:save!), AgentCall::Prompt.new("s", "u")).call
        assert_match(/--model sonnet --effort high$/, File.read("#{log}/args").strip)
      end
      codex_agent = agent(name: "Coder", executor: @codex, model: "gpt-6.1-terra", effort: "xhigh").tap(&:save!)
      with_fake_program("codex", %(echo "$@" > #{log}/args; cat > /dev/null)) do
        AgentCall.new(chat_run, codex_agent, AgentCall::Prompt.new("s", "u")).call
        assert_match(/-m gpt-6\.1-terra -c model_reasoning_effort=xhigh -$/, File.read("#{log}/args").strip)
      end
    end
  end

  test "G1: Codex models come from its cache, without hidden ones, with their effort levels" do
    Dir.mktmpdir do |home|
      File.write(File.join(home, "models_cache.json"), {
        models: [
          { slug: "gpt-6.1-terra", visibility: "list", supported_reasoning_levels: [ { effort: "low" }, { effort: "high" }, { effort: "turbo" } ] },
          { slug: "codex-auto-review", visibility: "hide" },
          { slug: "-oops", visibility: "list" }
        ]
      }.to_json)
      result = ModelList.new(@codex, codex_home: home).run
      assert result.ok
      assert_equal [ { "name" => "gpt-6.1-terra", "efforts" => %w[low high] } ], result.models, "hidden, odd names and unknown levels left out"

      File.write(File.join(home, "models_cache.json"), "{ not json")
      assert_not ModelList.new(@codex, codex_home: home).run.ok
    end
    result = ModelList.new(@codex, codex_home: "/nonexistent-#{SecureRandom.hex(4)}").run
    assert_not result.ok
    assert_match "run codex once", result.note
  end

  test "G1: Ollama and LM Studio lists come from their CLIs with fixed arguments" do
    ollama = Executor.create!(name: "Ollama", preset: "ollama_cli")
    with_fake_program("ollama", %(echo "NAME ID SIZE MODIFIED"; echo "qwen3:8b abc 5GB now"; echo "args=$*" >&2)) do
      assert_equal [ "qwen3:8b" ], ModelList.new(ollama).run.models.map { |m| m["name"] }
    end
    lms = Executor.create!(name: "LM Studio", preset: "lm_studio_cli")
    with_fake_program("lms", %([ "$*" = "ls --llm --json" ] && echo '[{"modelKey":"qwen/qwen3-8b"},{"modelKey":"--bad"}]')) do
      assert_equal [ "qwen/qwen3-8b" ], ModelList.new(lms).run.models.map { |m| m["name"] }
    end
    with_fake_program("lms", "echo broken >&2; exit 2") do
      assert_not ModelList.new(lms).run.ok
    end
  end

  test "G2, Q3: Claude offers its aliases and the admin's names; other lists add the tool's names" do
    @claude.update!(extra_models: "claude-opus-4-1\nsonnet")
    assert_equal %w[opus sonnet haiku claude-opus-4-1], @claude.model_choices.map { |m| m["name"] }
    @codex.update!(models: [ { "name" => "gpt-6.1-terra", "efforts" => [ "high" ] } ], extra_models: "gpt-custom")
    assert_equal [ { "name" => "gpt-6.1-terra", "efforts" => [ "high" ] }, { "name" => "gpt-custom", "efforts" => [] } ], @codex.model_choices
  end

  test "G3, R5: a refresh replaces the list; a failure keeps the old list with a note" do
    ollama = Executor.create!(name: "Ollama", preset: "ollama_cli")
    with_fake_program("ollama", %(echo "NAME ID"; echo "llama3.2 x")) { ollama.refresh_models! }
    assert_equal [ "llama3.2" ], ollama.reload.models.map { |m| m["name"] }
    assert ollama.models_listed_at
    with_fake_program("ollama", "exit 1") { ollama.refresh_models! }
    assert_equal [ "llama3.2" ], ollama.reload.models.map { |m| m["name"] }
    assert_match "Out of date", ollama.models_note
  end

  test "G4, R3: Check model asks once like a step, reports the time, and leaves no folder behind" do
    runs = Dir.mktmpdir
    Dir.mktmpdir do |log|
      with_fake_program("claude", %(echo "$@" > #{log}/args; pwd > #{log}/pwd; cat > #{log}/stdin; echo ok)) do
        result = ModelCheck.new(@claude, model: "sonnet", effort: "low", runs_dir: runs).run
        assert result.ok
        assert_match(/\Asonnet, effort low: answered in [\d.]+ s — ok\z/, result.output)
        assert_match "--model sonnet --effort low", File.read("#{log}/args")
        assert_match "Reply with the single word: ok", File.read("#{log}/stdin")
        assert_match %r{/check-\h+/work\z}, File.read("#{log}/pwd").strip
        assert_empty Dir.children(runs), "the check's folder is removed"
      end
      with_fake_program("claude", %(cat > /dev/null; echo "model not found: nope" >&2; exit 1)) do
        result = ModelCheck.new(@claude, model: "nope", effort: nil, runs_dir: runs).run
        assert_not result.ok
        assert_match "model not found: nope", result.output
      end
    end
    assert_not ModelCheck.new(@claude, model: "-x", effort: nil, runs_dir: runs).run.ok
    assert_match "Choose a model", ModelCheck.new(Executor.create!(name: "O", preset: "ollama_cli"), model: nil, effort: nil, runs_dir: runs).run.output
    assert_equal 0, TaskRun.count, "a check is not a task run"
  ensure
    FileUtils.rm_rf(runs)
  end
end
