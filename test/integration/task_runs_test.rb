require "test_helper"

# Spec 010: runs on the task page and run page (G6), Run now (G7), permissions (S4), calendar marks (G6, G9).
class TaskRunsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Writer", master_prompt: "You write.", executor: @executor)
    sign_in(@user)
  end

  def t(str) = Time.zone.parse(str)

  def make(**attrs)
    Task.create!({ user: @user, title: "Newsletter", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"), agent: @agent }.merge(attrs))
  end

  test "G7: Run now queues a manual run and shows its page" do
    task = make
    get edit_task_path(task)
    assert_select "form[action='#{task_runs_path(task)}'] button", text: /Run now/
    post task_runs_path(task)
    run = TaskRun.last
    assert_redirected_to task_run_path(run)
    assert_equal [ "manual", "queued", "user:#{@user.id}:alice", t("2026-11-20 09:00") ], [ run.trigger, run.state, run.requested_by, run.occurrence_start ]
    follow_redirect!
    assert_select "meta[http-equiv=refresh]", 0, "owner fix: no <meta refresh>, it outlived Turbo visits"
    assert_select "[data-refresh-url$='/stamp'][data-refresh-every='5']", 1, "refreshes itself while not finished"
  end

  test "Run now on one occurrence of a series" do
    series = make(repeat: "daily", repeat_count: 3)
    second = series.series_starts[1]
    post task_runs_path(series), params: { occurrence: second.iso8601 }
    assert_equal second, TaskRun.last.occurrence_start
  end

  test "G6: a finished run shows the answer, errors and prompt as text" do
    task = make
    run = TaskRun.create!(task: task, occurrence_start: task.starts_at, trigger: "scheduled", state: "succeeded", agent_name: "Writer",
                          executor_name: "Claude", prompt: "You write.\n\n---\n\nYour task", output: "<script>alert(1)</script> Done",
                          started_at: 2.minutes.ago, finished_at: 1.minute.ago)
    get task_run_path(run)
    assert_select "meta[http-equiv=refresh]", 0
    assert_select "[data-refresh-every]", 0, "a finished run stops refreshing"
    assert_select "pre.run-text", text: "<script>alert(1)</script> Done"
    assert_select "script:not([src])", 0
    assert_select "details pre", text: /Your task/
    get edit_task_path(task)
    assert_select ".task-runs a[href='#{task_run_path(run)}']", text: /succeeded/
  end

  test "G6, G9: the calendar marks runs and missed occurrences" do
    ran = travel_to(t("2026-11-19 12:00")) { make }
    missed = travel_to(t("2026-11-19 12:00")) { make(title: "Forgotten", starts_at: t("2026-11-20 11:00"), ends_at: t("2026-11-20 12:00")) }
    TaskRun.create!(task: ran, occurrence_start: ran.starts_at, trigger: "scheduled", state: "succeeded")
    travel_to(t("2026-11-20 15:00")) do
      sign_in(@user)
      get calendar_path(view: "day", date: "2026-11-20")
    end
    assert_select "a.task.run-succeeded", text: /Newsletter/
    assert_select "a.task.run-missed", text: /Forgotten/
  end

  test "S4: runs of other users' private tasks do not exist; read-only users cannot Run now" do
    bob = create_user(username: "bob")
    bobs_agent = Agent.create!(user: bob, name: "Bob's", master_prompt: "x", executor: @executor)
    theirs = Task.create!(user: bob, title: "Secret", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"), agent: bobs_agent)
    run = TaskRun.create!(task: theirs, occurrence_start: theirs.starts_at, trigger: "manual", output: "secret answer")
    get task_run_path(run)
    assert_response :not_found
    post task_runs_path(theirs)
    assert_response :not_found

    admin = create_user(username: "root1", role: "admin")
    shared = Agent.create!(user: admin, kind: "shared", name: "Team", master_prompt: "x", executor: @executor)
    system_task = Task.create!(user: admin, calendar: "system", title: "Office", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00"), agent: shared)
    system_run = TaskRun.create!(task: system_task, occurrence_start: system_task.starts_at, trigger: "scheduled", state: "succeeded", output: "Open")
    get task_run_path(system_run)
    assert_response :success, "system-wide runs are visible to everyone"
    get task_path(system_task)
    assert_select "form[action='#{task_runs_path(system_task)}']", 0
    post task_runs_path(system_task)
    assert_response :forbidden
    assert_equal 1, system_task.runs.count
  end

  test "Run now without an agent asks for one" do
    task = make(agent: nil)
    post task_runs_path(task)
    assert_redirected_to edit_task_path(task)
    assert_equal 0, TaskRun.count
  end
end
