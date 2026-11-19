require "test_helper"

# Spec 009: agents pages (G1–G3), permissions (S2), assignment through forms and calendar (G4, S1, S3).
class AgentsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @admin = create_user(username: "root1", role: "admin")
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
  end

  def t(str) = Time.zone.parse(str)

  def make_agent(**attrs)
    Agent.create!({ user: @user, name: "Helper", master_prompt: "You are a careful assistant.", executor: @executor }.merge(attrs))
  end

  def task_params(**extra)
    { title: "Write report", start_date: "2026-11-20", start_time: "10:00", end_date: "2026-11-20", end_time: "11:00" }.merge(extra)
  end

  test "users create, edit and delete their private agents" do
    sign_in(@user)
    get new_agent_path
    assert_response :success
    post agents_path, params: { agent: { name: "Researcher", master_prompt: "You research things.", executor_id: @executor.id, kind: "shared" } }
    assert_redirected_to agents_path
    agent = Agent.find_by!(name: "Researcher")
    assert_equal [ "private", @user ], [ agent.kind, agent.user ], "users cannot create shared agents"

    patch agent_path(agent), params: { agent: { description: "Finds sources", model: "opus", enabled: "0" } }
    assert_equal [ "Finds sources", "opus", false ], [ agent.reload.description, agent.model, agent.enabled ]

    get agents_path
    assert_select ".agent-list", text: /Researcher/

    delete agent_path(agent)
    assert_not Agent.exists?(agent.id)
  end

  test "admins create shared agents that everyone sees read-only" do
    sign_in(@admin)
    post agents_path, params: { agent: { name: "Team writer", master_prompt: "You write for the team.", executor_id: @executor.id, kind: "shared" } }
    shared = Agent.find_by!(name: "Team writer")
    assert shared.shared?

    sign_in(@user)
    get agents_path
    assert_select ".agent-list", text: /Team writer/
    get agent_path(shared)
    assert_response :success
    assert_select ".pre", text: "You write for the team."
    get edit_agent_path(shared)
    assert_response :forbidden
    patch agent_path(shared), params: { agent: { name: "Mine now" } }
    assert_response :forbidden
    delete agent_path(shared)
    assert_response :forbidden
    assert_equal "Team writer", shared.reload.name
  end

  test "S2: other users' private agents do not exist (also for admins)" do
    theirs = make_agent
    sign_in(@admin)
    get agents_path
    assert_no_match "Helper", response.body
    get agent_path(theirs)
    assert_response :not_found
    patch agent_path(theirs), params: { agent: { name: "X" } }
    assert_response :not_found
    delete agent_path(theirs)
    assert_response :not_found
    assert Agent.exists?(theirs.id)
  end

  test "only enabled executors can be chosen; a forged one is refused" do
    off = Executor.create!(name: "Off", preset: "codex", enabled: false)
    sign_in(@user)
    get new_agent_path
    assert_select "select[name='agent[executor_id]'] option[value='#{off.id}']", 0
    post agents_path, params: { agent: { name: "Sneaky", master_prompt: "x", executor_id: off.id } }
    assert_response :unprocessable_content
    assert_match "Executor must exist", response.body
  end

  test "G4, S1: assign an agent in the task form; the calendar and popup show it" do
    agent = make_agent
    sign_in(@user)
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select "dialog#task-dialog select[name='task[agent_id]'] option[value='#{agent.id}']", text: "Helper"
    post tasks_path, params: { task: task_params(agent_id: agent.id) }, headers: { "Accept" => "application/json" }
    task = Task.find_by!(title: "Write report")
    assert_equal agent, task.agent

    get calendar_path(view: "week", date: "2026-11-20")
    assert_select "a.task .task-agent", text: /Helper/
    get edit_task_path(task)
    assert_select "select[name='task[agent_id]'] option[selected][value='#{agent.id}']"

    patch task_path(task), params: { task: task_params(agent_id: "") }
    assert_nil task.reload.agent_id
  end

  test "S2, S3: forged, private-to-others, disabled agents are refused; a kept agent stays" do
    theirs = make_agent(user: create_user(username: "bob"), name: "Bob's")
    disabled = make_agent(name: "Sleepy", enabled: false)
    sign_in(@user)
    [ theirs, disabled ].each do |agent|
      post tasks_path, params: { task: task_params(title: "T#{agent.id}", agent_id: agent.id) }
      assert_response :unprocessable_content
      assert_match "Agent is not available", response.body
    end

    mine = make_agent(name: "Mine")
    task = Task.create!(user: @user, title: "Kept", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"), agent: mine)
    mine.update!(enabled: false)
    patch task_path(task), params: { task: task_params(title: "Kept and renamed", agent_id: mine.id) }
    assert_equal [ "Kept and renamed", mine ], [ task.reload.title, task.agent ]
    get edit_task_path(task)
    assert_select "option[selected]", text: /Mine — not available/
  end

  test "system-wide tasks take shared agents only" do
    mine = make_agent(user: @admin, name: "Admin private")
    shared = make_agent(user: @admin, kind: "shared", name: "Team")
    sign_in(@admin)
    post tasks_path, params: { task: task_params(title: "Office", calendar: "system", agent_id: mine.id) }
    assert_response :unprocessable_content
    post tasks_path, params: { task: task_params(title: "Office", calendar: "system", agent_id: shared.id) }
    assert_equal shared, Task.find_by!(title: "Office").agent

    sign_in(@user)
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select "a.task .task-agent", text: /Team/
  end

  test "an executor used by agents cannot be deleted" do
    make_agent
    sign_in(@admin)
    delete admin_executor_path(@executor)
    assert_redirected_to edit_admin_executor_path(@executor)
    assert Executor.exists?(@executor.id)
  end

  test "pages have no inline styles or scripts" do
    agent = make_agent
    sign_in(@user)
    [ agents_path, new_agent_path, edit_agent_path(agent) ].each do |path|
      get path
      assert_response :success
      assert_select "[style]", 0, path
      assert_select "script:not([src])", 0, path
    end
  end
end
