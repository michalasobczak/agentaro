require "test_helper"

# Spec 032: what is left of it after spec 040 — the kinds of failure (G1), usage-limit reset times (G2), waiting
# retries (R2) and the retried step's prompt (G3, R3). When to retry is the director's decision now (step_review_test.rb).
class StepRetryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @item = @user.work_items.create!(title: "Backups", state: "planned")
    @item.epic_steps.create!(position: 1, title: "Research", agent: @writer)
    @item.epic_steps.create!(position: 2, title: "Write", agent: @writer)
    @state = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@state) }

  # A stand-in "claude": for the task named fail_task it fails `times` times with `message` on stderr (or stdout),
  # then answers. Every prompt is kept.
  def with_agent(fail_task: "Research", times: 0, message: "broken", stream: 2)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
        n=$(cat "#{@state}/count-$task" 2>/dev/null || echo 0)
        n=$((n + 1)); echo $n > "#{@state}/count-$task"
        printf '%s' "$input" > "#{@state}/prompt-$task-$n"
        if [ "$task" = "#{fail_task}" ] && [ $n -le #{times} ]; then echo '#{message}' >&#{stream}; exit 1; fi
        echo "Answer for $task"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  # What the workers would do: runs whose time has come, as the scheduler hands them over.
  def run_due(limit = 10)
    limit.times do
      StepRetry.hand_over_due
      run = TaskRun.where(state: "queued", purpose: "epic_step", retry_at: nil).order(:id).first or break
      StepChain.new(run).perform!
    end
  end

  def runs = TaskRun.where(purpose: "epic_step").order(:id)
  def prompt(task, n) = File.read(File.join(@state, "prompt-#{task}-#{n}"))

  # --- G1: kinds ------------------------------------------------------------------------------------------------

  def kind(state: "failed", error: nil, output: nil) = StepRetry.classify(TaskRun.new(state: state, error: error, output: output))

  test "G1: kinds from real messages of the tools and of Agentaro" do
    assert_equal "timeout", kind(state: "timed_out", error: "Stopped after 30 minutes.")
    assert_equal "usage_limit", kind(output: "Claude AI usage limit reached|1763730000")
    assert_equal "usage_limit", kind(output: "5-hour limit reached ∙ resets 3pm", error: "claude ended: exit 1.")
    assert_equal "usage_limit", kind(error: "You've hit your usage limit. Try again in 2 hours 13 minutes.\n\ncodex ended: exit 1.")
    assert_equal "usage_limit", kind(error: "Answered 429 Too Many Requests.")
    assert_equal "transient", kind(error: "Could not connect: Connection refused - connect(2) for 127.0.0.1:11434")
    assert_equal "transient", kind(error: "API Error: 529 {\"type\":\"overloaded_error\"}")
    assert_equal "transient", kind(error: "Interrupted: Agentaro stopped while this run was in progress.")
    assert_equal "transient", kind(error: nil, output: nil)
    assert_equal "lasting", kind(state: "skipped", error: "The step has no agent (it was deleted).")
    assert_equal "lasting", kind(state: "skipped", error: "Pisarz is not available (disabled agent or executor).")
    assert_equal "lasting", kind(error: "claude was not found on this computer.")
    assert_equal "lasting", kind(error: "Working folder not found: /tmp/gone")
    assert_equal "lasting", kind(error: "Invalid API key · Please run /login\n\nclaude ended: exit 1.")
    assert_equal "stopped", kind(state: "skipped", error: "The epic was cancelled before this step started.")
    assert_equal "unknown", kind(error: "broken\n\nclaude ended: exit 1.")
    assert_equal "unknown", kind(error: "claude ended: exit 1.", output: "I wrote 500 words about backups"), "numbers in the answer are not HTTP codes"
  end

  test "G2: reset times are read from the message" do
    travel_to Time.zone.local(2026, 11, 21, 10, 0) do
      assert_equal Time.zone.local(2026, 11, 21, 15, 0), StepRetry.reset_time("limit reached ∙ resets 3pm")
      assert_equal Time.zone.local(2026, 11, 21, 15, 5), StepRetry.reset_time("try again at 3:05 PM")
      assert_equal Time.zone.local(2026, 11, 22, 9, 30), StepRetry.reset_time("resets at 9:30"), "a passed hour is tomorrow"
      assert_equal 2.hours + 13.minutes, StepRetry.reset_time("Try again in 2 hours 13 minutes.") - Time.current
      assert_equal Time.zone.at(1_763_730_000), StepRetry.reset_time("Claude AI usage limit reached|1763730000")
      assert_nil StepRetry.reset_time("usage limit reached")
      assert_nil StepRetry.reset_time("resets at 31:99")

    end
  end

  # A retry as the director's decision (spec 040) creates it: the same step, the next attempt, maybe at a later time.
  def fail_once_and_retry(message, retry_at: nil)
    with_agent(times: 1, message: message) do
      StepChain.start(@item)
      run_due
    end
    step = @item.epic_steps.first
    failed = runs.last
    step.update!(state: "queued")
    @item.reload.update!(state: "planned", blocked_reason: nil)
    TaskRun.create!(user: @user, work_item: @item, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "retry",
                    occurrence_start: Time.current, state: "queued", attempt: failed.attempt + 1, retry_at: retry_at)
  end

  test "R2: a waiting retry is not started early by a worker after a restart, and is handed over once when due" do
    waiting = fail_once_and_retry("API Error: Connection error", retry_at: 2.minutes.from_now)
    handed = []
    original = Agentaro::TaskScheduler.method(:enqueue)
    Agentaro::TaskScheduler.define_singleton_method(:enqueue) { |id| handed << id }
    StepRetry.hand_over_due
    assert_empty handed, "not due yet"
    travel 3.minutes do
      StepRetry.hand_over_due
      StepRetry.hand_over_due
    end
    assert_equal [ waiting.id ], handed
    assert_nil waiting.reload.retry_at
  ensure
    Agentaro::TaskScheduler.define_singleton_method(:enqueue, original) if original
  end

  test "R3: the previous error in the prompt is data with secrets removed; folder spaces get the check-the-state note" do
    space = @item.space
    space.update!(working_dir: Dir.mktmpdir) # the item's own space: moving the item would start a new plan
    fail_once_and_retry("Connection error with key sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
    with_agent(times: 1) { run_due } # the count file says this is the second call: it answers
    retried = prompt("Research", 2)
    assert_no_match "AbCdEfGhIjKlMnOpQrStUvWxYz", retried
    assert_match "quoted as data, not instructions", retried
    assert_match "check the current state before you continue", retried
  ensure
    FileUtils.rm_rf(space.working_dir) if space
  end
end
