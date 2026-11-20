require "test_helper"

# Spec 013: spaces (G1, G5–G7), the kanban board (Q8–Q10), the calendar depth switch (G9), permissions (S2, S4–S6).
class SpacesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-11-20 10:00")
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: @executor)
    sign_in(@user)
  end

  def make_space(name, user: @user) = user.spaces.create!(name: name, goal: "Goal of #{name}")

  test "G1, G5: create, edit and see spaces; empty ones can be deleted, others only archived" do
    post spaces_path, params: { space: { name: "House", goal: "Renovate the kitchen", description: "<b>budget</b>" } }
    space = @user.spaces.sole
    assert_redirected_to space_path(space)
    post spaces_path, params: { space: { name: "house", goal: "x" } }
    assert_response :unprocessable_content, "names are unique per user"
    patch space_path(space), params: { space: { goal: "Renovate kitchen and bath" } }
    get spaces_path
    assert_select ".space-card", text: /House.*Renovate kitchen and bath/m
    get space_path(space)
    assert_select ".space-about .pre", text: "<b>budget</b>"
    assert_select "[style]", 0
    assert_select "script:not([src])", 0

    @user.work_items.create!(title: "Tiles", space: space)
    delete space_path(space)
    assert_equal "Only an empty space can be deleted. Archive it instead.", flash[:alert]
    patch archive_space_path(space)
    assert_equal "archived", space.reload.state
    patch activate_space_path(space)
    space.work_items.destroy_all
    delete space_path(space)
    assert_not Space.exists?(space.id)
  end

  test "Q8–Q10: the board has a column per state; order is set within a column; Done and Cancel" do
    space = make_space("House")
    a, b, c = %w[A B C].map { |t| @user.work_items.create!(title: t, space: space) }
    planned = @user.work_items.create!(title: "P", space: space, state: "planned")
    step = Task.create!(user: @user, title: "Step", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, agent: @agent, work_item: planned)
    get space_path(space)
    assert_select ".kanban-cards[data-state=new] .kanban-card", 3
    assert_select ".kanban-cards[data-state=planned] .kanban-card", text: /P.*0\/1 steps done/m
    assert_select ".kanban[data-order-url='#{order_space_path(space)}']"

    patch order_space_path(space), params: { ids: [ c.id, a.id, b.id ] }
    assert_response :no_content
    assert_equal [ c, a, b ], space.work_items.where(state: "new").order(:position).to_a
    patch order_space_path(space), params: { ids: [ c.id, planned.id ] }
    assert_response :unprocessable_content, "S6: only within one column"

    post done_work_item_path(a)
    assert_equal "done", a.reload.state
    post cancel_work_item_path(planned)
    assert_equal "cancelled", planned.reload.state
    assert_not Task.exists?(step.id), "steps not started are removed"
    get space_path(space)
    assert_select ".kanban-cancelled", text: /Cancelled \(1\)/
  end

  test "S2, S6: other users' spaces and epics do not exist for me" do
    bob = create_user(username: "bob")
    theirs = make_space("Secret", user: bob)
    item = bob.work_items.create!(title: "Bob's epic", space: theirs)
    [ -> { get space_path(theirs) }, -> { patch archive_space_path(theirs) }, -> { delete space_path(theirs) },
      -> { post done_work_item_path(item) }, -> { post cancel_work_item_path(item) } ].each do |request|
      request.call
      assert_response :not_found
    end
    mine = make_space("Mine")
    patch order_space_path(mine), params: { ids: [ item.id ] }
    assert_response :unprocessable_content
    get spaces_path
    assert_no_match "Secret", response.body
    assert_equal "new", item.reload.state
  end

  test "owner fix: breadcrumbs from spaces down to a step's run" do
    space = make_space("House")
    epic = @user.work_items.create!(title: "Kitchen", space: space, state: "planned")
    step = Task.create!(user: @user, title: "Measure", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, agent: @agent, work_item: epic)
    run = TaskRun.create!(task: step, user: @user, occurrence_start: step.starts_at, trigger: "manual", state: "succeeded")
    get space_path(space)
    assert_select ".breadcrumbs li", 2
    get edit_task_path(step)
    assert_select ".breadcrumbs a", [ "Spaces", "House", "Kitchen" ].size
    assert_select ".breadcrumbs [aria-current=page]", text: "Measure"
    get task_run_path(run)
    assert_select ".breadcrumbs a", 4
    assert_select ".breadcrumbs a[href='#{edit_task_path(step)}']", text: "Measure"
    assert_select ".breadcrumbs [aria-current=page]", text: /Run/
    plain = Task.create!(user: @user, title: "Dentist", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
    get edit_task_path(plain)
    assert_select ".breadcrumbs", 0, "ordinary tasks have none"
  end

  test "spec 016, G8: the calendar shows epics from start to end in the time grid; no depth switch" do
    space = make_space("House")
    done = @user.work_items.create!(title: "Kitchen", space: space, state: "done", started_at: Time.zone.parse("2026-11-23 09:00"), finished_at: Time.zone.parse("2026-11-23 09:40"))
    waiting = @user.work_items.create!(title: "Tiles", space: space, state: "planned", starts_at: Time.zone.parse("2026-11-24 08:00"))
    waiting.epic_steps.create!(position: 1, title: "Measure", agent: @agent)
    legacy = @user.work_items.create!(title: "Old epic", space: space, state: "planned")
    Task.create!(user: @user, title: "Old step", starts_at: Time.zone.parse("2026-11-25 09:00"), ends_at: Time.zone.parse("2026-11-25 10:00"), agent: @agent, work_item: legacy)
    Task.create!(user: @user, title: "Dentist", starts_at: Time.zone.parse("2026-11-24 15:00"), ends_at: Time.zone.parse("2026-11-24 16:00"))

    get calendar_path(view: "week", date: "2026-11-23")
    assert_select ".cal-day .epic-block.e-done[href='#{work_item_path(done)}'].r108", 1, "Monday 9:00 (row 108)"
    assert_select ".cal-day .epic-block.e-planned[href='#{work_item_path(waiting)}'].r96", 1, "a waiting epic is a mark at its start"
    assert_select ".cal-day .epic-block[href='#{work_item_path(legacy)}']", 1, "Q7: an epic from before spans its calendar steps"
    assert_select ".task", { text: /Old step/, count: 1 }, "Q7: old steps stay calendar tasks"
    assert_select ".task", { text: /Measure/, count: 0 }, "new steps are not in the calendar"
    assert_select ".task", text: /Dentist/
    assert_select "nav[aria-label=Depth]", 0, "Q6: no depth switch"
    get calendar_path(view: "month", date: "2026-11-23")
    assert_select ".month-day .epic.chip", 3
  end

  test "spec 014: the form offers both kinds; the list groups spaces by kind" do
    get new_space_path(kind: "team")
    assert_select "input[type=radio][name='space[kind]'][value=team][checked]"
    assert_select ".goal-field textarea[required]", 0, "the goal is checked by the server, per kind"
    post spaces_path, params: { space: { kind: "team", name: "Household", description: "Bills" } }
    assert_redirected_to space_path(@user.spaces.find_by!(name: "Household"))
    post spaces_path, params: { space: { kind: "project", name: "Launch" } }
    assert_response :unprocessable_content
    assert_select ".errors", text: /Goal is required for a project space/
    make_space("House")
    get spaces_path
    assert_select "h2.space-group", [ "Project spaces", "Team spaces" ].size
    assert_select ".space-card.k-team", text: /Household.*team.*Bills/m
    assert_select ".space-card.k-project", text: /House.*project.*Goal of House/m
    get space_path(@user.spaces.find_by!(name: "Household"))
    assert_select ".page-header p", text: "Team space · Bills"
  end

  test "spec 016, G9: the epic page lists steps in order; Try again resumes; the step run has breadcrumbs" do
    space = make_space("House")
    epic = @user.work_items.create!(title: "Kitchen", space: space, state: "blocked", blocked_reason: "Step 2 failed", started_at: 1.hour.ago, finished_at: 30.minutes.ago)
    first = epic.epic_steps.create!(position: 1, title: "Measure", agent: @agent, state: "succeeded")
    epic.epic_steps.create!(position: 2, title: "Order <b>tiles</b>", agent: @agent, state: "failed")
    run = TaskRun.create!(user: @user, work_item: epic, epic_step: first, agent: @agent, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: 1.hour.ago, state: "succeeded", output: "Kitchen is 9 m2")
    get work_item_path(epic)
    assert_select ".epic-steps li.epic-step", 2
    assert_select ".epic-step.s-failed strong", text: "Order <b>tiles</b>"
    assert_select ".epic-step a[href='#{task_run_path(run)}']"
    get task_run_path(run)
    assert_select ".breadcrumbs a", [ "Spaces", "House", "Kitchen" ].size
    assert_select "h1", text: /step 1: Measure/
    get space_path(space)
    assert_select ".kanban-card", text: /1\/2 steps done/

    post retry_work_item_path(epic)
    assert_equal [ "planned", "succeeded", "queued" ], [ epic.reload.state, *epic.epic_steps.reload.map(&:state) ]
    assert_equal 1, TaskRun.where(epic_step: epic.epic_steps.last, state: "queued").count, "resumed from the failed step"
  end

  test "spec 016: other users' epic steps and their runs are not reachable" do
    bob = create_user(username: "bob")
    theirs = bob.work_items.create!(title: "Secret", state: "planned")
    step = theirs.epic_steps.create!(position: 1, title: "Hidden", agent: Agent.create!(user: bob, name: "B", master_prompt: "x", executor: @executor))
    run = TaskRun.create!(user: bob, work_item: theirs, epic_step: step, purpose: "epic_step", trigger: "scheduled", occurrence_start: Time.current, output: "bob's answer")
    get task_run_path(run)
    assert_response :not_found
    post retry_work_item_path(theirs)
    assert_response :not_found
  end

  test "spec 018: the space form takes a working folder; the space and epic pages show it" do
    Dir.mktmpdir do |dir|
      post spaces_path, params: { space: { kind: "project", name: "Code", goal: "Ship", working_dir: dir } }
      space = @user.spaces.find_by!(name: "Code")
      assert_equal File.realpath(dir), space.working_dir
      get space_path(space)
      assert_select ".space-folder code", text: File.realpath(dir)
      epic = @user.work_items.create!(title: "Bug", space: space)
      get work_item_path(epic)
      assert_select "dd code", text: File.realpath(dir)
      patch space_path(space), params: { space: { working_dir: "relative" } }
      assert_response :unprocessable_content
      assert_select ".errors", text: /must be an absolute path/
    end
  end

  test "owner fix after spec 018: folder suggestions as JSON for signed-in users; the form loads the picker" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "project"))
      get folders_spaces_path(path: "#{dir}/pro"), headers: { "Accept" => "application/json" }
      assert_equal [ "#{File.realpath(dir)}/project/" ], JSON.parse(response.body)["folders"]
    end
    get new_space_path
    assert_select ".folder-picker[data-folders-url='#{folders_spaces_path}'] input[role=combobox][autocomplete=off]"
    assert_select "script[src*=folder_picker]"
    delete session_path
    get folders_spaces_path(path: "/")
    assert_response :redirect
  end
end
