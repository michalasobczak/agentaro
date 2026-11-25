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

  # Fix 2026-11-21: the admin saw the chat on the right and the tasks on the left. Voice mode (spec 020 G5) hid the
  # page chat, the panel slid into the first column and the floating chat opened at the right edge.
  test "G1: chat on the left, work panel on the right, also while voice mode hides the page chat" do
    get director_path
    children = css_select(".director-layout > *").map { |node| node["class"].split.first }
    assert_equal %w[chat-app work-panel step-view], children, "the chat comes first in the layout (spec 038: the step view, hidden, last)"

    css = Rails.root.join("app/assets/stylesheets/application.css").read
    assert_match(/\.director-layout \{[^}]*grid-template-columns: minmax\(0, 1fr\) minmax\(16rem, 24rem\)/, css, "wide chat column first, panel column second")
    assert_match(/^\.director-layout > \.work-panel \{ grid-column: 2; \}/, css, "the panel keeps the right column without the page chat")
    assert_match(/@media \(max-width: 899px\) \{[^@]*\.director-layout > \.work-panel \{ grid-column: auto; \}/, css, "one column on narrow screens")
    dock = css[/body:has\(\.director-layout\) \.chat-dock\.is-voice \.chat-dock-panel \{[^}]*\}/]
    assert dock, "the floating chat in voice mode has its own place on the Director page"
    assert_match(/left: calc\(var\(--sidebar-width, 260px\) \+ var\(--director-side\)\)/, dock, "it starts where the page chat starts")
    assert_match(/right: calc\(var\(--director-side\) \+ 25rem\)/, dock, "it ends before the panel column (24rem + 1rem gap)")
    assert_match(/body:has\(\.director-layout\):has\(\.chat-dock\.is-open\.is-voice\) \.main \{ margin-right: 0; \}/, css)
    # Fix 2026-11-21 (owner: "nie widzę zadań po prawej stronie od czatu, tylko w trybie voice"): a floating chat
    # maximized earlier (the choice is remembered in the browser) covered the panel in voice mode.
    assert_no_match(/body:has\(\.director-layout\)[^{]*is-voice:not\(\.is-max\)/, css, "a maximized floating chat keeps the left column too")
    assert_no_match(/\.work-panel \{[^}]*(\border:|grid-column: 1)/, css, "nothing moves the panel before the chat")
    assert_no_match(/\.director-layout \{[^}]*(direction: rtl|grid-auto-flow: dense|row-reverse)/, css)
  end

  # Owner change (2026-11-23): groups, spaces and epics fold like the groups on the Spaces page; the script does the folding.
  test "groups, spaces and epics have fold arrows, counts and a fold-all pair; the JSON names each group" do
    games = @user.space_groups.create!(name: "Gry", position: 1)
    @home.update!(space_group: games)
    get director_path
    assert_select ".work-panel-head [data-work-fold-all][hidden] button[data-fold-all]", 2
    assert_select ".work-group-box[data-fold-key='g#{games.id}'] .work-group-name", text: "Gry"
    assert_select ".work-group-box[data-fold-key='gnone'] .work-group-name", text: SpaceGroup::UNGROUPED
    assert_select ".work-space[data-fold-key='s#{@home.id}'] > .work-bar [data-work-fold][hidden]"
    assert_select ".work-space[data-fold-key='s#{@home.id}'] .space-count", text: "2"
    assert_select ".work-group-box[data-fold-key='g#{games.id}'] .work-stats .s-running", text: "1 running"
    assert_select ".work-epic[data-fold-key='e#{@running.id}'] > .work-epic-head [data-work-fold]"
    assert_select ".work-epic[data-fold-key='e#{@running.id}'] .work-progress", text: "1/2"
    assert_select ".work-epic[data-fold-key='e#{@running.id}'] > ol.work-steps.work-fold-body"
    assert_select "[style]", 0
    assert_equal [ games.id, nil ], WorkPanel.for(@user)[:groups].map { |g| g[:id] }
    js = Rails.root.join("app/assets/javascripts/work_panel.js").read
    assert_match "agentaro.work.folded", js
    assert_no_match(/innerHTML|insertAdjacentHTML/, js)
  end

  # Owner fix 2026-11-25 (screenshot): a long state such as "retrying at 13:30 (attempt 2 of 5) — passing error" took the
  # whole row of a step and squeezed its title to one letter per line. The row now wraps: the note goes to its own line.
  test "owner fix: a long step state wraps under the title instead of squeezing it" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read
    row = css[/^\.work-step \{[^}]*\}/]
    assert_match(/display: flex; flex-wrap: wrap/, row)
    assert_no_match(/grid-template-columns/, row, "no auto column that grows with the note")
    assert_match(/^\.work-step-title \{ flex: 1 1 10rem; min-width: 0;/, css, "the title keeps room of its own")
    assert_match(/^\.work-step > \.work-state \{ flex: 0 1 auto; margin-left: auto; min-width: 0; overflow-wrap: anywhere;/, css)
  end
end
