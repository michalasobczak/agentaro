require "test_helper"

# Spec 025: an archived space is deleted with its epics, steps, calendar entries, runs and run folders; running
# steps are stopped first.
class SpacePurgeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: @executor)
    @space = @user.spaces.create!(name: "Old", kind: "team")
    @other = @user.spaces.create!(name: "Kept", kind: "team")
    @runs_dir = Rails.application.config.x.runs_dir
  end

  def epic(space, title)
    item = @user.work_items.create!(title: title, space: space, state: "planned", started_at: 1.hour.ago)
    step = item.epic_steps.create!(position: 1, title: "Write", agent: @agent, state: "succeeded")
    run = TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @agent, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: Time.current, state: "succeeded", output: "done")
    FileUtils.mkdir_p(File.join(@runs_dir, run.id.to_s, "work"))
    task = Task.create!(user: @user, work_item: item, title: "Write", starts_at: 1.hour.ago, ends_at: 30.minutes.ago)
    [ item, step, run, task ]
  end

  test "G3, R4, R5: everything of the space goes; chat text stays; other spaces and folders are untouched" do
    item, step, run, task = epic(@space, "Old epic")
    kept, _, kept_run, = epic(@other, "Kept epic")
    note = @user.chat_messages.create!(author: "director", content: "Planned Old epic", task_run: run)
    @space.update!(state: "archived")

    assert_equal({ epics: 1, running: 0 }, @space.purge_counts)
    @space.purge!

    assert_not Space.exists?(@space.id)
    assert_not WorkItem.exists?(item.id)
    assert_not EpicStep.exists?(step.id)
    assert_not TaskRun.exists?(run.id)
    assert_not Task.exists?(task.id)
    assert_not File.exist?(File.join(@runs_dir, run.id.to_s)), "the run's folder is removed"
    assert_equal [ "Planned Old epic", nil ], note.reload.values_at(:content, :task_run_id), "the chat keeps its text"
    assert WorkItem.exists?(kept.id)
    assert TaskRun.exists?(kept_run.id)
    assert File.exist?(File.join(@runs_dir, kept_run.id.to_s))
  ensure
    FileUtils.rm_rf(@runs_dir)
  end

  test "G5: an active space with epics is not deleted with them" do
    epic(@space, "Live")
    assert_raises(ArgumentError) { @space.purge! }
    assert Space.exists?(@space.id)
  ensure
    FileUtils.rm_rf(@runs_dir)
  end

  test "G4, R3: a step running in the space is stopped (its process killed) and the space deleted; a queued one is skipped" do
    item = @user.work_items.create!(title: "Running", space: @space, state: "planned", started_at: 1.minute.ago)
    step = item.epic_steps.create!(position: 1, title: "Long", agent: @agent, state: "running")
    second = item.epic_steps.create!(position: 2, title: "Next", agent: @agent, state: "queued")
    run = TaskRun.create!(user: @user, work_item: item, epic_step: step, agent: @agent, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: Time.current, state: "queued")
    queued = TaskRun.create!(user: @user, work_item: item, epic_step: second, agent: @agent, purpose: "epic_step", trigger: "scheduled",
                             occurrence_start: Time.current, state: "queued")
    @space.update!(state: "archived")

    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nsleep 30\necho late\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      worker = Thread.new { AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "x", user: "y")).call.tap { |o| TaskRunner.finish!(run, o) } }
      sleep 0.05 until RunControl.running?(run.id)
      assert_equal({ epics: 1, running: 2 }, @space.purge_counts)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @space.purge!
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5, "stopped at once, not after 30 s"
      outcome = worker.value
      assert_match "killed by signal 9", outcome.error.to_s
    ensure
      ENV["PATH"] = original
    end
    assert_not Space.exists?(@space.id)
    assert_not TaskRun.exists?(run.id)
    assert_not TaskRun.exists?(queued.id)
    assert_not RunControl.running?(run.id)
  ensure
    FileUtils.rm_rf(@runs_dir)
  end
end
