require "test_helper"

# Spec 037: one epic at a time in a space — the holder (R1–R4), the next one starting by itself (G2, R6),
# a waiting or blocked epic keeps the space (S2), other spaces are not held (S3), epics already interleaving (S4),
# recurring occurrences (S6) and retries (R2).
class OneEpicPerSpaceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.update!(auto_retry: false)
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @a = epic("A")
    @b = epic("B")
  end

  def epic(title, space: @space, steps: 2)
    item = @user.work_items.create!(title: title, state: "planned", space: space)
    steps.times { |i| item.epic_steps.create!(position: i + 1, title: "#{title}#{i + 1}", agent: @writer) }
    item
  end

  def with_agent(fail: nil, ask: nil)
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        task=$(printf '%s' "$input" | sed -n 's/^Your task: //p' | head -1)
        if [ "$task" = "#{fail}" ]; then echo "broken" >&2; exit 3; fi
        if [ "$task" = "#{ask}" ] && [ ! -f "#{bin}/asked" ]; then
          touch "#{bin}/asked"
          echo 'AGENTARO-DECISION: {"question": "PDF?", "options": ["PDF", "MD"], "recommended": "MD", "why": "x", "important": true}'
          exit 0
        fi
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

  # Runs queued steps one by one and returns their titles in the order they ran.
  def run_queued(limit = 20)
    order = []
    limit.times do
      run = TaskRun.where(state: "queued", purpose: "epic_step", retry_at: nil).order(:id).first or break
      order << run.epic_step.title
      StepChain.new(run).perform!
    end
    order
  end

  test "R1–R4: the holder is the earliest-ordered epic in progress; a new or unapproved epic does not hold the space" do
    assert_nil @a.waits_for
    assert_nil @b.waits_for, "nothing in progress yet"
    @b.update!(started_at: Time.current)
    assert_equal @b, @a.waits_for, "an epic not started waits for any epic in progress"
    @a.update!(started_at: Time.current)
    assert_nil @a.waits_for, "of two in progress, the earlier-ordered holds"
    assert_equal @a, @b.waits_for
    @a.update!(state: "blocked")
    assert_equal @a, @b.waits_for, "blocked still holds"
    @a.update!(state: "done")
    assert_nil @b.waits_for

    c = @user.work_items.create!(title: "C", state: "new", space: @space)
    d = epic("D")
    d.update!(awaiting_approval: true)
    [ c, d ].each { |x| assert_not x.in_progress? }
    assert_nil epic("E").tap { |e| e.update!(space: @user.spaces.create!(name: "Inna", kind: "team")) }.waits_for
  end

  test "S1, G2: all steps of A run before B's first; B starts by itself when A is done" do
    with_agent do
      StepChain.start_due(user: @user)
      assert_equal [ "queued", "pending" ], [ @a.epic_steps.first.reload.state, @b.epic_steps.first.reload.state ]
      assert_nil @b.reload.started_at
      assert_equal %w[A1 A2 B1 B2], run_queued
    end
    assert_equal %w[done done], [ @a.reload.state, @b.reload.state ]
  end

  test "S2: a step of A waiting for the owner's answer keeps B waiting; answering goes on with A" do
    with_agent(ask: "A1") do
      StepChain.start_due(user: @user)
      assert_equal %w[A1], run_queued
      decision = @a.step_decisions.pending.sole
      assert_equal "waiting", @a.epic_steps.first.reload.state
      StepChain.start_due(user: @user)
      assert_nil @b.reload.started_at, "B does not start while A waits for an answer"
      decision.answer_by_owner!("PDF")
      assert_equal %w[A1 A2 B1 B2], run_queued
    end
  end

  test "S2: a blocked A keeps B waiting; cancelling A starts B at once" do
    with_agent(fail: "A1") do
      StepChain.start_due(user: @user)
      run_queued
      assert_equal "blocked", @a.reload.state
      StepChain.start_due(user: @user)
      assert_nil @b.reload.started_at
      @a.cancel!
      assert @b.reload.started_at, "R6: the next epic starts in the same pass"
      assert_equal %w[B1 B2], run_queued
    end
  end

  test "S2: Done by hand on A releases the space at the next pass" do
    StepChain.start_due(user: @user)
    @a.done!
    StepChain.start_due(user: @user)
    assert @b.reload.started_at
  end

  test "S3: epics of different spaces run side by side" do
    other = epic("X", space: @user.spaces.create!(name: "Inna", kind: "team"))
    StepChain.start_due(user: @user)
    assert [ @a.reload.started_at, other.reload.started_at ].all?
    assert_nil @b.reload.started_at
  end

  test "S4: two epics already interleaving — the running step finishes, then the later one waits for the earlier" do
    @a.update!(started_at: 1.hour.ago, state: "blocked", blocked_reason: "Step 1 asks")
    @a.epic_steps.first.update!(state: "waiting")
    @b.update!(started_at: 10.minutes.ago)
    step = @b.epic_steps.first
    step.update!(state: "queued")
    run = TaskRun.create!(user: @user, work_item: @b, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current, state: "queued")
    with_agent { StepChain.new(run).perform! }
    assert_equal [ "succeeded", "pending" ], @b.epic_steps.reload.map(&:state)
    assert_empty TaskRun.where(state: "queued"), "B queues no further step while A is unfinished"
    assert_equal @a, @b.reload.waits_for
  end

  test "R2: a retry of a later epic waits (and a chat retry is refused) while the earlier holds the space" do
    @a.update!(started_at: 1.hour.ago)
    @b.update!(started_at: 10.minutes.ago, state: "blocked")
    step = @b.epic_steps.first
    step.update!(state: "failed")
    failed = TaskRun.create!(user: @user, work_item: @b, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current, state: "failed")
    assert_match "waits for \"A\" in this space", StepChain.retry_problem(@b, step, failed.id)

    @b.update!(state: "planned")
    step.update!(state: "queued")
    retry_run = TaskRun.create!(user: @user, work_item: @b, epic_step: step, agent: @writer, purpose: "epic_step", trigger: "retry", occurrence_start: Time.current, state: "queued", retry_at: 1.minute.ago)
    StepRetry.hand_over_due
    assert retry_run.reload.retry_at, "still waiting"
    @a.update!(state: "done")
    StepRetry.hand_over_due
    assert_nil retry_run.reload.retry_at
  end

  test "S6: a recurring occurrence in a busy space is created and waits; it is not skipped" do
    StepChain.start_due(user: @user)
    order = travel_to(Time.zone.local(2026, 11, 23, 7, 0)) do
      @user.recurring_orders.create!(space: @space, title: "Przegląd", kind: "daily", at_time: "08:00",
                                     last_plan: [ { "title" => "R1", "description" => "", "agent" => @writer.id } ])
    end
    travel_to(Time.zone.local(2026, 11, 23, 8, 1)) do
      item = RecurringOrder.run_due.sole
      assert_equal "planned", item.state
      assert_nil item.started_at
      assert_equal @a, item.waits_for
      assert_nil order.reload.note
    end
  end
end
