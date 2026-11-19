require "test_helper"

# Spec 007: task rules (R1), recurrence (G4, R3, Q3), exceptions and series edits (R4), visibility (Q2, Q2a).
class TaskTest < ActiveSupport::TestCase
  setup { @user = create_user }

  def t(str) = Time.zone.parse(str)

  def task(**attrs)
    Task.new({ user: @user, title: "Task", starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-20 10:00") }.merge(attrs))
  end

  test "S2: duration from 1 minute to 4 days" do
    assert task(ends_at: t("2026-11-20 09:01")).valid?
    assert task(ends_at: t("2026-11-24 09:00")).valid?, "exactly 4 days"
    assert_not task(ends_at: t("2026-11-20 09:00:30")).valid?
    assert_not task(ends_at: t("2026-11-24 09:01")).valid?
    assert_not task(ends_at: t("2026-11-20 08:00")).valid?
  end

  test "all-day tasks start and end at midnight and last 1 to 4 days" do
    assert task(all_day: true, starts_at: t("2026-11-20 00:00"), ends_at: t("2026-11-21 00:00")).valid?
    assert task(all_day: true, starts_at: t("2026-11-20 00:00"), ends_at: t("2026-11-24 00:00")).valid?
    assert_not task(all_day: true, starts_at: t("2026-11-20 00:00"), ends_at: t("2026-11-25 00:00")).valid?
    assert_not task(all_day: true, starts_at: t("2026-11-20 09:00"), ends_at: t("2026-11-21 09:00")).valid?
  end

  test "title required; length limits" do
    assert_not task(title: " ").valid?
    assert_not task(title: "x" * 201).valid?
    assert_not task(description: "x" * 5001).valid?
  end

  test "daily, every 2 days, until a date" do
    series = task(repeat: "daily", repeat_interval: 2, repeat_until: Date.new(2026, 11, 26))
    assert series.valid?, series.errors.full_messages.to_sentence
    assert_equal %w[2026-11-20 2026-11-22 2026-11-24 2026-11-26], series.series_starts.map { |s| s.to_date.iso8601 }
  end

  test "weekly on chosen weekdays, a number of times" do
    series = task(repeat: "weekly", weekdays: [ 1, 5 ], repeat_count: 4) # Fri 20 Nov start
    assert series.valid?
    assert_equal [ "Fri 20", "Mon 23", "Fri 27", "Mon 30" ], series.series_starts.map { |s| s.strftime("%a %d") }
  end

  test "monthly on the same day skips months without that day" do
    series = task(starts_at: t("2026-12-31 10:00"), ends_at: t("2026-12-31 11:00"), repeat: "monthly", repeat_count: 3)
    assert series.valid?, series.errors.full_messages.to_sentence
    assert_equal %w[2026-12-31 2027-01-31 2027-03-31], series.series_starts.map { |s| s.to_date.iso8601 }
  end

  test "Q3: a series lasts at most 3 months and must end" do
    assert_not task(repeat: "daily").valid?, "no end"
    assert_not task(repeat: "daily", repeat_until: Date.new(2027, 2, 21)).valid?
    assert task(repeat: "daily", repeat_until: Date.new(2027, 2, 20)).valid?
    assert_not task(repeat: "daily", repeat_count: 100).valid?
    assert task(repeat: "daily", repeat_count: 90).valid?
  end

  test "S3: occurrences appear only on matching days, also across daylight-saving time" do
    series = task(starts_at: t("2027-03-26 09:00"), ends_at: t("2027-03-26 09:30"), repeat: "daily", repeat_count: 4)
    assert series.valid?
    assert_equal [ "09:00" ] * 4, series.series_starts.map { |s| s.strftime("%H:%M") }, "Europe/Warsaw switches to summer time on 28 March"
    range = t("2027-03-27 00:00")...t("2027-03-28 00:00")
    assert_equal 1, series.occurrences(range).size
  end

  test "visibility: private for the author, system-wide for everyone; only admins change system tasks" do
    other = create_user(username: "bob")
    admin = create_user(username: "root1", role: "admin")
    private_task = task.tap(&:save!)
    system_task = task(user: admin, calendar: "system").tap(&:save!)
    assert_equal [ private_task, system_task ].sort_by(&:id), Task.visible_to(@user).order(:id).to_a
    assert_equal [ system_task ], Task.visible_to(other).to_a
    assert private_task.editable_by?(@user)
    assert_not private_task.editable_by?(other)
    assert_not system_task.editable_by?(@user)
    assert system_task.editable_by?(admin)
  end

  test "R4: changing one occurrence detaches it; the series skips that day" do
    series = task(repeat: "daily", repeat_count: 3).tap(&:save!)
    second = series.series_starts[1]
    result = TaskEditor.new(series, occurrence_start: second).move(starts_at: second + 2.hours, ends_at: second + 3.hours, scope: "this")
    assert result.ok
    assert_equal "none", result.task.repeat
    assert_equal second + 2.hours, result.task.starts_at
    assert_equal 2, series.reload.occurrence_starts.size
  end

  test "R4: changing the whole series shifts every occurrence and the weekdays" do
    series = task(repeat: "weekly", weekdays: [ 1, 5 ], repeat_count: 4).tap(&:save!) # Fri, Mon, Fri, Mon
    first = series.series_starts.first
    result = TaskEditor.new(series, occurrence_start: first).move(starts_at: first + 1.day + 1.hour, ends_at: first + 1.day + 2.hours, scope: "series")
    assert result.ok, result.errors.to_sentence
    assert_equal [ 2, 6 ], series.reload.weekdays
    assert_equal [ "Sat 21 10:00", "Tue 24 10:00", "Sat 28 10:00", "Tue 01 10:00" ], series.occurrence_starts.map { |s| s.strftime("%a %d %H:%M") }
  end

  test "deleting one occurrence or the whole series" do
    series = task(repeat: "daily", repeat_count: 2).tap(&:save!)
    TaskEditor.new(series, occurrence_start: series.series_starts.first).destroy(scope: "this")
    assert_equal 1, series.reload.occurrence_starts.size
    TaskEditor.new(series, occurrence_start: series.occurrence_starts.first).destroy(scope: "this")
    assert_not Task.exists?(series.id), "a series without occurrences is removed"
  end

  test "Q6: duplicate goes to the same time next day, as a one-time task" do
    series = task(repeat: "daily", repeat_count: 2).tap(&:save!)
    copy = TaskEditor.new(series, occurrence_start: series.series_starts.last).duplicate(calendar: "private").task
    assert_equal series.series_starts.last + 1.day, copy.starts_at
    assert_equal "none", copy.repeat
    assert_equal 1.hour, copy.duration
  end

  test "occurrence expansion is bounded by the 3-month limit" do
    daily = task(repeat: "daily", repeat_until: Date.new(2027, 2, 20))
    weekly = task(repeat: "weekly", weekdays: (1..7).to_a, repeat_until: Date.new(2027, 2, 20))
    assert_operator daily.series_starts.size, :<=, 93
    assert_operator weekly.series_starts.size, :<=, 93
    leap = task(starts_at: t("2028-02-29 09:00"), ends_at: t("2028-02-29 10:00"), repeat: "monthly", repeat_interval: 12, repeat_count: 1)
    assert_equal 1, leap.series_starts.size, "a rare day ends quickly instead of looping"
  end
end
