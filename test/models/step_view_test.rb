require "test_helper"

# Spec 038: the live log of a running step (LiveLog), Codex's event stream (G6), Ollama's text (G7) and what the view
# shows for each state of a step (StepView, G2, G3, R2–R5).
class StepViewTest < ActiveSupport::TestCase
  # Codex 0.170.0 printed these for "cat a.txt, then create b.txt" (spec 038, G6).
  CODEX_LINES = [
    { type: "thread.started", thread_id: "t" },
    { type: "turn.started" },
    { type: "item.completed", item: { id: "item_0", type: "agent_message", text: "I'll read a.txt and then write b.txt." } },
    { type: "item.started", item: { id: "item_1", type: "command_execution", command: "/bin/zsh -lc 'cat a.txt'", aggregated_output: "", exit_code: nil, status: "in_progress" } },
    { type: "item.completed", item: { id: "item_1", type: "command_execution", command: "/bin/zsh -lc 'cat a.txt'", aggregated_output: "hello\n", exit_code: 0, status: "completed" } },
    { type: "item.completed", item: { id: "item_2", type: "file_change", changes: [ { path: "b.txt", kind: "add" } ], status: "completed" } },
    { type: "item.completed", item: { id: "item_3", type: "agent_message", text: "done" } },
    { type: "turn.completed", usage: { input_tokens: 58031, cached_input_tokens: 45696, output_tokens: 100 } }
  ].freeze

  setup do
    @user = create_user
    @user.update!(auto_retry: false)
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @item = @user.work_items.create!(title: "MVP", space: @space, state: "planned", started_at: 1.minute.ago)
    @step = @item.epic_steps.create!(position: 1, title: "Build", agent: @agent, state: "queued")
    @later = @item.epic_steps.create!(position: 2, title: "Check", agent: @agent)
    @runs = []
  end

  teardown { @runs.each { |run| FileUtils.rm_rf(LiveLog.dir_for(run.id)) } }

  def new_run(step = @step)
    TaskRun.create!(user: @user, purpose: "epic_step", work_item: @item, epic_step: step, agent: step.agent, trigger: "manual",
                    occurrence_start: Time.current).tap { |run| @runs << run }
  end

  def with_program(name, script)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, name), "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, File.join(bin, name))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def echo_lines(events) = events.map { |e| "echo '#{e.to_json.gsub("'", "'\\\\''")}'" }.join("\n")

  # --- G6: Codex ----------------------------------------------------------------------------------------------------

  test "G6: Codex's events become the trace's events — commands with output, file changes, messages — and its tokens" do
    stream = CodexStream.new
    assert_equal [ "--search", "exec", "--json", "-C", "x", "-" ], stream.arguments([ "--search", "exec", "-C", "x", "-" ])
    CODEX_LINES.each { |line| stream.feed(line.to_json + "\n") }
    assert_equal [ %w[text], %w[tool_use Bash], %w[tool_result Bash], %w[tool_use Edit], %w[tool_result Edit], %w[text] ],
                 stream.events.map { |e| e.values_at("kind", "name").compact }
    assert_equal "hello\n", stream.events[2]["content"]
    assert_equal false, stream.events[2]["error"]
    assert_match "add b.txt", stream.events[3]["input"]
    assert_equal({ input_tokens: 58031, output_tokens: 100, cache_read_tokens: 45696 }, stream.usage)
    assert_equal "done", stream.answer("")
  end

  test "G6, S4: a Codex step runs with --json; its trace lists its commands and tokens, the answer is its last message, the live log goes" do
    @agent.update!(executor: Executor.create!(name: "Codex", preset: "codex"))
    script = <<~SH
      for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
      case " $* " in *" --json "*) ;; *) echo "no --json" >&2; exit 2;; esac
      cat > /dev/null
      #{echo_lines(CODEX_LINES)}
      printf 'Final answer' > "$out"
    SH
    with_program("codex", script) do
      run = StepChain.new(new_run).perform!
      assert_equal [ "succeeded", "Final answer" ], [ run.state, run.output ]
      call = run.model_calls.sole
      assert_equal [ 58031, 100 ], call.values_at(:input_tokens, :output_tokens)
      assert_includes call.event_list.map { |e| e["input"] }, { command: "/bin/zsh -lc 'cat a.txt'" }.to_json
      assert_nil LiveLog.read(LiveLog.dir_for(run.id)), "the trace is the record now"
    end
  end

  # --- G2, R5: the live log while it runs -------------------------------------------------------------------------

  test "G2, R5: while a Claude Code step runs its actions are readable from the live log, secrets replaced" do
    snapshot = File.join(Dir.mktmpdir, "live.jsonl")
    events = [ { type: "assistant", message: { content: [ { type: "text", text: "Sprawdzam testy." }, { type: "tool_use", id: "t1", name: "Bash", input: { command: "npm test" } } ] } },
               { type: "user", message: { content: [ { type: "tool_result", tool_use_id: "t1", content: "ok token=sk-ant-abcdefghijklmnopqrstuvwxyz123" } ] } } ]
    script = "cat > /dev/null\n#{echo_lines(events)}\nsleep 0.5\ncp ../live.jsonl #{snapshot}\n" +
             echo_lines([ { type: "result", result: "Gotowe." } ])
    with_program("claude", script) do
      run = StepChain.new(new_run).perform!
      assert_equal "succeeded", run.state
      lines = File.readlines(snapshot).map { |l| JSON.parse(l) }
      assert_equal [ %w[text], %w[tool_use Bash], %w[tool_result Bash] ], lines.map { |e| e.values_at("kind", "name").compact }
      assert_no_match "sk-ant-", lines.last["content"]
      assert_match RunTrace::REDACTED, lines.last["content"]

      view = StepView.new(@step.reload).to_h # finished: the same log from the trace (R4) and the answer
      assert_equal [ [ "text", nil, "Sprawdzam testy." ], [ "action", "Bash", "npm test" ] ], view[:entries].map { |e| e.values_at(:kind, :label, :text) },
                   "R2 (owner change): no tool result in the view"
      assert_equal [ "Gotowe.", "log", false ], view.values_at(:answer, :stream, :running)
    end
  end

  test "G7: an Ollama step's text is readable while it is written" do
    @agent.update!(executor: Executor.create!(name: "Ollama", preset: "ollama_cli", default_model: "llama3"))
    snapshot = File.join(Dir.mktmpdir, "live.txt")
    with_program("ollama", "cat > /dev/null\nprintf 'Pierwsze zdanie. '\nsleep 0.7\ncp ../live.txt #{snapshot}\nprintf 'Drugie.'") do
      run = StepChain.new(new_run).perform!
      assert_equal "succeeded", run.state
      assert_equal "Pierwsze zdanie. ", File.read(snapshot)
      assert_nil LiveLog.read(LiveLog.dir_for(run.id))
    end
    assert_equal "text", StepView.new(@step.reload).to_h[:stream]
  end

  # --- G3, R2, R3: the view of each state ----------------------------------------------------------------------------

  test "R2, R3: a running step's view comes from its live log — texts cut to 300 characters, actions one line of 80 without results, the latest 200, earlier ones counted" do
    run = new_run
    run.update!(state: "running", started_at: 90.seconds.ago)
    log = LiveLog.new(LiveLog.dir_for(run.id).tap { |d| FileUtils.mkdir_p(d) })
    log.add("kind" => "tool_use", "id" => "t1", "name" => "Read", "input" => { file_path: "src/world.js" }.to_json)
    log.add("kind" => "tool_result", "id" => "t1", "name" => "Read", "source" => "file", "content" => "secret file contents")
    205.times { |i| log.add("kind" => "text", "text" => "krok #{i}") }
    view = StepView.new(@step).to_h
    assert_equal [ true, 200, 6 ], view.values_at(:running, :entries, :earlier).then { |r, e, n| [ r, e.size, n ] }
    assert_equal "krok 204", view[:entries].last[:text]
    assert_in_delta 90, view[:run][:elapsed], 2

    log.clear!
    log.add("kind" => "text", "text" => "x" * 1000)
    log.add("kind" => "tool_use", "id" => "t2", "name" => "Bash", "input" => { command: "npm test\n#{"y" * 200}" }.to_json)
    log.add("kind" => "tool_result", "id" => "t2", "name" => "Bash", "error" => true, "content" => "boom: stack trace")
    text, action = StepView.new(@step).to_h[:entries]
    assert_equal 301, text[:text].length, "300 characters and the mark"
    assert_equal [ "action", "Bash", 81, true ], [ action[:kind], action[:label], action[:text].length, action[:error] ]
    assert_no_match "\n", action[:text]
    assert_no_match "boom", StepView.new(@step).to_h.to_json, "results are never shown, also not a failed one"
  end

  test "G3: a failed step shows its error; an interrupted one keeps its log; a waiting one its question; a pending one what it waits for" do
    run = new_run
    run.update!(state: "failed", started_at: 5.minutes.ago, finished_at: 1.minute.ago, error: "Interrupted: Agentaro was restarted.")
    LiveLog.new(LiveLog.dir_for(run.id).tap { |d| FileUtils.mkdir_p(d) }).add("kind" => "text", "text" => "Buduję wyspę.")
    view = StepView.new(@step.reload).to_h
    assert_equal [ "Interrupted: Agentaro was restarted.", true, "Buduję wyspę." ], [ view[:error], view[:run][:interrupted], view[:entries].sole[:text] ]

    assert_equal "step 1 “Build”", StepView.new(@later).to_h[:waits]
    @step.update!(state: "waiting")
    @item.step_decisions.create!(epic_step: @step, question: "Sterowanie myszą czy klawiaturą?", options: %w[mysz klawiatura], recommended: "klawiatura")
    assert_equal "Sterowanie myszą czy klawiaturą?", StepView.new(@step).to_h[:question]

    other = @user.work_items.create!(title: "Mapa", space: @space, state: "planned")
    later_step = other.epic_steps.create!(position: 1, title: "Map", agent: @agent)
    assert_equal "“MVP” in this space (one epic at a time)", StepView.new(later_step).to_h[:waits]
  end

  test "B20: a link planted in the run's folder is neither written through nor read" do
    dir = LiveLog.dir_for(new_run.id).tap { |d| FileUtils.mkdir_p(d) }
    target = File.join(Dir.mktmpdir, "elsewhere.txt")
    File.write(target, "keep me\n")
    File.symlink(target, dir.join(LiveLog::EVENTS))
    File.symlink(target, dir.join(LiveLog::TEXT))
    File.symlink(target, dir.join("#{LiveLog::TEXT}.tmp"))
    log = LiveLog.new(dir)
    log.add("kind" => "text", "text" => "injected")
    log.text("injected", force: true)
    assert_equal "keep me\n", File.read(target)
    assert_nil LiveLog.read(dir.tap { FileUtils.rm_f(dir.join(LiveLog::TEXT)) }), "a link is not read"
  end

  test "G1, G4: an epic shows its running step, else its latest started one, else its first" do
    assert_equal @step, StepView.step_for(@item)
    @step.update!(state: "succeeded")
    assert_equal @step, StepView.step_for(@item)
    @later.update!(state: "running")
    assert_equal @later, StepView.step_for(@item)
    fresh = @user.work_items.create!(title: "Nowy", space: @space, state: "planned")
    first = fresh.epic_steps.create!(position: 1, title: "A", agent: @agent)
    assert_equal first, StepView.step_for(fresh)
  end
end
