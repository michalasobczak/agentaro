require "test_helper"

# Spec 052: the buttons and the page (G2 a, G4, G5), the owner's words (S6), and CI between steps (G2 b).
class SpaceCiTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir("ci-page")
    File.write(File.join(@dir, "agentaro.yml"), "build: echo ok\nserve: python3 -m http.server 1 --bind 127.0.0.1\nurl: http://127.0.0.1:1/\n")
    @user = create_user
    @space = @user.spaces.create!(kind: "project", name: "Gra Słodziaki", goal: "Gra", working_dir: @dir)
    sign_in(@user)
  end

  teardown do
    Ci::Server.stop!(@space.reload) if @space.reload.server_pid
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(Ci::Server.log_path(@space).dirname)
  end

  test "G2 (a), G5: the page shows the file and the buttons; Build queues one run; no inline style" do
    get space_path(@space)
    assert_select "#ci dt", text: "build"
    assert_select "#ci button", text: "Build"
    assert_select "#ci button", text: "Start server"
    assert_select "[style]", 0
    post build_space_path(@space)
    assert_equal 1, @space.ci_runs.where(state: "queued").count
    post build_space_path(@space)
    assert_equal 1, @space.ci_runs.where(state: "queued").count, "one waiting run"
    get spaces_path
    assert_select ".space-ci-line .badge", text: "CI queued"
    get work_director_path, as: :json
    assert_equal "busy", response.parsed_body["spaces"].first["ci"]
  end

  test "G4: Start and Stop on the page; the state is kept" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    post server_space_path(@space, do: "start")
    assert @space.reload.server_wanted
    assert_includes %w[starting up down], @space.server_state
    post server_space_path(@space, do: "stop")
    assert_equal [ false, "stopped" ], [ @space.reload.server_wanted, @space.server_state ]
  end

  test "R3, negative: another user's space cannot be built or served" do
    other = create_user(username: "bob").spaces.create!(kind: "team", name: "Bob", working_dir: @dir)
    post build_space_path(other)
    assert_response :not_found
    post server_space_path(other, do: "start")
    assert_response :not_found
  end

  def apply(text, actions)
    @user.chat_messages.create!(author: "user", content: text)
    ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:apply_chat!, { "reply" => "OK", "actions" => actions })
    @user.chat_messages.last
  end

  test "S6, G5: \"zbuduj Słodziaki\" queues CI; the director sees the state; without such words nothing runs" do
    reply = apply("Zbuduj Słodziaki", [ { "type" => "run_ci", "space" => @space.id } ])
    assert_match "CI queued: Gra Słodziaki", reply.actions_summary
    text = ManagementRunner.new(TaskRun.new(user: @user, purpose: "chat")).send(:spaces_text)
    assert_match "\"Gra Słodziaki\" — project space; goal: Gra [CI queued]", text
    error = (apply("Co słychać?", [ { "type" => "server_action", "space" => @space.id, "do" => "start" } ]); nil) rescue $!
    assert_match "has not asked in their message to build or to run a server", error.message
  end

  test "G2 (b): after a step that changed files, CI is queued before the next step, so it runs between them" do
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    agent = Agent.create!(user: @user, name: "Inżynier", master_prompt: "x", executor: executor)
    item = @user.work_items.create!(title: "Woda", space: @space, state: "planned", started_at: Time.current)
    first = item.epic_steps.create!(position: 1, title: "A", agent: agent, state: "running")
    item.epic_steps.create!(position: 2, title: "B", agent: agent, state: "pending")
    run = TaskRun.create!(user: @user, work_item: item, epic_step: first, agent: agent, purpose: "epic_step", trigger: "scheduled",
                          occurrence_start: Time.current, state: "succeeded", output: "done")
    File.write(File.join(@dir, "game.js"), "new")
    StepChain.after_run(run)
    queued = TaskRun.where(state: "queued").order(:id).pluck(:purpose)
    assert_equal %w[ci epic_step], queued
  end
end
