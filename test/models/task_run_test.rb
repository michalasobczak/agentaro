require "test_helper"

# Spec 010: prompt (G2), execution per preset with stand-in programs and servers (G3, G4, S3, S5),
# states (G5), scheduling (G1, R1, Q2, S2) and recovery.
class TaskRunTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Writer", master_prompt: "You are a concise writer.", executor: @claude)
  end

  def t(str) = Time.zone.parse(str)

  def task(**attrs)
    Task.create!({ user: @user, title: "Draft the newsletter", description: "Three short points.", location: "Home office",
                   starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"), agent: @agent }.merge(attrs))
  end

  def run_for(task, trigger: "manual") = TaskRun.create!(task: task, occurrence_start: task.starts_at, trigger: trigger)

  # A stand-in for a vendor CLI on PATH, recording its arguments, input, folder and environment.
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

  RECORD = 'echo "$@" > "$LOG/args"; cat > "$LOG/stdin"; pwd > "$LOG/pwd"; env > "$LOG/env"'

  test "G2: the prompt is the master prompt, then the task in Europe/Warsaw" do
    prompt = TaskRunner.prompt_for(task, @agent, t("2026-11-20 09:00"))
    assert_equal "You are a concise writer.", prompt.system
    assert_match "Your task: Draft the newsletter", prompt.user
    assert_match "When: Friday 20 November 2026, 09:00 – 10:00 (Europe/Warsaw)", prompt.user
    assert_match "Location: Home office", prompt.user
    assert_match "Details:\nThree short points.", prompt.user
  end

  test "G3, S5: Claude gets the prompt on standard input, sandbox settings, its own folder and no secrets" do
    Dir.mktmpdir do |log|
      ENV["AGENTARO_TEST_SECRET"] = "s3cret"
      with_fake_program("claude", RECORD.gsub("$LOG", log) + "; echo 'Here is the draft.'") do
        run = TaskRunner.new(run_for(task)).perform!
        assert_equal [ "succeeded", "Here is the draft." ], [ run.state, run.output ]
        args = File.read("#{log}/args")
        assert_match "-p --output-format text --no-session-persistence --permission-mode acceptEdits --allowedTools WebSearch WebFetch --settings", args
        assert_match '"denyRead":["' + Rails.root.join("storage").realpath.to_s, args
        assert_no_match "Draft the newsletter", args, "the prompt is not in the arguments"
        assert_equal run.prompt, File.read("#{log}/stdin")
        assert_equal File.realpath(Rails.root.join("tmp/test-runs", run.id.to_s, "work")), File.realpath(File.read("#{log}/pwd").strip)
        env = File.read("#{log}/env")
        assert_no_match "s3cret", env
        assert_no_match "SECRET_KEY_BASE", env
        assert_equal [ "Writer", "Claude", "claude_code" ], [ run.agent_name, run.executor_name, run.preset ]
      end
    ensure
      ENV.delete("AGENTARO_TEST_SECRET")
    end
  end

  test "G3: Codex runs in a workspace sandbox and its last message is the answer" do
    @claude.update!(preset: "codex")
    Dir.mktmpdir do |log|
      script = RECORD.gsub("$LOG", log) + %(; prev=""; for a in "$@"; do if [ "$prev" = "-o" ]; then echo "Final answer" > "$a"; fi; prev="$a"; done; echo "progress log" >&2)
      with_fake_program("codex", script) do
        run = TaskRunner.new(run_for(task)).perform!
        assert_equal [ "succeeded", "Final answer", nil ], [ run.state, run.output, run.error ]
        assert_match(/^--search exec --skip-git-repo-check --sandbox workspace-write --ephemeral --color never -C \S+\/work -o \S+answer.txt -$/, File.read("#{log}/args").strip)
      end
    end
  end

  test "G3: Ollama CLI needs a model; the agent's model wins over the executor's default" do
    @claude.update!(preset: "ollama_cli", default_model: "llama3.2")
    Dir.mktmpdir do |log|
      with_fake_program("ollama", RECORD.gsub("$LOG", log) + "; echo answer") do
        assert_equal "succeeded", TaskRunner.new(run_for(task)).perform!.state
        assert_equal "run llama3.2", File.read("#{log}/args").strip
        @agent.update!(model: "qwen3:8b")
        TaskRunner.new(run_for(task(title: "Second"))).perform!
        assert_equal "run qwen3:8b", File.read("#{log}/args").strip
      end
    end
    @claude.update!(default_model: nil)
    @agent.update!(model: nil)
    run = TaskRunner.new(run_for(task(title: "Third"))).perform!
    assert_equal "failed", run.state
    assert_match "Choose a model", run.error
  end

  test "S3: failures, timeouts and missing programs end as states, with output kept" do
    with_fake_program("claude", "echo partial; echo 'quota exceeded' >&2; exit 2") do
      run = TaskRunner.new(run_for(task)).perform!
      assert_equal [ "failed", "partial", "quota exceeded", 2 ], [ run.state, run.output, run.error, run.exit_status ]
    end
    with_fake_program("claude", "sleep 30") do
      run = TaskRunner.new(run_for(task(title: "Slow")), timeout: 1).perform!
      assert_equal "timed_out", run.state
      assert run.finished_at
    end
  end

  test "output is limited to 200 KB" do
    with_fake_program("claude", "head -c 300000 /dev/zero | tr '\\0' 'a'") do
      run = TaskRunner.new(run_for(task)).perform!
      assert_equal "succeeded", run.state
      assert_operator run.output.bytesize, :<, 205 * 1024
      assert_match "[… cut at 200 KB]", run.output
    end
  end

  test "G1, Q3: unusable agents and unsupported tools are skipped with the reason" do
    @agent.update!(enabled: false)
    run = TaskRunner.new(run_for(task)).perform!
    assert_equal "skipped", run.state
    assert_match "not available", run.error
    @agent.update!(enabled: true)
    @claude.update!(preset: "grok_cli")
    run = TaskRunner.new(run_for(task(title: "Grok"))).perform!
    assert_equal [ "skipped", "running Grok CLI is not supported yet (spec 010, Q3)" ], [ run.state, run.error ]
  end

  # A one-shot local HTTP server returning `body`, recording the request.
  def with_http_server(body)
    server = TCPServer.new("127.0.0.1", 0)
    request = {}
    thread = Thread.new do
      client = server.accept
      request[:line] = client.gets
      length = 0
      while (line = client.gets) && line != "\r\n"
        length = line.split(":", 2)[1].to_i if line.downcase.start_with?("content-length")
      end
      request[:body] = client.read(length)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    end
    yield "http://127.0.0.1:#{server.addr[1]}", request
  ensure
    thread&.join(2)
    server&.close
  end

  test "G3: local APIs get the master prompt as the system message" do
    with_http_server({ message: { role: "assistant", content: "Ollama says hi" } }.to_json) do |url, request|
      @claude.update!(preset: "ollama_api", base_url: url, default_model: "qwen3:8b")
      run = TaskRunner.new(run_for(task)).perform!
      assert_equal [ "succeeded", "Ollama says hi" ], [ run.state, run.output ]
      assert_equal "POST /api/chat HTTP/1.1\r\n", request[:line]
      body = JSON.parse(request[:body])
      assert_equal [ "qwen3:8b", false, "system", "You are a concise writer." ], [ body["model"], body["stream"], body.dig("messages", 0, "role"), body.dig("messages", 0, "content") ]
    end
    with_http_server({ choices: [ { message: { content: "LM Studio says hi" } } ] }.to_json) do |url, request|
      @claude.update!(preset: "lm_studio_api", base_url: "#{url}/v1", default_model: "gpt-oss")
      run = TaskRunner.new(run_for(task(title: "LM"))).perform!
      assert_equal [ "succeeded", "LM Studio says hi" ], [ run.state, run.output ]
      assert_equal "POST /v1/chat/completions HTTP/1.1\r\n", request[:line]
    end
  end

  test "G1, Q2, R1: due only within 2 minutes after the start and after the agent was assigned" do
    travel_to t("2026-11-19 12:00") do
      @task = task
    end
    assert_empty Agentaro::TaskScheduler.tick(now: t("2026-11-20 08:59:59"))
    runs = Agentaro::TaskScheduler.tick(now: t("2026-11-20 09:00:30"))
    assert_equal [ [ @task.id, t("2026-11-20 09:00"), "scheduled", "queued" ] ], runs.map { |r| [ r.task_id, r.occurrence_start, r.trigger, r.state ] }
    assert_empty Agentaro::TaskScheduler.tick(now: t("2026-11-20 09:01:00")), "S2: once per occurrence"

    late = travel_to(t("2026-11-19 12:00")) { task(title: "Late", starts_at: t("2026-11-20 07:00"), ends_at: t("2026-11-20 08:00")) }
    assert_empty Agentaro::TaskScheduler.tick(now: t("2026-11-20 07:03")).select { |r| r.task_id == late.id }, "Q2: never run late"

    fresh = travel_to(t("2026-11-20 10:00:30")) { task(title: "Assigned after start", starts_at: t("2026-11-20 10:00"), ends_at: t("2026-11-20 11:00")) }
    assert_empty Agentaro::TaskScheduler.tick(now: t("2026-11-20 10:01")).select { |r| r.task_id == fresh.id }, "R1"
  end

  test "S2: every occurrence of a series runs once; a unique key stops duplicates" do
    series = travel_to(t("2026-11-19 12:00")) { task(repeat: "daily", repeat_count: 3) }
    days = %w[2026-11-20 2026-11-21 2026-11-22].map { |d| Agentaro::TaskScheduler.tick(now: t("#{d} 09:01")).size }
    assert_equal [ 1, 1, 1 ], days
    assert_equal 3, series.runs.where(trigger: "scheduled").count
    assert_raises(ActiveRecord::RecordNotUnique) { TaskRun.create!(task: series, occurrence_start: t("2026-11-20 09:00"), trigger: "scheduled") }
    assert TaskRun.create!(task: series, occurrence_start: t("2026-11-20 09:00"), trigger: "manual"), "manual runs may repeat"
  end

  test "recovery: interrupted runs fail, queued ones stay queued" do
    running = run_for(task).tap { |r| r.update!(state: "running", started_at: Time.current) }
    queued = run_for(task(title: "Waiting"))
    Agentaro::TaskScheduler.recover!
    assert_equal "failed", running.reload.state
    assert_match "Interrupted", running.error
    assert_equal "queued", queued.reload.state
  end

  test "the data changelog keeps the size of prompts and answers, not the text" do
    with_fake_program("claude", "echo 'secret plans'") do
      run = TaskRunner.new(run_for(task)).perform!
      change = DataChange.where(record_type: "TaskRun", record_id: run.id).order(:id).last
      assert_no_match "secret plans", change.changeset
      assert_match "characters]", change.changeset
    end
  end

  test "each environment has its own runs folder (incident fix)" do
    config = Rails.root.join("config/application.rb").read
    assert_match 'var/runs/#{Rails.env}', config
  end

  test "deleting a task deletes its runs; deleting the agent keeps them" do
    t1 = task
    run = run_for(t1)
    @agent.destroy!
    assert TaskRun.exists?(run.id)
    t1.destroy!
    assert_not TaskRun.exists?(run.id)
  end
end
