require "test_helper"

# Spec 013: projects (G1, G5–G7), the kanban board (Q8–Q10), the calendar depth switch (G9), permissions (S2, S4–S6).
class ProjectsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-11-20 10:00")
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: @executor)
    sign_in(@user)
  end

  def make_project(name, user: @user) = user.projects.create!(name: name, goal: "Goal of #{name}")

  test "G1, G5: create, edit and see projects; empty ones can be deleted, others only archived" do
    post projects_path, params: { project: { name: "House", goal: "Renovate the kitchen", description: "<b>budget</b>" } }
    project = @user.projects.sole
    assert_redirected_to project_path(project)
    post projects_path, params: { project: { name: "house", goal: "x" } }
    assert_response :unprocessable_content, "names are unique per user"
    patch project_path(project), params: { project: { goal: "Renovate kitchen and bath" } }
    get projects_path
    assert_select ".project-card", text: /House.*Renovate kitchen and bath/m
    get project_path(project)
    assert_select ".project-about .pre", text: "<b>budget</b>"
    assert_select "[style]", 0
    assert_select "script:not([src])", 0

    @user.work_items.create!(title: "Tiles", project: project)
    delete project_path(project)
    assert_equal "Only an empty project can be deleted. Archive it instead.", flash[:alert]
    patch archive_project_path(project)
    assert_equal "archived", project.reload.state
    patch activate_project_path(project)
    project.work_items.destroy_all
    delete project_path(project)
    assert_not Project.exists?(project.id)
  end

  test "Q8–Q10: the board has a column per state; order is set within a column; Done and Cancel" do
    project = make_project("House")
    a, b, c = %w[A B C].map { |t| @user.work_items.create!(title: t, project: project) }
    planned = @user.work_items.create!(title: "P", project: project, state: "planned")
    step = Task.create!(user: @user, title: "Step", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, agent: @agent, work_item: planned)
    get project_path(project)
    assert_select ".kanban-cards[data-state=new] .kanban-card", 3
    assert_select ".kanban-cards[data-state=planned] .kanban-card", text: /P.*0\/1 steps done/m
    assert_select ".kanban[data-order-url='#{order_project_path(project)}']"

    patch order_project_path(project), params: { ids: [ c.id, a.id, b.id ] }
    assert_response :no_content
    assert_equal [ c, a, b ], project.work_items.where(state: "new").order(:position).to_a
    patch order_project_path(project), params: { ids: [ c.id, planned.id ] }
    assert_response :unprocessable_content, "S6: only within one column"

    post done_work_item_path(a)
    assert_equal "done", a.reload.state
    post cancel_work_item_path(planned)
    assert_equal "cancelled", planned.reload.state
    assert_not Task.exists?(step.id), "steps not started are removed"
    get project_path(project)
    assert_select ".kanban-cancelled", text: /Cancelled \(1\)/
  end

  test "S2, S6: other users' projects and epics do not exist for me" do
    bob = create_user(username: "bob")
    theirs = make_project("Secret", user: bob)
    item = bob.work_items.create!(title: "Bob's epic", project: theirs)
    [ -> { get project_path(theirs) }, -> { patch archive_project_path(theirs) }, -> { delete project_path(theirs) },
      -> { post done_work_item_path(item) }, -> { post cancel_work_item_path(item) } ].each do |request|
      request.call
      assert_response :not_found
    end
    mine = make_project("Mine")
    patch order_project_path(mine), params: { ids: [ item.id ] }
    assert_response :unprocessable_content
    get projects_path
    assert_no_match "Secret", response.body
    get work_items_path(project: theirs.id)
    assert_no_match "Bob's epic", response.body
    assert_equal "new", item.reload.state
  end

  test "the epics list filters by project" do
    house, work = make_project("House"), make_project("Work")
    @user.work_items.create!(title: "Tiles", project: house)
    @user.work_items.create!(title: "Report", project: work)
    get work_items_path(project: house.id)
    assert_select ".row-link", 1
    assert_select ".row-link", text: /Tiles.*House/m
    assert_select ".filter-pills a.active", text: "House"
  end

  test "G9, S5: the calendar shows epics as bars and hides agents' steps unless asked" do
    project = make_project("House")
    epic = @user.work_items.create!(title: "Kitchen", project: project, state: "planned")
    Task.create!(user: @user, title: "Measure", starts_at: Time.zone.parse("2026-11-23 09:00"), ends_at: Time.zone.parse("2026-11-23 10:00"), agent: @agent, work_item: epic)
    Task.create!(user: @user, title: "Order tiles", starts_at: Time.zone.parse("2026-11-25 09:00"), ends_at: Time.zone.parse("2026-11-25 10:00"), agent: @agent, work_item: epic)
    Task.create!(user: @user, title: "Dentist", starts_at: Time.zone.parse("2026-11-24 15:00"), ends_at: Time.zone.parse("2026-11-24 16:00"))

    get calendar_path(view: "week", date: "2026-11-23")
    assert_select ".epic.chip.e-planned[href='#{work_item_path(epic)}']", 3, "one bar piece per day: Monday to Wednesday"
    assert_select ".task", text: /Measure/, count: 0
    assert_select ".task", text: /Dentist/
    get calendar_path(view: "week", date: "2026-11-23", depth: "steps")
    assert_select ".task", text: /Measure/
    assert_select ".epic.chip", 3
    get calendar_path(view: "month", date: "2026-11-23")
    assert_select ".month-day .epic.chip", 3, "the switch is remembered (steps): epics stay in the month view"
    assert_select ".task", text: /Measure/
  end
end
