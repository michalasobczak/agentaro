require "test_helper"

# Spec 027: beside the director chat, each active space with its epics in progress and their steps.
class WorkPanelTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "x", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @home = @user.spaces.create!(name: "Home", kind: "team")
    @quiet = @user.spaces.create!(name: "Quiet", kind: "team")
    @old = @user.spaces.create!(name: "Old", kind: "team", state: "archived")
    @running = @user.work_items.create!(title: "Backups", space: @home, state: "planned", started_at: 5.minutes.ago)
    @running.epic_steps.create!(position: 1, title: "Find tools", agent: @writer, state: "succeeded")
    @running.epic_steps.create!(position: 2, title: "Compare", agent: @writer, state: "running")
    @user.work_items.create!(title: "Later", space: @home, state: "planned", starts_at: 1.day.from_now)
    @user.work_items.create!(title: "Finished", space: @home, state: "done", started_at: 1.day.ago, finished_at: 1.hour.ago)
    sign_in(@user)
  end

  test "G1–G3: active spaces only; epics in progress, running first, with their steps; finished ones left out" do
    data = WorkPanel.for(@user)
    assert_equal %w[Home Quiet], data[:spaces].map { |s| s[:name] }
    home = data[:spaces].first
    assert_equal [ [ "Backups", "running" ], [ "Later", "planned" ] ], home[:epics].map { |e| e.values_at(:title, :state) }
    assert_equal [ [ 1, "Find tools", "succeeded", "Pisarz" ], [ 2, "Compare", "running", "Pisarz" ] ],
                 home[:epics].first[:steps].map { |s| s.values_at(:position, :title, :state, :agent) }
    assert_equal [], data[:spaces].last[:epics]
  end

  test "G1, G4: the Director page shows the panel beside the chat; the JSON is the same data; nothing of others" do
    other = create_user(username: "other1")
    other.work_items.create!(title: "Theirs", space: other.spaces.create!(name: "X", kind: "team"))
    get director_path
    assert_select ".director-layout > .chat-app"
    assert_select ".director-layout > .work-panel[data-work-panel][data-url='#{work_director_path}']"
    assert_select ".work-space", 2
    assert_select ".work-epic.is-running .work-epic-head a", text: "Backups"
    assert_select ".work-step.is-running .work-step-title", text: "Compare"
    assert_select ".work-space", text: /Quiet.*Nothing planned or in progress\./m
    assert_select "script[src*=work_panel]"
    assert_select "[style]", 0
    get work_director_path, headers: { "Accept" => "application/json" }
    assert_equal JSON.parse(WorkPanel.for(@user).to_json), response.parsed_body
    assert_no_match "Theirs", response.body
  end
end
