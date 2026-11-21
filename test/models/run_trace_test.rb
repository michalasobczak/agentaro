require "test_helper"

# Spec 030: every model call is kept as a structured trace — parts stored once, answer, tool events, numbers, links.
class RunTraceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You are a writer.\n\nBe brief.", executor: @executor)
    @space = @user.spaces.create!(name: "Home", kind: "team", description: "Home things")
    @item = @user.work_items.create!(title: "Backups", space: @space, state: "planned", started_at: 1.minute.ago, description: "Weekly")
    @step = @item.epic_steps.create!(position: 1, title: "Find tools", description: "Three options", agent: @agent, state: "queued")
  end

  def new_run = TaskRun.create!(user: @user, purpose: "epic_step", work_item: @item, epic_step: @step, agent: @agent, trigger: "manual", occurrence_start: Time.current)

  def record(run, prompt, outcome: AgentCall::Outcome.new("succeeded", "Done.", nil, 0), **options)
    RunTrace.record(run: run, agent: @agent, prompt: prompt, outcome: outcome, pass: nil, started_at: Time.current, duration: 1.25,
                    model: "sonnet", effort: "high", **options)
  end

  def with_fake_claude(script)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\n#{script}\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def json_lines(*events) = events.map { |e| "echo '#{e.to_json.gsub("'", "'\\\\''")}'" }.join("\n")

  test "G1, S2, R1: the prompt is rebuilt exactly from its parts, for step, task, director and plain prompts" do
    task = @user.tasks.create!(title: "Newsletter", starts_at: Time.current, ends_at: 1.hour.from_now, agent: @agent, description: "Three points")
    prompts = [
      StepChain.prompt_for(@step, @agent),
      TaskRunner.prompt_for(task, @agent, task.starts_at),
      AgentCall::Prompt.new(system: "Director.", sections: [ [ "context", "Mode: chat" ], [ "instructions", "A\n\n\nB\n\n" ], [ "rejection", "" ] ]),
      AgentCall::Prompt.new("Check.", "Reply ok")
    ]
    prompts.each do |prompt|
      call = record(new_run, prompt)
      assert_equal prompt.text, call.prompt_text
      assert_equal "master_prompt", call.parts.first.kind
    end
    assert_equal %w[master_prompt task epic instructions], ModelCall.first.parts.map(&:kind).uniq
  end

  test "G1, S3: repeated text is stored once and shared" do
    prompt = StepChain.prompt_for(@step, @agent)
    record(new_run, prompt)
    parts = TracePart.count
    second = record(new_run, prompt)
    assert_equal parts, TracePart.count, "no new parts for the same prompt and answer"
    assert_equal prompt.text, second.prompt_text
  end

  test "G3, G4: numbers and links are kept on the call; a second call of the run is the next position" do
    run = new_run
    call = record(run, StepChain.prompt_for(@step, @agent), usage: { input_tokens: 1200, output_tokens: 300, cost_usd: 0.0123, turns: 3 })
    assert_equal [ @user.id, 1, "epic_step", "Pisarz", "claude_code", "sonnet", "high", "succeeded", 1250, 1200, 300, 0.0123, 3 ],
                 call.values_at(:user_id, :position, :pass, :agent_name, :preset, :model, :effort, :state, :duration_ms, :input_tokens, :output_tokens, :cost_usd, :turns)
    assert_equal "Done.", call.answer
    assert_equal [ @item, @step ], [ call.task_run.work_item, call.task_run.epic_step ]
    assert_equal [ 1, 2 ], [ call, record(run, AgentCall::Prompt.new("s", "u"), pass: "proposal") ].map(&:position)
    assert_equal "proposal", run.model_calls.last.pass
  end

  test "R2: secrets in prompts, answers and events are replaced before they are stored" do
    key = "sk-ant-api03-#{"a" * 40}"
    prompt = AgentCall::Prompt.new(system: "Agent", sections: [ [ "task", "Use #{key} and password: hunter2hunter2 now" ] ])
    call = record(new_run, prompt, outcome: AgentCall::Outcome.new("succeeded", "token=ghp_#{"b" * 36}", nil, 0),
                  events: [ { "kind" => "tool_result", "content" => "Authorization: Bearer #{"c" * 40}" } ])
    stored = TracePart.pluck(:content).join + call.events
    [ key, "hunter2hunter2", "b" * 36, "c" * 40 ].each { |secret| assert_not_includes stored, secret }
    assert_includes call.prompt_text, "password: [secret removed]"
    assert call.redacted
    assert_equal "Use [secret removed] and", RunTrace.redact("Use #{key} and").first
    assert_equal [ "an ordinary sentence about tokens and passwords", false ], RunTrace.redact("an ordinary sentence about tokens and passwords")
  end

  test "G2, R3: Claude Code's stream gives tool events with their source, usage and cost; payloads are cut at 8 KB" do
    stream = ClaudeStream.new
    lines = [
      { type: "system", subtype: "init" },
      { type: "assistant", message: { content: [ { type: "text", text: "Searching." }, { type: "tool_use", id: "t1", name: "WebFetch", input: { url: "https://example.com" } } ] } },
      { type: "user", message: { content: [ { type: "tool_result", tool_use_id: "t1", content: [ { type: "text", text: "x" * 20_000 } ] } ] } },
      { type: "assistant", message: { content: [ { type: "tool_use", id: "t2", name: "Bash", input: { command: "ls" } } ] } },
      { type: "user", message: { content: [ { type: "tool_result", tool_use_id: "t2", content: "a.txt", is_error: true } ] } },
      { type: "result", result: "Final answer", total_cost_usd: 0.05, num_turns: 2,
        usage: { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 30, cache_creation_input_tokens: 40 } }
    ]
    lines.map { |l| l.to_json + "\n" }.join.scan(/.{1,100}/m).each { |chunk| stream.feed(chunk) }
    assert_equal "Final answer", stream.answer("")
    assert_equal({ input_tokens: 10, output_tokens: 20, cache_read_tokens: 30, cache_write_tokens: 40, cost_usd: 0.05, turns: 2 }, stream.usage)
    assert_equal [ %w[text], %w[tool_use WebFetch], %w[tool_result WebFetch web], %w[tool_use Bash], %w[tool_result Bash command] ],
                 stream.events.map { |e| e.values_at("kind", "name", "source").compact }
    assert_operator stream.events[2]["content"].bytesize, :<, 8 * 1024 + 50
    assert stream.events[4]["error"]
    assert_equal [ "-p", "--output-format", "stream-json", "--verbose", "--x" ], stream.arguments([ "-p", "--output-format", "text", "--x" ]), "no partial messages when nobody reads them"
  end

  test "G2, S1: a Claude Code step streams; its trace has the events, tokens and cost, and the answer is the result line" do
    script = json_lines({ type: "assistant", message: { content: [ { type: "tool_use", id: "t1", name: "Read", input: { file_path: "a" } } ] } },
                        { type: "user", message: { content: [ { type: "tool_result", tool_use_id: "t1", content: "file text" } ] } },
                        { type: "result", result: "Three tools found.", total_cost_usd: 0.02, num_turns: 2, usage: { input_tokens: 500, output_tokens: 80 } })
    with_fake_claude(script) do
      run = StepChain.new(new_run).perform!
      assert_equal [ "succeeded", "Three tools found." ], [ run.state, run.output ]
      call = run.model_calls.sole
      assert_equal [ 500, 80, 0.02, 2, 2 ], call.values_at(:input_tokens, :output_tokens, :cost_usd, :turns, :events_count)
      assert_equal [ [ "tool_use", "Read" ], [ "tool_result", "Read" ] ], call.event_list.map { |e| e.values_at("kind", "name") }
      assert_equal "file", call.event_list.last["source"]
      assert_equal run.prompt, call.prompt_text
      assert_equal "Three tools found.", call.answer
    end
  end

  test "the result line is found also after tool results larger than the output limit" do
    big = { type: "user", message: { content: [ { type: "tool_result", tool_use_id: "t1", content: "y" * 900_000 } ] } }.to_json
    File.write(path = File.join(Dir.tmpdir, "agentaro-big-#{SecureRandom.hex(4)}.json"), big + "\n")
    script = "cat '#{path}'\n" + json_lines({ type: "result", result: "Short answer.", usage: { input_tokens: 1, output_tokens: 1 } })
    with_fake_claude(script) do
      run = StepChain.new(new_run).perform!
      assert_equal [ "succeeded", "Short answer." ], [ run.state, run.output ]
    end
  ensure
    FileUtils.rm_f(path) if path
  end

  test "a plain-text answer (no stream events) still works and is traced" do
    with_fake_claude("echo 'Plain answer'") do
      run = StepChain.new(new_run).perform!
      assert_equal [ "succeeded", "Plain answer" ], [ run.state, run.output ]
      assert_equal 0, run.model_calls.sole.events_count
    end
  end

  test "G1: the director's reply and its proposal pass are two calls of the chat run, each with its own prompt" do
    director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @user.team_roles.create!(agent: director, role: "director")
    @user.chat_messages.create!(author: "user", content: "Add an epic Taxes to Home, please.")
    answer = { reply: "Added Taxes.", actions: [ { type: "add_item", space: @space.id, title: "Taxes" } ] }
    with_fake_claude("echo '#{answer.to_json}'") do
      run = ManagementRunner.chat!(@user)
      ManagementRunner.new(run.reload).perform!
      calls = run.reload.model_calls.to_a
      assert_equal [ [ 1, "chat" ], [ 2, "proposal" ] ], calls.map { |c| [ c.position, c.pass ] }
      assert_equal %w[master_prompt context instructions], calls.first.parts.map(&:kind).uniq
      assert_not_equal calls.first.prompt_text, calls.last.prompt_text
      assert_equal run.prompt, calls.last.prompt_text, "the run keeps the last prompt sent, as before"
    end
  end

  test "a retry after a rejected answer keeps the rejection in the prompt and in the trace" do
    prompt = AgentCall::Prompt.new(system: "S", sections: [ [ "context", "C" ], [ "instructions", "I" ] ])
    retried = prompt.with(sections: [ *prompt.sections, [ "rejection", "Your previous answer was not accepted: x" ] ])
    assert_equal "S\n\n---\n\nC\n\nI\n\nYour previous answer was not accepted: x", retried.text
    assert_raises(ArgumentError) { prompt.with(user: "changed") }
    assert_equal retried.text, record(new_run, retried).prompt_text
  end

  test "R7: a failure to record never breaks the run" do
    with_fake_claude("echo 'Fine'") do
      ModelCall.define_singleton_method(:create!) { |*, **| raise ActiveRecord::StatementInvalid, "disk full" }
      begin
        run = StepChain.new(new_run).perform!
        assert_equal [ "succeeded", "Fine" ], [ run.state, run.output ]
      ensure
        ModelCall.singleton_class.remove_method(:create!)
      end
    end
    assert_equal 0, ModelCall.count
  end

  test "G6: events older than 90 days are compressed and read the same; parts nothing uses are deleted" do
    events = [ { "kind" => "text", "text" => "hello" } ]
    call = record(new_run, AgentCall::Prompt.new("s", "u"), events: events)
    call.update!(created_at: 91.days.ago)
    fresh = record(new_run, AgentCall::Prompt.new("s", "v"), events: events)
    assert_equal 1, RunTrace.compress_old!
    assert_equal [ "zlib", "json" ], [ call.reload, fresh.reload ].map(&:events_format)
    assert_equal events, call.event_list

    used = TracePart.count
    fresh.task_run.destroy!
    assert_equal 1, TracePart.prune_orphans!, "only the part no other call shares (\"v\")"
    assert_equal used - 1, TracePart.count
  end

  test "runs from before traces get one legacy part that gives back their prompt; traces stay out of the data changelog" do
    run = new_run
    run.update!(prompt: "Old\n\n---\n\nprompt with password: hunter2hunter2", output: "Old answer", state: "succeeded")
    changes = DataChange.count
    assert_equal 1, RunTrace.backfill_legacy!
    assert_equal 0, RunTrace.backfill_legacy!, "only once"
    call = run.model_calls.sole
    assert_equal [ "legacy", true, "Old answer" ], [ call.layout, call.redacted, call.answer ]
    assert_equal "Old\n\n---\n\nprompt with password: [secret removed]", call.prompt_text
    assert_equal changes, DataChange.count
  end

  test "a model check (spec 022) leaves no trace" do
    with_fake_claude("echo ok") { assert ModelCheck.new(@executor, model: "sonnet", effort: nil).run.ok }
    assert_equal 0, ModelCall.count
  end
end
