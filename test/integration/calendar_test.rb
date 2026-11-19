require "test_helper"

# Spec 007: views (S1), forms (G5), JSON actions used by the calendar script (G6), permissions (S5).
class CalendarTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in(@user)
  end

  def t(str) = Time.zone.parse(str)

  def make(**attrs)
    Task.create!({ user: @user, title: "Dentist", location: "Old Town", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00") }.merge(attrs))
  end

  def json(method, path, params)
    send(method, path, params: params.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" })
    JSON.parse(response.body)
  end

  test "S1: the views show the right days" do
    get calendar_path(view: "4days", date: "2026-11-20") # Friday
    assert_select ".cal-head .day-head", 4
    assert_select ".cal-head .day-head .dow", text: "Mon"
    assert_select ".cal-day[data-date='2026-11-23']"
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select ".cal-day", 7
    assert_select ".cal-day[data-date='2026-11-16']" # Monday
    assert_select ".cal-day[data-date='2026-11-22']" # Sunday
    get calendar_path(view: "day", date: "2026-11-20")
    assert_select ".cal-day", 1
    get calendar_path(view: "month", date: "2026-11-20")
    assert_select ".month-day", 42 # Mon 26 Oct – Sun 6 Dec: November 2026 spans six weeks
  end

  test "tasks appear in time grid and month, placed by classes (no inline styles)" do
    make
    make(title: "Trip", all_day: true, starts_at: t("2026-11-21 00:00"), ends_at: t("2026-11-23 00:00"))
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select ".cal-day[data-date='2026-11-20'] a.task.r108.h12", text: /Dentist/ # 09:00 = row 108, 1 h = 12 rows
    assert_select ".allday-cell[data-date='2026-11-21'] a.task", text: /Trip/
    assert_select ".allday-cell[data-date='2026-11-22'] a.task", text: /Trip/
    assert_select "[style]", 0
    get calendar_path(view: "month", date: "2026-11-20")
    assert_select ".month-day[data-date='2026-11-20'] a.task", text: /Dentist/
  end

  test "overlapping tasks are placed side by side" do
    make
    make(title: "Call", starts_at: t("2026-11-20 09:30"), ends_at: t("2026-11-20 10:30"))
    get calendar_path(view: "day", date: "2026-11-20")
    assert_select "a.task.c1.w30", text: /Dentist/
    assert_select "a.task.c31.w30", text: /Call/
  end

  test "create, edit and delete through the forms" do
    post tasks_path, params: { task: { title: "Gym", location: "Club", start_date: "2026-11-20", start_time: "18:00", end_date: "2026-11-20", end_time: "19:15", repeat: "none" } }
    task = Task.last
    assert_equal [ "Gym", t("2026-11-20 18:00"), 75.minutes ], [ task.title, task.starts_at, task.duration ]
    assert_redirected_to calendar_path(date: "2026-11-20")

    patch task_path(task), params: { task: { title: "Gym!", start_date: "2026-11-20", start_time: "18:00", end_date: "2026-11-20", end_time: "18:01" } }
    assert_equal [ "Gym!", 1.minute ], [ task.reload.title, task.duration ]

    post tasks_path, params: { task: { title: "Too long", start_date: "2026-11-20", start_time: "18:00", end_date: "2026-11-25", end_time: "18:00" } }
    assert_response :unprocessable_content
    assert_match "at most 4 days", response.body

    delete task_path(task)
    assert_not Task.exists?(task.id)
  end

  test "create a weekly series and an all-day task through the form" do
    post tasks_path, params: { task: { title: "Standup", start_date: "2026-11-23", start_time: "09:00", end_date: "2026-11-23", end_time: "09:15",
                                       repeat: "weekly", repeat_interval: "1", weekdays: %w[1 3 5], repeat_ends: "until", repeat_until: "2026-12-04" } }
    series = Task.find_by!(title: "Standup")
    assert_equal 6, series.series_starts.size
    post tasks_path, params: { task: { title: "Trip", all_day: "1", start_date: "2026-11-27", end_date: "2026-11-29" } }
    trip = Task.find_by!(title: "Trip")
    assert_equal [ t("2026-11-27 00:00"), t("2026-11-30 00:00") ], [ trip.starts_at, trip.ends_at ]
  end

  test "G6: move and resize as JSON" do
    task = make
    result = json(:patch, move_task_path(task), starts_at: "2026-11-21T14:00", ends_at: "2026-11-21T14:30", scope: "this")
    assert result["ok"]
    assert_equal [ t("2026-11-21 14:00"), 30.minutes ], [ task.reload.starts_at, task.duration ]
    result = json(:patch, move_task_path(task), starts_at: "2026-11-21T14:00", ends_at: "2026-11-26T14:00", scope: "this")
    assert_not result["ok"]
    assert_response :unprocessable_content
    assert_match "4 days", result["errors"].join
  end

  test "G6: copy (paste), duplicate, and moving one occurrence of a series" do
    task = make
    json(:post, copy_task_path(task), starts_at: "2026-11-22T11:00")
    assert Task.exists?(title: "Dentist", starts_at: t("2026-11-22 11:00"), ends_at: t("2026-11-22 12:00"))
    json(:post, duplicate_task_path(task), {})
    assert Task.exists?(title: "Dentist", starts_at: t("2026-11-21 09:00"))

    series = make(title: "Pills", repeat: "daily", repeat_count: 3)
    second = series.series_starts[1]
    json(:patch, move_task_path(series), occurrence: second.iso8601, starts_at: "2026-11-21T20:00", ends_at: "2026-11-21T21:00", scope: "this")
    assert_equal 2, series.reload.occurrence_starts.size
    assert Task.exists?(title: "Pills", starts_at: t("2026-11-21 20:00"), repeat: "none")
  end

  test "editing an occurrence offers this-one or whole-series" do
    series = make(repeat: "daily", repeat_count: 3)
    get edit_task_path(series, occurrence: series.series_starts[1].iso8601)
    assert_select "input[name=scope][value=this]"
    assert_select "input[name=scope][value=series]"
    assert_select "input[name='task[start_date]'][value='2026-11-21']"
  end

  test "S5: other users' private tasks do not exist for me" do
    theirs = Task.create!(user: create_user(username: "bob"), title: "Secret", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"))
    get calendar_path(view: "week", date: "2026-11-20")
    assert_no_match "Secret", response.body
    get edit_task_path(theirs)
    assert_response :not_found
    json(:patch, move_task_path(theirs), starts_at: "2026-11-21T09:00", ends_at: "2026-11-21T10:00")
    assert_response :not_found
    assert_equal t("2026-11-20 09:00"), theirs.reload.starts_at
  end

  test "Q2a: system-wide tasks are visible to all, changed only by admins" do
    admin = create_user(username: "root1", role: "admin")
    system_task = Task.create!(user: admin, calendar: "system", title: "Office closed", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 17:00"))
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select "a.task.t-system.is-readonly", text: /Office closed/
    get edit_task_path(system_task)
    assert_response :forbidden
    json(:patch, move_task_path(system_task), starts_at: "2026-11-21T09:00", ends_at: "2026-11-21T10:00")
    assert_response :forbidden
    get task_path(system_task)
    assert_response :success
    post tasks_path, params: { task: { title: "Sneaky", calendar: "system", start_date: "2026-11-20", start_time: "10:00", end_date: "2026-11-20", end_time: "11:00" } }
    assert_equal "private", Task.find_by!(title: "Sneaky").calendar, "regular users cannot create system-wide tasks"

    sign_in(admin)
    json(:patch, move_task_path(system_task), starts_at: "2026-11-21T09:00", ends_at: "2026-11-21T17:00")
    assert_equal t("2026-11-21 09:00"), system_task.reload.starts_at
  end

  test "return_to accepts only calendar paths (no open redirect)" do
    post tasks_path, params: { return_to: "https://evil.example/", task: { title: "A", start_date: "2026-11-20", start_time: "10:00", end_date: "2026-11-20", end_time: "11:00" } }
    assert_redirected_to calendar_path(date: "2026-11-20")
    post tasks_path, params: { return_to: "/calendar?view=day&date=2026-11-20", task: { title: "B", start_date: "2026-11-20", start_time: "10:00", end_date: "2026-11-20", end_time: "11:00" } }
    assert_redirected_to "/calendar?view=day&date=2026-11-20"
  end

  test "changes are recorded in the data changelog" do
    task = make
    json(:patch, move_task_path(task), starts_at: "2026-11-21T14:00", ends_at: "2026-11-21T15:00", scope: "this")
    change = DataChange.where(record_type: "Task", record_id: task.id, action: "update").last
    assert_equal "user:#{@user.id}:alice", change.actor
    assert change.changes_hash.key?("starts_at")
  end

  test "the JSON endpoints used by the script require the CSRF token" do
    task = make
    ActionController::Base.allow_forgery_protection = true
    patch move_task_path(task), params: { starts_at: "2026-11-21T09:00", ends_at: "2026-11-21T10:00" }.to_json,
                                headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :unprocessable_content
    assert_equal t("2026-11-20 09:00"), task.reload.starts_at
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "adding a task happens in a popup on the calendar (owner correction)" do
    get calendar_path(view: "week", date: "2026-11-20")
    assert_select "dialog#task-dialog form#new-task-form[action='#{tasks_path}']"
    assert_select "dialog#task-dialog input[name='task[title]']"
    assert_select "dialog#task-dialog [data-errors][hidden]"
    assert_select "a[data-new-task][href^='#{new_task_path}']", 1, "the page form stays as a fallback"
  end

  test "the popup creates tasks as JSON and gets validation errors back" do
    post tasks_path, params: { task: { title: "Popup task", start_date: "2026-11-20", start_time: "15:00", end_date: "2026-11-20", end_time: "15:30" } },
                     headers: { "Accept" => "application/json" }
    assert_response :success
    assert JSON.parse(response.body)["ok"]
    assert Task.exists?(title: "Popup task", starts_at: t("2026-11-20 15:00"))

    post tasks_path, params: { task: { title: "", start_date: "2026-11-20", start_time: "15:00", end_date: "2026-11-20", end_time: "15:00" } },
                     headers: { "Accept" => "application/json" }
    assert_response :unprocessable_content
    errors = JSON.parse(response.body)["errors"].join(" ")
    assert_match "Title can't be blank", errors
    assert_match "End must be after the start", errors
  end
end
