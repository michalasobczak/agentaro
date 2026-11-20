require "test_helper"

# Spec 023: busy/free on the Team page and in the chat (G3–G5, S1, S2, S4), and agent icons in the chat (G7, S6).
class TeamStatusTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: executor)
    @verifier = Agent.create!(user: @user, name: "Weryfikator", master_prompt: "x", executor: executor)
    @evidence = Agent.create!(user: @user, name: "Evidence Agent", master_prompt: "x", executor: executor)
    @analyst = Agent.create!(user: @user, name: "Market Analyst", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: @director, role: "director")
    @user.team_roles.create!(agent: @verifier, role: "verifier")
    @user.team_roles.create!(agent: @evidence, role: "member", role_text: "evidence")
    @user.team_roles.create!(agent: @analyst, role: "member", role_text: "analyst")
    @epic = @user.work_items.create!(title: "World review", state: "planned", started_at: 10.minutes.ago)
    @steps = [ [ "Find topics", @analyst, "succeeded" ], [ "Collect evidence", @evidence, "running" ], [ "Analyse", @analyst, "pending" ], [ "Summary", @evidence, "pending" ] ]
             .each_with_index.map { |(title, agent, state), i| @epic.epic_steps.create!(position: i + 1, title: title, agent: agent, state: state) }
    @run = TaskRun.create!(user: @user, work_item: @epic, epic_step: @steps[1], agent: @evidence, purpose: "epic_step", trigger: "scheduled",
                           occurrence_start: Time.current, state: "running", started_at: 3.minutes.ago)
    sign_in(@user)
  end

  def json_get(path, **params)
    get path, params: params, headers: { "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  test "S1, G3: the Team page shows busy with the activity and free, with icons; no inline style" do
    get team_path
    assert_select "[data-status-url='#{status_team_path}'][data-status-stamp]"
    assert_select "script[src*='team_status']"
    assert_select ".org-node [data-agent-status='#{@evidence.id}'] .badge.warn", text: "busy"
    assert_select ".org-node [data-agent-status='#{@evidence.id}'] .agent-activity", text: "World review · step 2/4: Collect evidence · for 3 min"
    assert_select ".org-node [data-agent-status='#{@analyst.id}'] .badge", text: "free"
    assert_select ".member-row [data-agent-status='#{@evidence.id}'] .badge", text: "busy"
    assert_select ".org-node.is-director [data-agent-status='#{@director.id}'][hidden]", 1, "R11: the director shows a status only when it runs a step"
    assert_select ".org-node .agent-icon.tone-#{@evidence.id % 8}[aria-hidden='true']", text: "EA"
    assert_select ".org-node.is-director .agent-icon.is-director", text: "D"
    assert_select ".org-node.is-verifier .agent-icon.is-verifier", text: "W"
    assert_select "[data-agent-icon='#{@evidence.id}'] .status-dot.is-busy[title='busy · World review · step 2/4: Collect evidence']"
    assert_select "[style]", 0
    assert_select "script:not([src])", 0
  end

  test "S2, G5, contract: /team/status flips when the step ends and the next one starts" do
    data = json_get(status_team_path)
    evidence = data["agents"].find { |a| a["id"] == @evidence.id }
    assert_equal %w[id name role member status label show_dot activities].sort, evidence.keys.sort
    assert_equal [ "busy", "busy · World review · step 2/4: Collect evidence" ], evidence.values_at("status", "label")
    assert_equal({ "epic_id" => @epic.id, "epic" => "World review", "step" => 2, "of" => 4, "title" => "Collect evidence", "cancelled" => false, "epic_state" => "planned" },
                 evidence["activities"].first.except("started_at"))
    first = data["stamp"]

    @run.update!(state: "succeeded", finished_at: Time.current)
    @steps[1].update!(state: "succeeded")
    @steps[2].update!(state: "running")
    TaskRun.create!(user: @user, work_item: @epic, epic_step: @steps[2], agent: @analyst, purpose: "epic_step", trigger: "scheduled",
                    occurrence_start: Time.current, state: "running", started_at: Time.current)
    data = json_get(status_team_path)
    assert_not_equal first, data["stamp"]
    assert_equal({ @evidence.id => "free", @analyst.id => "busy" }, data["agents"].select { |a| a["member"] }.to_h { |a| [ a["id"], a["status"] ] })
    assert_no_match(/[<>]/, response.body, "no HTML in JSON fields")
  end

  test "S4: the status needs sign-in and shows only my runs" do
    other = create_user(username: "bob")
    theirs = other.work_items.create!(title: "Secret plan", state: "planned", started_at: 1.minute.ago)
    secret = theirs.epic_steps.create!(position: 1, title: "Hidden step", agent: @analyst, state: "running")
    TaskRun.create!(user: other, work_item: theirs, epic_step: secret, agent: @analyst, purpose: "epic_step", trigger: "scheduled",
                    occurrence_start: Time.current, state: "running", started_at: 1.minute.ago)
    data = json_get(status_team_path)
    assert_equal "free", data["agents"].find { |a| a["id"] == @analyst.id }["status"]
    assert_no_match "Secret plan", response.body
    get team_path
    assert_no_match "Secret plan", response.body
    json_get(chat_messages_path, after: 0)
    assert_no_match "Secret plan", response.body

    delete session_path
    get status_team_path, headers: { "Accept" => "application/json" }
    assert_not response.successful?
    assert_no_match "World review", response.body
  end

  test "G4: the chat strip lists the members with icons, status and activity; it folds into a count" do
    get director_path
    assert_select ".content > .chat-app[data-team-stamp] .team-strip[data-team-strip]" do
      assert_select "[data-team-count]", text: "1 of 2 busy"
      assert_select ".team-chip", 2
      assert_select ".team-chip[data-team-agent='#{@evidence.id}'] .agent-icon.is-strip.tone-#{@evidence.id % 8}", text: "EA"
      assert_select ".team-chip[data-team-agent='#{@evidence.id}'] .status-dot.is-busy:not([hidden])"
      assert_select ".team-chip[data-team-agent='#{@evidence.id}'] [data-team-label]", text: "busy · World review · step 2/4: Collect evidence · for 3 min"
      assert_select ".team-chip[data-team-agent='#{@analyst.id}'] .status-dot.is-free"
      assert_select ".team-chip[data-team-agent='#{@analyst.id}'] [data-team-label]", text: "free"
      assert_select ".team-chip[data-team-agent='#{@director.id}']", 0, "members only"
    end
    get team_path # the floating chat on every other page has the strip too
    assert_select ".chat-dock .team-strip .team-chip", 2
    assert_select "[style]", 0
  end

  test "G5, R12: the chat poll carries the stamp, and the statuses only when the stamp changed" do
    data = json_get(chat_messages_path, after: 0)
    stamp = data["team_stamp"]
    assert stamp.present?
    assert_equal [ @evidence.id, @analyst.id, @director.id, @verifier.id ], data["team"].map { |a| a["id"] }
    data = json_get(chat_messages_path, after: 0, team_stamp: stamp)
    assert_nil data["team"], "unchanged: no statuses"
    @run.update!(state: "failed", finished_at: Time.current)
    data = json_get(chat_messages_path, after: 0, team_stamp: stamp)
    assert_not_equal stamp, data["team_stamp"]
    assert_equal "free", data["team"].find { |a| a["id"] == @evidence.id }["status"]
  end

  test "S6, G7, R10: every non-user bubble has its author's icon; user bubbles none; JSON gives the same icon" do
    @user.chat_messages.create!(author: "user", content: "Who is busy?")
    @user.chat_messages.create!(author: "director", content: "Evidence Agent is.")
    @user.chat_messages.create!(author: "director", content: "And Market Analyst is free.")
    @user.chat_messages.create!(author: "verifier", content: "Correct.")
    @user.chat_messages.create!(author: "system", content: "Step finished.")
    get director_path
    assert_select ".content .bubble-row.from-user .agent-icon", 0
    assert_select ".content .bubble-row.from-director > .agent-icon.is-bubble.is-director[aria-hidden='true'][data-agent-icon='#{@director.id}']", count: 2, text: "D"
    assert_select ".content .bubble-row.from-verifier > .agent-icon.is-verifier[data-agent-icon='#{@verifier.id}']", text: "W"
    assert_select ".content .bubble-row.from-system > .agent-icon.is-system", text: "A"
    assert_select ".content .bubble-row.from-system > .agent-icon .status-dot", 0, "Agentaro's notices have no status"
    assert_select ".content .bubble-row.from-director > .agent-icon .status-dot.is-free[hidden]", 2, "R11: the director's dot only while it runs a step"
    assert_select ".content .bubble-row.from-director .bubble-name", text: "Dyrektor"
    assert_select ".content .chat-avatar[data-agent-icon='#{@director.id}']", text: "D"

    messages = json_get(chat_messages_path, after: 0)["messages"]
    icons = messages.map { |m| m.values_at("author", "icon_letter", "icon_kind", "icon_agent") }
    assert_equal [ [ "user", nil, nil, nil ], [ "director", "D", "director", @director.id ], [ "director", "D", "director", @director.id ],
                   [ "verifier", "W", "verifier", @verifier.id ], [ "system", "A", "system", nil ] ], icons
  end

  test "R10: a name that does not start with a letter gets a question mark; tones come from the id" do
    helper = ApplicationController.helpers
    assert_equal "?", helper.agent_initials("42 bot")
    assert_equal "?", helper.agent_initials("")
    assert_equal "Ż", helper.agent_initials("żaba")
    # Owner fix ("wystarczy inicjały, max 2"): the first letters of the first two words.
    assert_equal "DA", helper.agent_initials("Discovery Agent")
    assert_equal "MA", helper.agent_initials("market analyst 2")
    assert_equal "JK", helper.agent_initials("Jan  Kowalski-Nowak")
    assert_equal "tone-#{@analyst.id % 8}", helper.agent_tone(@analyst)
  end

  test "R6, R10: an unassigned agent is omitted and a member without a role description gets a default icon" do
    @user.team_roles.find_by!(agent: @evidence).destroy!
    @user.team_roles.find_by!(agent: @analyst).update!(role_text: nil)
    @analyst.update!(name: "42 bot")

    get director_path
    assert_select ".content [data-team-agent='#{@evidence.id}']", 0
    assert_select ".content [data-team-agent='#{@analyst.id}'] .agent-icon", text: "?"
    data = json_get(status_team_path)
    assert_not_includes data["agents"].map { |a| a["id"] }, @evidence.id
    assert_equal "Member", data["agents"].find { |a| a["id"] == @analyst.id }["role"]
  end

  test "R6: deleting a busy member unassigns its run and removes it from fresh status and chat responses" do
    stamp = json_get(chat_messages_path)["team_stamp"]
    @evidence.destroy!

    assert_nil @run.reload.agent_id
    assert_nil @steps[1].reload.agent_id
    data = json_get(chat_messages_path, team_stamp: stamp)
    assert_not_equal stamp, data["team_stamp"]
    assert_not_includes data["team"].map { |a| a["id"] }, @evidence.id
    get director_path
    assert_select ".content [data-team-agent='#{@evidence.id}']", 0
  end
end
