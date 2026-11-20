require "test_helper"

# Spec 011: chat actions (G1), checks of every answer (R1, R2, S3), retry, blocking, scheduling of due items (Q4, S1).
# Spec 012: the director plans for its members (G2, G3); old manager and review runs are skipped.
class ManagementRunnerTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    mk = ->(name) { Agent.create!(user: @user, name: name, master_prompt: "You are #{name}.", executor: @executor) }
    @director, @writer = mk.("Dyrektor"), mk.("Pisarz")
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
    @answers = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@answers) }

  # A stand-in "claude": answers with the file named after the mode in its prompt (and a second file on retry).
  def with_management(answers)
    answers.each { |mode, text| File.write(File.join(@answers, mode), text.is_a?(String) ? text : text.to_json) }
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), <<~SH)
        #!/bin/sh
        input=$(cat)
        mode=$(printf '%s' "$input" | sed -n 's/^Mode: //p' | head -1)
        if printf '%s' "$input" | grep -q "previous answer was not accepted" && [ -f "#{@answers}/$mode.retry" ]; then cat "#{@answers}/$mode.retry"; else cat "#{@answers}/$mode"; fi
        printf '%s' "$input" > "#{@answers}/last-$mode-prompt"
      SH
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def run_all
    10.times do
      run = TaskRun.where(state: "queued", purpose: %w[chat director manager review]).order(:id).first or break
      ManagementRunner.new(run).perform!
    end
  end

  def prompt(mode) = File.read(File.join(@answers, "last-#{mode}-prompt"))

  def in_days(days, hour) = (Time.zone.now.to_date + days).in_time_zone.change(hour: hour).strftime("%Y-%m-%dT%H:%M")

  test "S1, S2: a chat message becomes a planned item, end to end" do
    @user.chat_messages.create!(author: "user", content: "Research backups and write a summary by Friday")
    with_management(
      "chat" => { reply: "On it.", actions: [ { type: "add_item", title: "Backup summary", description: "Compare 3 tools", due_on: (Date.current + 10).iso8601, priority: "high" } ] },
      "director" => { summary: "Research then write", steps: [ { title: "Research", description: "Find 3 tools", agent: @writer.id, starts_at: in_days(1, 9), minutes: 60 },
                                                               { title: "Write", description: "One page", agent: @writer.id, starts_at: in_days(1, 11), minutes: 30 } ] }
    ) do
      ManagementRunner.chat!(@user)
      run_all
    end
    item = @user.work_items.sole
    assert_equal [ "Backup summary", "high", "planned", "Research then write" ], [ item.title, item.priority, item.state, item.plan_summary ]
    assert_equal [ "Research", "Write" ], item.tasks.order(:starts_at).pluck(:title)
    assert item.tasks.all? { |t| t.agent == @writer && t.calendar == "private" && t.user == @user }
    messages = @user.chat_messages.ordered.map { |m| [ m.author, m.content ] }
    assert_equal [ "director", "On it." ], messages[1]
    assert_match "Added to the list: Backup summary", @user.chat_messages.where(author: "director").first.actions_summary
    assert_match(/\AResearch then write\n\nPlanned "Backup summary": 2 steps, first on/, messages.last[1])
    assert_match "Member id #{@writer.id}: Pisarz, role: writer", prompt("director")
    assert_match "You are the director. Break the work item into steps", prompt("director")
    assert_equal %w[chat director], TaskRun.where(user: @user).order(:id).pluck(:purpose), "spec 012: one management run per item"
  end

  test "R1, S3: invalid steps change nothing; one retry with the errors, then blocked and told in the chat" do
    item = @user.work_items.create!(title: "Plan a trip")
    outsider = Agent.create!(user: @user, name: "Outsider", master_prompt: "x", executor: @executor)
    bad = { summary: "x", steps: [ { title: "Book", agent: outsider.id, starts_at: in_days(1, 9), minutes: 30 } ] }
    with_management("director" => bad, "director.retry" => { summary: "x", steps: [ { title: "Book", agent: @writer.id, starts_at: "2020-01-01T09:00", minutes: 30 } ] }) do
      run = ManagementRunner.queue!(user: @user, purpose: "director", work_item: item, agent: @director)
      ManagementRunner.new(run).perform!
      assert_match "agent #{outsider.id} is not one of your team members", prompt("director"), "the retry tells the errors"
      assert_equal "failed", run.reload.state
    end
    assert_equal 0, Task.count
    assert_equal "blocked", item.reload.state
    assert_match "starts_at must be in the future", item.blocked_reason
    assert_match "\"Plan a trip\" is blocked", @user.chat_messages.last.content
  end

  test "R2: limits on steps, horizon, due date and handle-from" do
    travel_to Time.zone.parse("2026-11-20 10:00") # the checks are relative to now; a fixed time keeps the test stable
    item = @user.work_items.create!(title: "Limits", due_on: Date.current + 2, handle_from: Time.zone.now + 1.day)
    step = ->(**over) { { title: "S", agent: @writer.id, starts_at: in_days(1, 23), minutes: 30 }.merge(over) }
    runner = ManagementRunner.new(TaskRun.new(user: @user, work_item: item, purpose: "director"))
    check = ->(data) { runner.send(:apply_plan!, data.deep_stringify_keys) rescue $! }
    assert_match "1 to 10 steps", check.({ steps: Array.new(11) { step.() } }).message
    assert_match "within 14 days", check.({ steps: [ step.(starts_at: in_days(20, 9)) ] }).message
    assert_match "ends after the due date", check.({ steps: [ step.(starts_at: in_days(2, 23), minutes: 120) ] }).message
    assert_match "before the handle-from time", check.({ steps: [ step.(starts_at: in_days(0, 23)) ] }).message
    assert_match "minutes must be 1 to 5760", check.({ steps: [ step.(minutes: 0) ] }).message
    assert_equal 0, Task.count
  end

  test "chat actions are checked together: one bad action applies none" do
    @user.chat_messages.create!(author: "user", content: "add two")
    other = WorkItem.create!(user: create_user(username: "bob"), title: "Bob's item")
    answer = { reply: "Done", actions: [ { type: "add_item", title: "Mine" }, { type: "cancel_item", id: other.id } ] }
    with_management("chat" => answer, "chat.retry" => answer) do
      ManagementRunner.chat!(@user)
      run_all
    end
    assert_equal 0, @user.work_items.count, "nothing added"
    assert_equal "new", other.reload.state, "other users' items are not reachable"
    assert_match "No answer from the director", @user.chat_messages.last.content
    assert_match "no item with id #{other.id}", @user.chat_messages.last.content
  end

  test "Q4, S1: items wait for their handle-from time" do
    later = @user.work_items.create!(title: "Later", handle_from: 2.hours.from_now)
    now = @user.work_items.create!(title: "Now")
    assert_equal [ now ], ManagementRunner.dispatch_due.map(&:work_item)
    assert_empty ManagementRunner.dispatch_due, "one management run per item at a time (R3)"
    assert_equal [ later ], ManagementRunner.dispatch_due(now: 3.hours.from_now).map(&:work_item)
  end

  test "the director can ask the user instead of planning" do
    item = @user.work_items.create!(title: "Unclear")
    with_management("director" => { blocked: "Which city?" }) do
      ManagementRunner.dispatch_due
      run_all
    end
    assert_equal [ "blocked", "Which city?" ], [ item.reload.state, item.blocked_reason ]
    assert_equal "About \"Unclear\": Which city?", @user.chat_messages.last.content

    assert_equal 0, Task.count
  end

  test "an unusable director blocks the item and says why" do
    @director.update!(enabled: false)
    item = @user.work_items.create!(title: "X")
    ManagementRunner.dispatch_due
    run_all
    assert_equal "blocked", item.reload.state
    assert_match "not available", item.blocked_reason
  end

  test "cancelling an item removes its steps that have not started" do
    item = @user.work_items.create!(title: "X", state: "planned")
    past = Task.create!(user: @user, title: "Done step", starts_at: 2.hours.ago, ends_at: 1.hour.ago, work_item: item)
    future = Task.create!(user: @user, title: "Next step", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, work_item: item)
    item.cancel!
    assert Task.exists?(past.id)
    assert_not Task.exists?(future.id)
    assert_equal "cancelled", item.reload.state
  end

  test "spec 012: team rules — one director, members once each, agents visible to the user; no managers" do
    assert_not @user.team_roles.new(agent: @writer, role: "director").valid?, "one director"
    assert @user.team_roles.new(agent: @director, role: "member").valid?, "spec 011, Q5: the director may also be a member"
    assert_not @user.team_roles.new(agent: @writer, role: "member").valid?, "a member only once"
    assert_not @user.team_roles.new(agent: @director, role: "manager").valid?, "no managers"
    bobs = Agent.create!(user: create_user(username: "bob"), name: "Bob's", master_prompt: "x", executor: @executor)
    assert_not @user.team_roles.new(agent: bobs, role: "member").valid?
  end

  test "spec 012: a manager or review run left from before is skipped and changes nothing" do
    item = @user.work_items.create!(title: "Old", state: "new")
    run = TaskRun.create!(user: @user, work_item: item, agent: @director, purpose: "manager", trigger: "scheduled", occurrence_start: Time.current)
    ManagementRunner.new(run).perform!
    assert_equal [ "skipped", "Managers were removed (spec 012)." ], [ run.reload.state, run.error ]
    assert_equal "new", item.reload.state
    assert_empty @user.chat_messages
  end

  test "spec 012: only members get steps; the director only when it is a member too" do
    item = @user.work_items.create!(title: "Self")
    runner = ManagementRunner.new(TaskRun.new(user: @user, work_item: item, purpose: "director"))
    plan = { "steps" => [ { "title" => "S", "agent" => @director.id, "starts_at" => in_days(1, 9), "minutes" => 30 } ] }
    assert_match "is not one of your team members", (runner.send(:apply_plan!, plan) rescue $!).message
    @user.team_roles.create!(agent: @director, role: "member", role_text: "editor")
    runner.send(:apply_plan!, plan)
    assert_equal [ @director ], item.tasks.map(&:agent)
    assert_equal "planned", item.reload.state
  end
end

class ManagementRunnerSpacesTest < ActiveSupport::TestCase
  # Spec 013: spaces in the director's chat actions (G4, G6, Q5) and in prompts (G3, S1, S3, S4).
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
  end

  def runner(item: nil, purpose: "chat") = ManagementRunner.new(TaskRun.new(user: @user, work_item: item, purpose: purpose))
  def apply(data) = runner.send(:apply_chat!, data.deep_stringify_keys)
  def try_apply(data) = (apply(data); nil) rescue $!

  test "G6: the director adds a space and its epics in one reply" do
    apply(reply: "OK", actions: [ { type: "add_space", name: "House", goal: "New kitchen" },
                                  { type: "add_item", space: "House", title: "Measure the room" } ])
    space = @user.spaces.sole
    assert_equal [ "House", "New kitchen" ], [ space.name, space.goal ]
    assert_equal [ "Measure the room" ], space.work_items.pluck(:title)
    assert_match "New space: House", @user.chat_messages.last.actions_summary
  end

  test "S3: with several spaces an epic must name one; the only active space or General otherwise" do
    apply(reply: "OK", actions: [ { type: "add_item", title: "First" } ])
    assert_equal "General", @user.work_items.sole.space.name, "no spaces yet: General"
    @user.spaces.create!(name: "Work", goal: "Ship it")
    error = try_apply(reply: "OK", actions: [ { type: "add_item", title: "Second" } ])
    assert_match "\"space\" is required", error.message
    work = @user.spaces.find_by(name: "Work")
    apply(reply: "OK", actions: [ { type: "add_item", space: work.id, title: "Second" } ])
    assert_equal work, @user.work_items.find_by(title: "Second").space
  end

  test "S4, R2: no epics in archived spaces or other users' spaces; only unplanned epics move" do
    archived = @user.spaces.create!(name: "Old", goal: "x", state: "archived")
    assert_match "is archived", try_apply(reply: "OK", actions: [ { type: "add_item", space: archived.id, title: "X" } ]).message
    bobs = create_user(username: "bob").spaces.create!(name: "Bob's", goal: "x")
    assert_match "no space", try_apply(reply: "OK", actions: [ { type: "add_item", space: bobs.id, title: "X" } ]).message

    home, work = @user.spaces.create!(name: "Home", goal: "x"), @user.spaces.create!(name: "Work", goal: "y")
    planned = @user.work_items.create!(title: "Planned", space: home, state: "planned")
    assert_match "only new or blocked", try_apply(reply: "OK", actions: [ { type: "update_item", id: planned.id, space: work.id } ]).message
    fresh = @user.work_items.create!(title: "Fresh", space: home)
    apply(reply: "OK", actions: [ { type: "update_item", id: fresh.id, space: work.id } ])
    assert_equal work, fresh.reload.space

    item = @user.work_items.create!(title: "Waits", space: home)
    home.update!(state: "archived")
    assert_not_includes ManagementRunner.dispatch_due.map(&:work_item), item, "S4: archived spaces are not taken up"
  end

  test "S1, G3: the plan prompt and the step prompt contain their own space only; the chat only names and titles" do
    house = @user.spaces.create!(name: "House", goal: "New kitchen", description: "Budget 20k")
    secret = @user.spaces.create!(name: "Startup", goal: "Raise a seed round", description: "Investor list: confidential")
    epic = @user.work_items.create!(title: "Measure", space: house)
    @user.work_items.create!(title: "Pitch deck", description: "Burn rate 50k", space: secret)

    plan = runner(item: epic, purpose: "director").send(:plan_prompt)
    assert_match "Space goal: New kitchen", plan
    assert_match "Budget 20k", plan
    [ "Startup", "Raise a seed round", "Investor list", "Pitch deck", "Burn rate" ].each { |text| assert_no_match text, plan }

    step = Task.create!(user: @user, title: "Measure", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, agent: @writer, work_item: epic)
    step_prompt = TaskRunner.prompt_for(step, @writer, step.starts_at).user
    assert_match "in the space \"House\" (project space; goal: New kitchen)", step_prompt
    assert_no_match "Startup", step_prompt

    chat = runner.send(:chat_prompt)
    assert_match "\"Startup\" — project space; goal: Raise a seed round", chat
    assert_match "\"Pitch deck\", space #{secret.id}", chat
    [ "Investor list", "Burn rate", "Budget 20k" ].each { |text| assert_no_match text, chat }
  end
end

class SpaceKindsTest < ActiveSupport::TestCase
  # Spec 014: project spaces (goal) and team spaces (no goal) — S1–S3.
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: executor)
    @writer = Agent.create!(user: @user, name: "Pisarz", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @writer, role: "member", role_text: "writer")
  end

  test "S1, R1: a project space needs a goal; a team space has none" do
    assert_not @user.spaces.new(name: "Launch", kind: "project").valid?
    team = @user.spaces.create!(name: "Household", kind: "team", goal: "ignored", description: "Bills, shopping, repairs")
    assert_nil team.goal
    assert_not @user.spaces.new(name: "X", kind: "club", goal: "y").valid?
  end

  test "S3: changing the kind keeps the epics; back to a project needs a goal" do
    space = @user.spaces.create!(name: "Launch", goal: "Ship 1.0")
    epic = @user.work_items.create!(title: "Beta", space: space)
    space.update!(kind: "team", description: "Ongoing releases")
    assert_nil space.reload.goal
    assert_equal [ epic ], space.work_items.to_a
    assert_not space.update(kind: "project")
    assert space.update(kind: "project", goal: "Ship 2.0")
  end

  test "S2, G3: prompts of a team space have no goal; a new General is a team space" do
    team = @user.spaces.create!(name: "Household", kind: "team", description: "Bills and repairs")
    other = @user.spaces.create!(name: "Startup", goal: "Raise a seed round")
    epic = @user.work_items.create!(title: "Pay the bills", space: team)
    plan = ManagementRunner.new(TaskRun.new(user: @user, work_item: epic, purpose: "director")).send(:plan_prompt)
    assert_match "Space: \"Household\" (team space)", plan
    assert_match "Space description: Bills and repairs", plan
    assert_no_match "Space goal", plan
    assert_no_match other.name, plan
    step = Task.create!(user: @user, title: "Pay", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, agent: @writer, work_item: epic)
    assert_match "(team space (no goal); takes care of: Bills and repairs)", TaskRunner.prompt_for(step, @writer, step.starts_at).user

    fresh = create_user(username: "fresh")
    general = fresh.work_items.create!(title: "First").space
    assert_equal [ "General", "team", nil ], [ general.name, general.kind, general.goal ]
  end

  test "G4: the director adds a team space without a goal; a project space without one is refused" do
    runner = ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat"))
    runner.send(:apply_chat!, { "reply" => "OK", "actions" => [ { "type" => "add_space", "kind" => "team", "name" => "Support", "description" => "Answer customers" },
                                                               { "type" => "add_item", "space" => "Support", "title" => "Inbox zero" } ] })
    support = @user.spaces.find_by!(name: "Support")
    assert_equal [ "team", nil, [ "Inbox zero" ] ], [ support.kind, support.goal, support.work_items.pluck(:title) ]
    error = (runner.send(:apply_chat!, { "reply" => "OK", "actions" => [ { "type" => "add_space", "kind" => "project", "name" => "Launch" } ] }) rescue $!)
    assert_match "Goal is required for a project space", error.message
  end
end
