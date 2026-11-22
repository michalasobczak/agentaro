require "test_helper"

# Spec 043, G2, G4: the limits on the Executors page and in the chat settings panel; the deputy on the Team page.
class UsageLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @local = Executor.create!(name: "Local", preset: "ollama_api")
    @director = Agent.create!(user: @user, name: "Dyrektor", master_prompt: "x", executor: @claude)
    @spare = Agent.create!(user: @user, name: "Lokalny", master_prompt: "x", executor: @local)
    @user.team_roles.create!(agent: @director, role: "director")
    sign_in(@user)
  end

  test "S1, G2: the Executors page and the chat panel show the windows; a reached limit is marked" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      UsageLimit.record!(@claude, { "windows" => [ { "name" => "five_hour", "used" => 100.0, "resets_at" => Time.zone.local(2026, 11, 22, 15, 10).iso8601, "reached" => true },
                                                   { "name" => "seven_day", "used" => 18.0, "resets_at" => Time.zone.local(2026, 11, 25, 8, 0).iso8601 } ],
                                    "reached" => true, "window" => "five_hour", "resets_at" => Time.zone.local(2026, 11, 22, 15, 10).iso8601 })
      get executors_path
      assert_select "td.usage-limit", text: /usage limit reached until 15:10.*5 h: 100 %, resets 15:10 · 7 days: 18 %, resets 25 Nov 08:00/m
      assert_select "td.usage-limit", text: "—" # the local server has no subscription limit
      get calendar_path
      assert_select ".chat-limit .chat-limit-text", text: /Claude Code: .*usage limit reached until 15:10/m
      assert_select "[style]", 0
    end
  end

  test "G4: the Team page chooses and shows the deputy director" do
    get team_path
    assert_select "input[name='team_role[role]'][value=deputy]"
    post team_roles_path, params: { team_role: { role: "deputy", agent_id: @spare.id } }
    assert_equal "Lokalny is now your deputy director.", flash[:notice]
    get team_path
    assert_select ".org-node .org-role", text: "Deputy director"
    assert_select "button", text: "Change deputy"
  end
end
