require "test_helper"

# Spec 034: recurring orders — schedules (G1), occurrences (G3), plan reuse (G4), the previous result (G5),
# reports (G6), no pile-ups (G7) and the rules R1–R5.
class RecurringOrderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Anna", master_prompt: "You direct.", executor: @executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: @executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @space = @user.spaces.create!(name: "Serwery", kind: "team")
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@dir) }

  def order(**attrs)
    @user.recurring_orders.create!({ space: @space, title: "Przegląd backupów", kind: "weekly", weekdays: "1", at_time: "08:00", starts_on: Date.new(2026, 11, 21) }.merge(attrs))
  end

  def at(*args) = Time.zone.local(*args)

  # --- G1: schedules ------------------------------------------------------------------------------

  test "G1: next occurrences for each kind, in Europe/Warsaw, including month ends and the end date" do
    travel_to at(2026, 11, 21, 12, 0) do # a Saturday
      assert_equal at(2026, 11, 23, 8, 0), order.next_at, "next Monday 08:00"
      assert_equal at(2026, 11, 22, 7, 30), order(kind: "daily", at_time: "07:30").next_at
      assert_equal at(2026, 11, 21, 13, 0), order(kind: "daily", at_time: "13:00").next_at, "later today"
      assert_equal [ at(2026, 11, 26, 9, 0), at(2026, 11, 28, 9, 0), at(2026, 12, 3, 9, 0) ],
                   order(weekdays: "6,4", at_time: "09:00").then { |o| [ o.next_at, o.next_occurrence(after: o.next_at), o.next_occurrence(after: at(2026, 11, 28, 9, 0)) ] }
      monthly = order(kind: "monthly", month_day: 31)
      assert_equal at(2026, 11, 30, 8, 0), monthly.next_at, "the last day in shorter months"
      assert_equal at(2026, 12, 31, 8, 0), monthly.next_occurrence(after: monthly.next_at)
      assert_equal at(2027, 2, 28, 8, 0), monthly.next_occurrence(after: at(2027, 2, 1))
      hourly = order(kind: "hourly", every_hours: 6, at_time: "02:00")
      assert_equal at(2026, 11, 21, 14, 0), hourly.next_at
      assert_equal at(2026, 11, 21, 20, 0), hourly.next_occurrence(after: hourly.next_at)
      assert_nil order(kind: "daily", ends_on: Date.new(2026, 11, 21), at_time: "09:00").next_at, "past its end"
      assert_equal at(2026, 12, 1, 8, 0), order(kind: "daily", starts_on: Date.new(2026, 12, 1)).next_at, "not before the start"
    end
  end

  test "G1: daylight saving time keeps the local hour" do
    travel_to at(2027, 3, 27, 12, 0) do
      o = order(kind: "daily", at_time: "08:00")
      assert_equal [ at(2027, 3, 28, 8, 0), at(2027, 3, 29, 8, 0) ], [ o.next_at, o.next_occurrence(after: o.next_at) ]
      assert_equal 8, o.next_at.in_time_zone.hour
    end
  end

  test "R2: schedules are checked — at least 1 hour apart, a valid time, weekdays, own space; at most 20 active" do
    assert_not @user.recurring_orders.new(space: @space, title: "x", kind: "hourly", every_hours: 0, at_time: "08:00").valid?
    assert_not @user.recurring_orders.new(space: @space, title: "x", kind: "daily", at_time: "25:00").valid?
    assert_not @user.recurring_orders.new(space: @space, title: "x", kind: "weekly", weekdays: "9", at_time: "08:00").valid?
    assert_not @user.recurring_orders.new(space: @space, title: "x", kind: "cron", at_time: "08:00").valid?
    other = create_user(username: "other1").spaces.create!(name: "Theirs", kind: "team")
    assert_not @user.recurring_orders.new(space: other, title: "x", kind: "daily", at_time: "08:00").valid?
    20.times { |i| order(title: "o#{i}") }
    assert_not @user.recurring_orders.new(space: @space, title: "21st", kind: "daily", at_time: "08:00").valid?
    assert @user.recurring_orders.new(space: @space, title: "paused", kind: "daily", at_time: "08:00", state: "paused").valid?
  end

  # --- G3–G7: occurrences --------------------------------------------------------------------------

  def with_agents
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        n=$(cat "#{@dir}/n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "#{@dir}/n"
        printf '%s' "$input" > "#{@dir}/prompt-$n"
        if printf '%s' "$input" | grep -q "Mode: director"; then
          echo '{"summary": "Sprawdź kopie.", "steps": [{"title": "Sprawdź kopie", "description": "x", "agent": #{@writer.id}}]}'
        else
          echo "Kopie OK, run $n"
        fi
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def work
    10.times do
      run = TaskRun.where(state: "queued").order(:id).first or break
      run.purpose == "epic_step" ? StepChain.new(run).perform! : ManagementRunner.new(run).perform!
    end
  end

  def prompts = Dir[File.join(@dir, "prompt-*")].sort_by { |f| f[/\d+\z/].to_i }.map { |f| File.read(f) }

  test "S2, G3, G4, G5: an occurrence becomes an epic that is planned, run and reported; the next one reuses the plan and sees the previous result" do
    o = nil
    travel_to at(2026, 11, 23, 7, 0) do
      o = order
    end
    with_agents do
      travel_to at(2026, 11, 23, 8, 0, 30) do
        assert_equal 1, RecurringOrder.run_due.size
        work
      end
      first = o.work_items.sole
      assert_equal [ "Przegląd backupów — 23.11", "done", @space ], [ first.title, first.state, first.space ]
      assert_match "Done: \"Przegląd backupów — 23.11\"", @user.chat_messages.where(author: "system").last.content
      assert_equal [ "Sprawdź kopie" ], o.reload.last_plan.map { |s| s["title"] }
      assert_equal at(2026, 11, 30, 8, 0), o.next_at
      planning_calls = prompts.count { |p| p.include?("Mode: director") }

      travel_to at(2026, 11, 30, 8, 0, 30) do
        RecurringOrder.run_due
        work
      end
      second = o.work_items.order(:id).last
      assert_equal "done", second.reload.state
      assert_equal planning_calls, prompts.count { |p| p.include?("Mode: director") }, "G4: no planning call for the second occurrence"
      assert_match "What the previous occurrence \"Przegląd backupów — 23.11\" answered last", prompts.last
      assert_match "Kopie OK, run 2", prompts.last
    end
  end

  test "S3, G7: an occurrence due while the previous one still runs is skipped with a note; missed ones collapse into one" do
    o = travel_to(at(2026, 11, 22, 7, 0)) { order(kind: "daily") }
    travel_to at(2026, 11, 22, 8, 1) do
      RecurringOrder.run_due
      assert_equal 1, o.work_items.count
    end
    travel_to at(2026, 11, 23, 8, 1) do
      assert_empty RecurringOrder.run_due
      assert_match "Skipped 23 Nov 08:01: the previous occurrence \"Przegląd backupów — 22.11\" is still new", o.reload.note
    end
    o.work_items.sole.update!(state: "done")
    travel_to at(2026, 11, 27, 9, 0) do # Agentaro was off for days
      assert_equal 1, RecurringOrder.run_due.size
      assert_empty RecurringOrder.run_due, "only one for the missed ones"
      assert_equal at(2026, 11, 28, 8, 0), o.reload.next_at
    end
  end

  test "S4: a paused order creates nothing; resumed, it goes on from the next due time" do
    o = travel_to(at(2026, 11, 22, 7, 0)) { order(kind: "daily") }
    o.update!(state: "paused")
    assert_nil o.next_at
    travel_to(at(2026, 11, 24, 9, 0)) do
      assert_empty RecurringOrder.run_due
      o.update!(state: "active")
      assert_equal at(2026, 11, 25, 8, 0), o.next_at
    end
  end

  test "G6: with \"only when something needs attention\", a quiet occurrence posts nothing in the chat" do
    o = travel_to(at(2026, 11, 23, 7, 0)) { order(report: "attention") }
    with_agents do
      travel_to(at(2026, 11, 23, 8, 1)) { RecurringOrder.run_due; work }
    end
    assert_equal "done", o.work_items.sole.state
    assert_nil @user.chat_messages.where(author: "system").where("content LIKE ?", "Done:%").first
  end

  test "G4: a plan whose agent left the team is planned anew" do
    o = order
    o.update!(last_plan: [ { "title" => "x", "description" => "", "agent" => @writer.id } ])
    assert o.reusable_plan
    @user.team_roles.where(agent: @writer).destroy_all
    assert_nil o.reusable_plan
  end

  test "R4: archiving the space pauses its orders; deleting the space deletes them" do
    o = order
    @space.update!(state: "archived")
    assert_equal [ "paused", "Paused: the space was archived." ], o.reload.values_at(:state, :note)
    @space.purge!(wait: 0)
    assert_not RecurringOrder.exists?(o.id)
  end
end
