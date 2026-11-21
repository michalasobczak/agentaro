require "test_helper"

# Spec 030: the trace view on the run page (G7, R4) and deletion of traces with a space (G6, R5, S4).
class RunTracesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Pisarz", master_prompt: "You are a writer.", executor: executor)
    @space = @user.spaces.create!(name: "Old", kind: "team")
    @item = @user.work_items.create!(title: "Backups", space: @space, state: "planned", started_at: 1.hour.ago)
    @step = @item.epic_steps.create!(position: 1, title: "Find tools", agent: @agent, state: "succeeded")
    @run = TaskRun.create!(user: @user, work_item: @item, epic_step: @step, agent: @agent, purpose: "epic_step", trigger: "manual",
                           occurrence_start: Time.current, state: "succeeded", output: "Done.")
    prompt = AgentCall::Prompt.new(system: "You are a writer.", sections: [ [ "task", "Your task: Find tools <b>now</b>" ] ])
    @call = RunTrace.record(run: @run, agent: @agent, prompt: prompt, outcome: AgentCall::Outcome.new("succeeded", "Done.", nil, 0), pass: nil,
                            started_at: Time.current, duration: 2.5, model: "sonnet", effort: nil,
                            usage: { input_tokens: 1500, output_tokens: 40, cost_usd: 0.01, turns: 2 },
                            events: [ { "kind" => "tool_use", "name" => "WebFetch", "input" => "{\"url\":\"https://example.com\"}" },
                                      { "kind" => "tool_result", "name" => "WebFetch", "source" => "web", "content" => "<script>x</script>" } ])
  end

  test "G7: the run page shows each call with its numbers, parts and events, escaped and desktop-only" do
    sign_in(@user)
    get task_run_path(@run)
    assert_response :success
    assert_select ".run-trace.desktop-only .trace-call summary", text: /Call 1 · epic_step.*succeeded · sonnet · 1,500 in \/ 40 out tokens · \$0\.0100 · 2\.5 s · 2 turns/m
    assert_select ".trace-parts .badge", text: "master prompt"
    assert_select ".trace-parts .badge", text: "task"
    assert_select ".trace-events li", 2
    assert_select ".trace-events summary", text: /WebFetch.*from web/m
    assert_includes response.body, "&lt;script&gt;x&lt;/script&gt;"
    assert_includes response.body, "Find tools &lt;b&gt;now&lt;/b&gt;"
    assert_select ".mobile-note"
    assert_select "[style]", 0
  end

  test "R4: another user's run and its trace are not shown" do
    other = create_user(username: "other1")
    sign_in(other)
    get task_run_path(@run)
    assert_response :not_found
  end

  test "S4, R5: deleting the space deletes its traces and the text only they used" do
    shared = TracePart.find_by!(content: "You are a writer.")
    kept_run = TaskRun.create!(user: @user, purpose: "chat", agent: @agent, trigger: "manual", occurrence_start: Time.current, state: "succeeded")
    RunTrace.record(run: kept_run, agent: @agent, prompt: AgentCall::Prompt.new("You are a writer.", "Chat"), outcome: AgentCall::Outcome.new("succeeded", "Hi", nil, 0),
                    pass: nil, started_at: Time.current, duration: 1, model: nil, effort: nil)
    @space.update!(state: "archived")
    @space.purge!(wait: 0)
    assert_not ModelCall.exists?(@call.id)
    assert_nil TracePart.find_by(content: "Your task: Find tools <b>now</b>")
    assert TracePart.exists?(shared.id), "a part another run still uses stays"
    assert_equal [ kept_run.id ], ModelCall.pluck(:task_run_id)
  end
end
