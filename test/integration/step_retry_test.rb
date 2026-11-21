require "test_helper"

# Spec 032: a waiting retry on the epic page, the work panel and the director's work list (G4). Spec 040 replaced
# the Team page's switch with a note: the director decides.
class StepRetryPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You write.", executor: executor)
    @item = @user.work_items.create!(title: "Backups", state: "planned", started_at: 5.minutes.ago)
    @step = @item.epic_steps.create!(position: 1, title: "Research", agent: @agent, state: "queued")
    failed = TaskRun.create!(user: @user, work_item: @item, epic_step: @step, agent: @agent, purpose: "epic_step", trigger: "scheduled",
                             occurrence_start: 5.minutes.ago, state: "failed", error: "5-hour limit reached", failure_kind: "usage_limit")
    @retry = TaskRun.create!(user: @user, work_item: @item, epic_step: @step, agent: @agent, purpose: "epic_step", trigger: "retry",
                             occurrence_start: Time.current, state: "queued", attempt: 2, retry_at: Time.zone.parse("2026-11-21 15:02"))
    @failed = failed
    sign_in(@user)
  end

  test "G4: the epic page, the work panel and the director's work list show the waiting retry" do
    travel_to Time.zone.parse("2026-11-21 13:00") do
      get work_item_path(@item)
      assert_select "#step-1 .badge", text: "retrying at 15:02 (attempt 2 of 5) — usage limit"
      assert_select "[style]", 0

      get work_director_path, as: :json
      step = response.parsed_body["spaces"].flat_map { |s| s["epics"] }.find { |e| e["id"] == @item.id }["steps"].first
      assert_equal "retrying at 15:02 (attempt 2 of 5) — usage limit", step["note"]

      lines = ManagementRunner.allocate.send(:step_lines, @item)
      assert_match "retrying at 15:02 (attempt 2 of 5) — usage limit; Agentaro retries it by itself", Array(lines).join("\n")
    end
    travel_to Time.zone.parse("2026-11-21 15:03") do
      assert_nil @step.retry_note, "due: no longer waiting"
    end
  end

  test "spec 040: the Team page says the director decides about failed steps; the switch is gone" do
    get team_path
    assert_select "#failed-steps", text: /your director reads its error and log and decides/
    assert_select "#failed-steps input[name=auto_retry]", 0
  end
end
