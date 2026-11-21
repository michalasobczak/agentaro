require "test_helper"

# Spec 023: busy or free per agent (G1, R1–R8, S3), and the status in the director's and verifier's prompts (G6, S5).
# Spec 036, S3 supersedes the labels: the load against the limit ("1/6 in progress"), busy only at the limit.
class AgentStatusTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-11-20 14:00")
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: executor)
    @evidence = Agent.create!(user: @user, name: "Evidence Agent", master_prompt: "x", executor: executor)
    @analyst = Agent.create!(user: @user, name: "Market Analyst", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @evidence, role: "member", role_text: "evidence")
    @user.team_roles.create!(agent: @analyst, role: "member", role_text: "analyst")
    @epic = @user.work_items.create!(title: "World review", state: "planned", started_at: 20.minutes.ago)
    @steps = [ [ "Find topics", @analyst, "succeeded" ], [ "Collect evidence", @evidence, "running" ], [ "Analyse", @analyst, "pending" ], [ "Summary", @evidence, "pending" ] ]
             .each_with_index.map { |(title, agent, state), i| @epic.epic_steps.create!(position: i + 1, title: title, agent: agent, state: state) }
  end

  def run_for(step, state: "running", user: @user, agent: step.agent, started: 12.minutes.ago)
    TaskRun.create!(user: user, work_item: step.work_item, epic_step: step, agent: agent, purpose: "epic_step", trigger: "scheduled",
                    occurrence_start: Time.current, state: state, started_at: (started unless state == "queued"))
  end

  def status = AgentStatus.for(@user)
  def label(agent) = AgentStatus.label(status[agent.id], AgentStatus.capacity(agent.running_tasks, agent.max_parallel_tasks))

  test "S1, R1, R7: a running step makes its agent busy with the epic and step N/M; the others are free" do
    run_for(@steps[1])
    activity = status.fetch(@evidence.id).sole
    assert_equal [ @epic.id, "World review", 2, 4, "Collect evidence", false ], [ activity.epic_id, activity.epic, activity.step, activity.of, activity.title, activity.cancelled ]
    assert_equal "1/6 in progress · World review · step 2/4: Collect evidence", label(@evidence)
    assert_equal "free · 0/6 in progress", label(@analyst)
    assert_equal "12 min", AgentStatus.elapsed(activity.started_at)
  end

  test "R2: a queued run is not work yet — free" do
    run_for(@steps[1], state: "queued")
    assert_empty status
  end

  test "R3: failed, timed out, skipped or interrupted runs leave the agent free" do
    %w[failed timed_out skipped succeeded].each { |state| run_for(@steps[1], state: state) }
    assert_empty status
  end

  test "R1: the step must still be running and in the active plan" do
    run = run_for(@steps[1])
    @steps[1].update!(state: "failed")
    assert_empty status, "the step stopped though the run row is still running"
    @steps[1].update!(state: "running")
    @epic.update!(active_step_from: 5)
    assert_empty status, "a retired plan does not count"
    assert run.reload.state == "running"
  end

  test "R4, Q2: a step still running in a cancelled or closed epic keeps its agent busy, marked" do
    run_for(@steps[1])
    @epic.update!(state: "cancelled")
    activity = status.fetch(@evidence.id).sole
    assert activity.cancelled
    assert_equal "1/6 in progress · finishing a step of a cancelled epic: World review · step 2/4: Collect evidence", label(@evidence)
    @epic.update!(state: "done")
    assert_match "finishing a step of a closed epic", label(@evidence)
  end

  test "R5: busy in two epics — every activity, oldest start first" do
    other = @user.work_items.create!(title: "Market scan", state: "planned", started_at: 5.minutes.ago)
    scan = other.epic_steps.create!(position: 1, title: "Scan", agent: @evidence, state: "running")
    run_for(scan, started: 2.minutes.ago)
    run_for(@steps[1])
    assert_equal [ "World review", "Market scan" ], status.fetch(@evidence.id).map(&:epic)
    assert_equal "2/6 in progress · World review · step 2/4: Collect evidence · +1 more", label(@evidence)
  end

  test "R7: numbering of a replanned epic counts only the active steps" do
    @epic.update!(active_step_from: 3)
    @steps[2].update!(state: "running")
    run_for(@steps[2])
    activity = status.fetch(@analyst.id).sole
    assert_equal [ 1, 2 ], [ activity.step, activity.of ]
  end

  test "R6: a deleted agent's runs count for no one; a disabled agent still running shows busy" do
    run_for(@steps[1], agent: nil)
    assert_empty status
    run_for(@steps[1])
    @evidence.update!(enabled: false)
    assert status.key?(@evidence.id)
  end

  test "R8, S4: another user's runs, also with a shared agent, never make the agent busy for me" do
    other = create_user(username: "bob")
    theirs = other.work_items.create!(title: "Secret plan", state: "planned", started_at: 1.minute.ago)
    secret = theirs.epic_steps.create!(position: 1, title: "Hidden step", agent: @evidence, state: "running")
    run_for(secret, user: other)
    assert_empty status
    # Spec 036, S6 (owner's decision) supersedes R8 for the count: their step counts as 1/6, never with its details.
    assert_equal [ "working", [] ], AgentStatus.json(@user)[:agents].find { |a| a[:id] == @evidence.id }.values_at(:status, :activities)
    assert_no_match "Secret plan", AgentStatus.json(@user).to_json
    assert_equal [ @evidence.id ], AgentStatus.for(other).keys
  end

  test "the stamp changes when a step starts and when it ends, and not otherwise" do
    before = AgentStatus.stamp(@user)
    assert_equal before, AgentStatus.stamp(@user)
    run = run_for(@steps[1])
    started = AgentStatus.stamp(@user)
    assert_not_equal before, started
    run.update!(state: "succeeded", finished_at: Time.current)
    assert_equal before, AgentStatus.stamp(@user)
  end

  test "G3, contract: members always show their dot; the director only while it runs a step" do
    data = AgentStatus.json(@user)
    assert_equal [ @evidence.id, @analyst.id, @director.id ], data[:agents].map { |a| a[:id] }
    assert_equal [ true, true, false ], data[:agents].map { |a| a[:show_dot] }
    @steps[2].update!(agent: @director, state: "running")
    run_for(@steps[2])
    director = AgentStatus.json(@user)[:agents].find { |a| a[:id] == @director.id }
    assert_equal [ "working", true ], [ director[:status], director[:show_dot] ] # spec 036: busy only at the limit
    assert_equal %i[epic_id epic step of title cancelled epic_state started_at].sort, director[:activities].first.keys.sort
  end

  test "G6, S5: the director's and the verifier's prompts say who is busy and who is free" do
    run_for(@steps[1])
    chat = ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:chat_prompt)
    verify = ManagementRunner.new(TaskRun.new(user: @user, purpose: "verify")).send(:verify_prompt)
    [ chat, verify ].each do |prompt|
      assert_match "Member id #{@evidence.id}: Evidence Agent, role: evidence; working: 1/6 tasks in progress, 5 free slots; yours: \"World review\" (id #{@epic.id}) step 2/4 \"Collect evidence\" for 12 min", prompt
      assert_match "Member id #{@analyst.id}: Market Analyst, role: analyst; free: 0/6 tasks in progress, 6 free slots", prompt
    end
  end

  # Spec 036, S3: a free slot keeps the agent "working", the limit makes it busy; the director is told who has room.
  test "spec 036, S3: 2/6 in progress is working, at the limit busy; the director's prompts say so" do
    other = @user.work_items.create!(title: "Market scan", state: "planned", started_at: 5.minutes.ago)
    scan = other.epic_steps.create!(position: 1, title: "Scan", agent: @evidence, state: "running")
    run_for(scan, started: 2.minutes.ago)
    run_for(@steps[1])
    entry = AgentStatus.json(@user)[:agents].find { |a| a[:id] == @evidence.id }
    assert_equal [ "working", "2/6 in progress" ], entry.values_at(:status, :headline)
    assert_equal "2/6 in progress · World review · step 2/4: Collect evidence · +1 more", entry[:label]

    @evidence.update!(max_parallel_tasks: 2)
    entry = AgentStatus.json(@user)[:agents].find { |a| a[:id] == @evidence.id }
    assert_equal [ "busy", "busy · 2/2 in progress", true ], [ entry[:status], entry[:headline], entry[:capacity][:full] ]
    analyst = AgentStatus.json(@user)[:agents].find { |a| a[:id] == @analyst.id }
    assert_equal [ "free", "free · 0/6 in progress" ], analyst.values_at(:status, :headline)

    plan = ManagementRunner.new(TaskRun.new(user: @user, purpose: "director", work_item: other))
    plan.instance_variable_set(:@item, other)
    prompt = plan.send(:plan_prompt)
    assert_match "Evidence Agent, role: evidence; busy: 2/2 tasks in progress, at its limit (a new step for it waits in the queue until one ends)", prompt
    assert_match "Market Analyst, role: analyst; free: 0/6 tasks in progress, 6 free slots", prompt
    assert_match "prefer a member with free slots", prompt
  end

  test "spec 036, S6: another user's running step counts in my status as a number, without its details" do
    other = create_user(username: "bob")
    theirs = other.work_items.create!(title: "Secret plan", state: "planned", started_at: 1.minute.ago)
    secret = theirs.epic_steps.create!(position: 1, title: "Hidden step", agent: @analyst, state: "running")
    run_for(secret, user: other)
    entry = AgentStatus.json(@user)[:agents].find { |a| a[:id] == @analyst.id }
    assert_equal [ "working", "1/6 in progress", "1/6 in progress", [] ], entry.values_at(:status, :headline, :label, :activities)
    assert_no_match "Secret plan", AgentStatus.json(@user).to_json
  end
end
