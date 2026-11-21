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
    assert_equal %w[chat-app work-panel], children, "the chat comes first in the layout"

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
end
