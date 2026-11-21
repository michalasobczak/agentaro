require "test_helper"

# Spec 016: an epic starts at its time; steps run one after another with the earlier answers (G1–G7, R1–R3, S1–S3).
class StepChainTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.update!(auto_retry: false) # these tests cover blocking and manual retries; spec 032's automatic ones: step_retry_test.rb
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @item = @user.work_items.create!(title: "Backups", state: "planned")
    %w[Research Fail\ maybe Write].each_with_index do |title, i|
      @item.epic_steps.create!(position: i + 1, title: title == "Fail maybe" ? "Compare" : title, agent: @writer)
    end
    @prompts = Dir.mktmpdir
    @fail = nil
  end

  teardown { FileUtils.rm_rf(@prompts) }

  # A stand-in "claude": answers "Answer for <task>", keeps each prompt, and fails for the task named in FAIL_TASK.
  def with_agent(fail: nil)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
        printf '%s' "$input" > "#{@prompts}/prompt-$task"
        if [ "$task" = "#{fail}" ]; then echo "broken" >&2; exit 3; fi
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

  def run_queued(limit = 10)
    limit.times do
      run = TaskRun.where(state: "queued", purpose: "epic_step").order(:id).first or break
      StepChain.new(run).perform!
    end
  end

  def prompt(task) = File.read(File.join(@prompts, "prompt-#{task}"))

  test "S1: the epic waits for its start, then runs every step back to back and ends done" do
    @item.update!(starts_at: 1.hour.from_now)
    assert_empty StepChain.start_due, "not yet"
    travel 2.hours do
      with_agent do
        assert_equal 1, StepChain.start_due.size
        assert_equal [ "queued", "pending", "pending" ], @item.epic_steps.reload.map(&:state)
        assert_nil StepChain.queue_next(@item), "R1: never two steps of one epic at once"
        run_queued
      end
    end
    @item.reload
    assert_equal [ "done", %w[succeeded succeeded succeeded] ], [ @item.state, @item.epic_steps.map(&:state) ]
    assert @item.started_at && @item.finished_at
    assert_equal "Answer for Write", @item.epic_steps.last.last_run.output.strip
    assert_match "Done: \"Backups\" — all 3 steps finished", @user.chat_messages.last.content
  end

  test "S2, G4: each step gets the answers of the earlier steps, in order" do
    with_agent do
      StepChain.start(@item)
      run_queued
    end
    write = prompt("Write")
    assert_match "This is step 3 of 3 of the epic \"Backups\"", write
    assert_match(/Step 1: Research.*Answer for Research.*Step 2: Compare.*Answer for Compare/m, write)
    assert_no_match "Answers of the earlier steps", prompt("Research")
  end

  test "S3, G5: a failed step blocks the epic and stops the chain; Try again resumes from it" do
    with_agent(fail: "Compare") do
      StepChain.start(@item)
      run_queued
    end
    @item.reload
    assert_equal [ "blocked", %w[succeeded failed pending] ], [ @item.state, @item.epic_steps.map(&:state) ]
    assert_match "Step 2 \"Compare\" failed", @item.blocked_reason
    assert_match "stopped at step 2 of 3", @user.chat_messages.last.content
    assert_nil @item.epic_steps.last.last_run, "no later step ran"

    with_agent do
      StepChain.resume(@item)
      run_queued
    end
    assert_equal [ "done", %w[succeeded succeeded succeeded] ], [ @item.reload.state, @item.epic_steps.map(&:state) ]
    assert_equal 1, @item.epic_steps.first.runs.count, "the step that succeeded did not run again"
  end

  test "G7: cancelling stops the chain; a running step finishes and its answer is kept" do
    with_agent do
      run = StepChain.start(@item)
      runner = StepChain.new(run)
      step = runner.send(:claim_run)
      assert_equal "running", step.state
      @item.cancel!
      outcome = AgentCall.new(run, @writer, StepChain.prompt_for(step, @writer)).call
      TaskRunner.finish!(run, outcome)
      StepChain.after_run(run)
    end
    @item.reload
    assert_equal [ "cancelled", %w[succeeded cancelled cancelled] ], [ @item.state, @item.epic_steps.map(&:state) ]
    assert_equal "Answer for Research", @item.epic_steps.first.last_run.output.strip
    assert_equal 1, TaskRun.where(purpose: "epic_step").count
  end

  test "R3: a step whose agent is gone is skipped and blocks the epic" do
    @item.epic_steps.first.update!(agent: nil)
    StepChain.start(@item)
    run_queued
    assert_equal "blocked", @item.reload.state
    assert_equal "skipped", @item.epic_steps.first.state
  end

  test "resilience: a step interrupted by a restart blocks the epic" do
    StepChain.start(@item)
    TaskRun.where(purpose: "epic_step").update_all(state: "running") # simulate the crash mid-run
    Agentaro::TaskScheduler.recover!
    assert_equal "blocked", @item.reload.state
    assert_match "Interrupted", @item.blocked_reason
  end

  test "R2: earlier answers fit a budget, newest whole first" do
    first, second, third = @item.epic_steps.to_a
    [ first, second ].each do |step|
      step.update!(state: "succeeded")
      TaskRun.create!(user: @user, work_item: @item, epic_step: step, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current,
                      state: "succeeded", output: "#{step.title} " + "x" * 25_000)
    end
    text = StepChain.earlier_answers(third)
    assert_operator text.bytesize, :<=, StepChain::HISTORY_BUDGET
    assert_match "Compare #{"x" * 1000}", text, "the newest answer is whole"
    assert_match(/Step 1: Research.*cut at/m, text, "the older one is shortened")
  end

  # --- Spec 021: retrying one failed step (G2, R5, R6, S3, resilience) ---------------------------------------------

  def block_at_compare
    with_agent(fail: "Compare") do
      StepChain.start(@item)
      run_queued
    end
    @item.reload
  end

  def compare = @item.epic_steps.find_by(position: 2)

  test "S3, R6: retrying the failed step queues one attempt with the earlier answer; the chain then goes on" do
    block_at_compare
    failed = compare.last_run
    first_run = @item.epic_steps.first.last_run
    run = StepChain.retry_step!(@item, compare, failed.id)
    assert_equal [ "queued", "epic_step", compare.id ], [ run.state, run.purpose, run.epic_step_id ]
    assert_equal [ "planned", %w[succeeded queued pending] ], [ @item.reload.state, @item.epic_steps.map(&:state) ]
    assert_nil StepChain.queue_next(@item), "never a second attempt or the next step at once"
    with_agent { run_queued }
    assert_match(/Step 1: Research.*Answer for Research/m, prompt("Compare"), "the retry gets the earlier answer")
    assert_equal [ "done", %w[succeeded succeeded succeeded] ], [ @item.reload.state, @item.epic_steps.map(&:state) ]
    assert_equal [ first_run ], @item.epic_steps.first.runs.to_a, "step 1 kept its original run"
    assert_equal [ "failed", "succeeded" ], compare.runs.order(:id).map(&:state), "the failed attempt stays in history"
  end

  test "S3: another failure blocks the epic at the same step again" do
    block_at_compare
    StepChain.retry_step!(@item, compare, compare.last_run.id)
    with_agent(fail: "Compare") { run_queued }
    assert_equal [ "blocked", %w[succeeded failed pending] ], [ @item.reload.state, @item.epic_steps.map(&:state) ]
    assert_equal 2, compare.runs.count
    assert_nil @item.epic_steps.last.last_run
  end

  test "R5: stale, duplicate and ineligible retries change nothing" do
    block_at_compare
    failed = compare.last_run
    assert_raises(StepChain::Ineligible) { StepChain.retry_step!(@item, compare, failed.id + 1000) }
    assert_raises(StepChain::Ineligible) { StepChain.retry_step!(@item, @item.epic_steps.first, failed.id) }
    @writer.update!(enabled: false)
    assert_match "not available", assert_raises(StepChain::Ineligible) { StepChain.retry_step!(@item, compare, failed.id) }.message
    @writer.update!(enabled: true)
    compare.update!(state: "timed_out")
    assert_match "Try again on the epic's page", StepChain.retry_problem(@item, compare, failed.id)
    compare.update!(state: "failed")
    assert_equal [ "blocked", 1 ], [ @item.reload.state, compare.runs.count ]

    StepChain.retry_step!(@item, compare, failed.id)
    assert_raises(StepChain::Ineligible) { StepChain.retry_step!(@item, compare, failed.id) }
    assert_nil StepChain.resume(@item), "Try again after a chat retry starts nothing"
    assert_equal 1, TaskRun.where(work_item: @item, state: %w[queued running]).count
  end

  test "resilience: a cancelled epic cannot be retried; Try again and a retry have one winner" do
    block_at_compare
    failed = compare.last_run
    @item.cancel!
    assert_raises(StepChain::Ineligible) { StepChain.retry_step!(@item, compare, failed.id) }
    assert_equal 1, compare.runs.count

    other = @user.work_items.create!(title: "Other", state: "planned")
    other.epic_steps.create!(position: 1, title: "Compare", agent: @writer)
    with_agent(fail: "Compare") { StepChain.start(other); run_queued }
    step = other.epic_steps.first
    assert StepChain.resume(other.reload), "Try again wins"
    assert_raises(StepChain::Ineligible) { StepChain.retry_step!(other, step, step.runs.last.id) }
    assert_equal 1, TaskRun.where(work_item: other, state: %w[queued running]).count
  end

  test "resilience: when the scheduler cannot take the run it stays queued for the next start" do
    block_at_compare
    original = Agentaro::TaskScheduler.method(:enqueue)
    Agentaro::TaskScheduler.define_singleton_method(:enqueue) { |_id| raise IOError, "scheduler down" }
    run = StepChain.retry_step!(@item, compare, compare.last_run.id)
    assert_equal "queued", run.reload.state
    assert_equal 1, TaskRun.where(work_item: @item, state: "queued").count
  ensure
    Agentaro::TaskScheduler.define_singleton_method(:enqueue, original) if original
  end
  test "cancelling a queued retry prevents a worker with a stale run from starting an agent" do
    block_at_compare
    queued = StepChain.retry_step!(@item, compare, compare.last_run.id)
    @item.cancel!
    StepChain.new(queued).perform!
    assert_equal %w[cancelled skipped], [ compare.reload.state, queued.reload.state ]
    assert_nil queued.started_at
    assert_nil queued.prompt
    assert_equal "cancelled", @item.reload.state
    assert_not @item.active_run?
  end

  test "earlier answers use only the latest successful attempt of the same account and epic" do
    block_at_compare
    first = @item.epic_steps.first
    other = @user.work_items.create!(title: "Other")
    TaskRun.create!(user: @user, work_item: other, epic_step: first, agent: @writer,
                    purpose: "epic_step", trigger: "manual", occurrence_start: Time.current,
                    state: "succeeded", output: "unrelated answer")
    answers = StepChain.earlier_answers(compare)
    assert_includes answers, "Answer for Research"
    assert_no_match "unrelated answer", answers

    first.last_run.update!(work_item: @item, state: "failed")
    assert_empty StepChain.earlier_answers(compare), "an older successful attempt must stay in history"
  end

  test "the history budget counts all headers, separators and the omission notice" do
    9.times do |i|
      step = @item.epic_steps.create!(position: i + 4, title: "ż" * 200, state: "succeeded")
      TaskRun.create!(user: @user, work_item: @item, epic_step: step, purpose: "epic_step",
                      trigger: "manual", occurrence_start: Time.current, state: "succeeded", output: "🌍" * 15_000)
    end
    last = @item.epic_steps.create!(position: 13, title: "Finish")
    text = StepChain.earlier_answers(last)
    assert_operator text.bytesize, :<=, StepChain::HISTORY_BUDGET
    assert text.valid_encoding?
    assert_match(/left out.*Step 12:.*cut at/m, text)
    assert_equal 1, text.scan("left out").size
  end

end
