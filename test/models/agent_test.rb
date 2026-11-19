require "test_helper"

# Spec 009: agent rules (R1, R2), visibility (G2), assignment (R3, R4), deletion (R5, S4).
class AgentTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user(username: "root1", role: "admin")
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
  end

  def t(str) = Time.zone.parse(str)

  def agent(**attrs)
    Agent.new({ user: @user, name: "Helper", master_prompt: "You are a careful assistant.", executor: @executor }.merge(attrs))
  end

  def task(**attrs)
    Task.new({ user: @user, title: "Task", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00") }.merge(attrs))
  end

  test "R1: required fields and limits" do
    assert agent.valid?
    assert_not agent(name: " ").valid?
    assert_not agent(name: "x" * 61).valid?
    assert_not agent(master_prompt: "  ").valid?
    assert_not agent(master_prompt: "x" * 20_001).valid?
    assert_not agent(description: "x" * 501).valid?
    assert_not agent(executor: nil).valid?
    assert_not agent(kind: "public").valid?
  end

  test "R1: names are unique per user's private list and among shared agents" do
    agent.save!
    assert_not agent(name: "helper").valid?
    assert agent(user: create_user(username: "bob")).valid?, "another user's private list"
    assert agent(user: @admin, kind: "shared").valid?, "shared list is separate"
    agent(user: @admin, kind: "shared").save!
    assert_not agent(user: @admin, kind: "shared", name: "HELPER").valid?
  end

  test "R2: only admins create shared agents; the kind is fixed" do
    assert_not agent(kind: "shared").valid?
    shared = agent(user: @admin, kind: "shared").tap(&:save!)
    shared.kind = "private"
    assert_not shared.valid?
  end

  test "G2: private agents visible to their owner only; shared to everyone" do
    mine = agent.tap(&:save!)
    shared = agent(user: @admin, kind: "shared", name: "Team").tap(&:save!)
    admin_private = agent(user: @admin, name: "Admin's").tap(&:save!)
    assert_equal [ mine, shared ].sort_by(&:id), Agent.visible_to(@user).order(:id).to_a
    assert_equal [ shared, admin_private ].sort_by(&:id), Agent.visible_to(@admin).order(:id).to_a, "admins do not see users' private agents"
    assert mine.editable_by?(@user)
    assert_not mine.editable_by?(@admin)
    assert shared.editable_by?(@admin)
    assert_not shared.editable_by?(@user)
  end

  test "R3: assignable means usable, and shared only for system-wide tasks" do
    mine = agent.tap(&:save!)
    shared = agent(user: @admin, kind: "shared", name: "Team").tap(&:save!)
    off = agent(name: "Off", enabled: false).tap(&:save!)
    assert_equal [ mine, shared ].sort_by(&:id), Agent.assignable(@user, "private").order(:id).to_a
    assert_equal [ shared ], Agent.assignable(@admin, "system").to_a
    @executor.update!(enabled: false)
    assert_empty Agent.assignable(@user, "private")
    assert_not off.usable?
  end

  test "R4: a private agent only on its owner's private tasks" do
    mine = agent.tap(&:save!)
    assert task(agent: mine).valid?
    assert_not task(agent: mine, user: create_user(username: "bob")).valid?
    system_task = task(user: @admin, calendar: "system", agent: mine)
    assert_not system_task.valid?
    assert_includes system_task.errors.full_messages, "Agent must be a shared agent on a system-wide task"
    shared = agent(user: @admin, kind: "shared", name: "Team").tap(&:save!)
    assert task(user: @admin, calendar: "system", agent: shared).valid?
  end

  test "S1: a recurring task keeps its agent on every occurrence, also when one is detached" do
    mine = agent.tap(&:save!)
    series = task(agent: mine, repeat: "daily", repeat_count: 3).tap(&:save!)
    assert series.occurrences(t("2026-11-20 00:00")...t("2026-11-23 00:00")).all? { |o| o.task.agent == mine }
    second = series.series_starts[1]
    result = TaskEditor.new(series, occurrence_start: second).move(starts_at: second + 1.hour, ends_at: second + 2.hours, scope: "this")
    assert_equal mine, result.task.agent
  end

  test "F11: copies and duplicates keep a usable agent and drop an unusable one" do
    mine = agent.tap(&:save!)
    source = task(agent: mine).tap(&:save!)
    assert_equal mine, TaskEditor.new(source).duplicate(calendar: "private").task.agent
    mine.update!(enabled: false)
    copy = TaskEditor.new(source).copy(starts_at: t("2026-11-22 09:00"), calendar: "private").task
    assert copy.persisted?
    assert_nil copy.agent
    assert_equal mine, source.reload.agent, "the original keeps its agent"
  end

  test "R5, S4: deleting an agent unassigns its tasks, recorded in the changelog; executors in use stay" do
    mine = agent.tap(&:save!)
    kept = task(agent: mine).tap(&:save!)
    assert_not @executor.destroy, "executor used by an agent"
    assert Executor.exists?(@executor.id)
    mine.destroy!
    assert_nil kept.reload.agent_id
    change = DataChange.where(record_type: "Task", record_id: kept.id, action: "update").last
    assert_equal [ mine.id, nil ], change.changes_hash["agent_id"]
    assert @executor.reload.destroy, "free again"
  end
end
