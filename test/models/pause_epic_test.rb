require "test_helper"

# Spec 048: pausing one epic — the running step finishes, nothing more of the epic starts until the owner resumes it.
class PauseEpicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "You direct.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @agent, role: "member")
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra")
    @city = epic("Miasto", 3)
  end

  def epic(title, steps)
    item = @user.work_items.create!(title: title, space: @space, state: "planned")
    steps.times { |i| item.epic_steps.create!(position: i + 1, title: "Krok #{i + 1}", agent: @agent, state: "pending") }
    item
  end

  # A step run as Claude Code would: the fake program answers "ok".
  def run_queued(item)
    run = TaskRun.where(work_item: item, purpose: "epic_step", state: "queued").order(:id).first or return
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\necho ok\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      StepChain.new(run).perform!
    ensure
      ENV["PATH"] = original
    end
  end

  def claimable?(run) = !Agentaro::TaskScheduler.send(:claim_for, run).nil?

  test "S1, G1, G2: paused while step 2 runs — step 2 finishes, step 3 stays pending and nothing is claimed" do
    StepChain.start(@city)
    run_queued(@city) # step 1
    step2_run = TaskRun.where(work_item: @city, state: "queued").sole
    @city.pause!
    assert @city.reload.paused?
    assert_not claimable?(step2_run), "a queued run of a paused epic is not claimed"
    run_queued(@city) # it was already running when the owner paused: it finishes
    assert_equal %w[succeeded succeeded pending], @city.active_steps.map(&:state)
    assert_equal 0, TaskRun.where(work_item: @city, state: "queued").count
    assert_equal "planned", @city.reload.state
  end

  test "G3, S2: resume queues the next step; a pause survives a reload of the record (a restart)" do
    StepChain.start(@city)
    run_queued(@city)
    @city.pause!
    run_queued(@city)
    assert WorkItem.find(@city.id).paused?, "saved on the epic"
    @city.resume!
    assert_not @city.reload.paused?
    run = TaskRun.where(work_item: @city, state: "queued").sole
    assert_equal 3, run.epic_step.position
    assert claimable?(run)
  end

  test "G2: a retry waiting for its time is not handed over while paused" do
    StepChain.start(@city)
    first = TaskRun.where(work_item: @city, state: "queued").sole
    first.update!(retry_at: 1.minute.ago)
    @city.pause!
    StepRetry.hand_over_due
    assert first.reload.retry_at, "kept waiting"
    @city.resume!
    StepRetry.hand_over_due
    assert_nil first.reload.retry_at
  end

  test "S3, G4: a paused epic keeps its space; the next one waits, with the reason" do
    StepChain.start(@city)
    other = epic("Smok", 1)
    @city.pause!
    assert_equal @city, other.waits_for
    assert_equal "“Miasto” in this space (one epic at a time, paused)", StepView.new(other.active_steps.first).to_h[:waits]
  end

  test "R2: done, cancelled and blocked epics cannot be paused; a paused epic can be cancelled" do
    done = epic("Gotowe", 1)
    done.update!(state: "done")
    assert_raises(WorkItem::NotPausable) { done.pause! }
    @city.pause!
    @city.cancel!
    assert_equal "cancelled", @city.reload.state
  end

  test "B20: a paused epic that blocks loses its pause, so Try again really starts it" do
    StepChain.start(@city)
    @city.pause!
    @city.block!("Step 1 stopped")
    assert_not @city.reload.paused?
    assert_equal "blocked", @city.state
  end
end
