require "test_helper"

# Spec 038: the step view's endpoint — own steps of the current plan only (R1, S5), an epic followed (G4) — and the
# Director page: clickable steps and epics, the view's place, first-party script, no inline style (R8).
class StepViewPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @space = @user.spaces.create!(name: "Gra", kind: "team")
    @item = @user.work_items.create!(title: "MVP <i>gry</i>", space: @space, state: "planned", started_at: 2.minutes.ago)
    @done = @item.epic_steps.create!(position: 1, title: "Plan", agent: @writer, state: "succeeded")
    @running = @item.epic_steps.create!(position: 2, title: "Build <b>it</b>", agent: @writer, state: "running")
    @run = TaskRun.create!(user: @user, purpose: "epic_step", work_item: @item, epic_step: @running, agent: @writer, trigger: "scheduled",
                           occurrence_start: Time.current, state: "running", started_at: 1.minute.ago, preset: "claude_code")
    sign_in(@user)
  end

  teardown { FileUtils.rm_rf(LiveLog.dir_for(@run.id)) }

  test "G1, R8: the work panel's steps and epics open the view; the view and its script are on the page; no inline style" do
    get director_path
    assert_select "[data-work-panel] a[data-live-epic='#{@item.id}']"
    assert_select "[data-work-panel] li[data-live-step='#{@running.id}'][role=button][tabindex='0']"
    assert_select "aside.step-view[data-step-view][hidden][data-url='#{live_director_path}']"
    assert_select "script[src*='step_view']"
    assert_select "[style]", 0
    get work_director_path, as: :json
    assert_equal [ @done.id, @running.id ], response.parsed_body["spaces"].first["epics"].first["steps"].map { |s| s["id"] }
  end

  test "G2, G4: a step's view and an epic followed — the running step, its live log, titles as plain JSON text" do
    LiveLog.new(LiveLog.dir_for(@run.id).tap { |d| FileUtils.mkdir_p(d) }).add("kind" => "tool_use", "name" => "Bash", "input" => { command: "npm test" }.to_json)
    get live_director_path(step: @running.id), as: :json
    body = response.parsed_body
    assert_equal [ "Build <b>it</b>", "running", true, "log", false ], [ body.dig("step", "title"), body.dig("step", "state"), body["running"], body["stream"], body["following"] ]
    assert_equal [ { "kind" => "action", "label" => "Bash", "text" => "npm test" } ], body["entries"]

    get live_director_path(epic: @item.id), as: :json
    assert_equal [ @running.id, true ], [ response.parsed_body.dig("step", "id"), response.parsed_body["following"] ]
  end

  test "R1, S5: another account's step or epic, and a step of a retired plan, are not found" do
    other = create_user(username: "other1")
    space = other.spaces.create!(name: "X", kind: "team")
    theirs = other.work_items.create!(title: "Theirs", space: space, state: "planned")
    step = theirs.epic_steps.create!(position: 1, title: "Secret", agent: Agent.create!(user: other, name: "B", master_prompt: "x", executor: @writer.executor))
    get live_director_path(step: step.id), as: :json
    assert_response :not_found
    get live_director_path(epic: theirs.id), as: :json
    assert_response :not_found

    @item.update_columns(active_step_from: 2)
    get live_director_path(step: @done.id), as: :json
    assert_response :not_found
  end
end
