require "test_helper"

# Spec 016: an epic starts at its time; steps run one after another with the earlier answers (G1–G7, R1–R3, S1–S3).
class StepChainTest < ActiveSupport::TestCase
  setup do
    @user = create_user
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
      StepChain.start(@item)
      @item.cancel!
      run_queued
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
    assert text.bytesize <= StepChain::HISTORY_BUDGET + 200
    assert_match "Compare #{"x" * 1000}", text, "the newest answer is whole"
    assert_match(/Step 1: Research.*cut at/m, text, "the older one is shortened")
  end
end
