require "test_helper"

# Spec 022: forms with the model picker (G2), Refresh models (G3), Check model and who may use it (G4, R4).
class ModelChecksTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @other = create_user(username: "other1")
    @admin = create_user(username: "root1", role: "admin")
    @executor = Executor.create!(name: "Claude", preset: "claude_code", extra_models: "claude-opus-4-1")
    @agent = Agent.create!(user: @user, name: "Helper", master_prompt: "You help.", executor: @executor, model: "sonnet")
  end

  def with_fake_claude(script = "cat > /dev/null; echo ok")
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "claude"), "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, File.join(dir, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{dir}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def check(**body) = post(model_checks_path, params: body, as: :json)

  test "G2: the agent form carries the executor's choices for the picker, with effort and Check model" do
    sign_in(@user)
    get edit_agent_path(@agent)
    assert_response :success
    lists = JSON.parse(css_select("[data-model-picker]").first["data-lists"])
    assert_equal %w[opus sonnet haiku claude-opus-4-1], lists[@executor.id.to_s]["models"].map { |m| m["name"] }
    assert_equal Executor::EFFORTS["claude_code"], lists[@executor.id.to_s]["efforts"]
    assert_select "input#agent_model[value=sonnet]", 1, "without JavaScript the text field still works"
    assert_select "select#agent_effort"
    assert_select "[data-model-check]"
    assert_select "script[src*=model_picker]"
  end

  test "G5: effort is saved from the form; one the tool does not take is refused" do
    sign_in(@user)
    patch agent_path(@agent), params: { agent: { effort: "high" } }
    assert_equal "high", @agent.reload.effort
    patch agent_path(@agent), params: { agent: { effort: "ultra", model: "-x" } }
    assert_response :unprocessable_content
    assert_equal [ "high", "sonnet" ], [ @agent.reload.effort, @agent.model ]
  end

  test "G4: the agent's owner checks the model in the form; the result is kept on the agent" do
    sign_in(@user)
    with_fake_claude { check(agent_id: @agent.id, executor_id: @executor.id, model: "haiku", effort: "low") }
    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    assert_match "haiku, effort low: answered", body["output"]
    assert @agent.reload.model_check_ok
    assert_equal "sonnet", @agent.model, "a check does not save the form"
  end

  test "G4: a new agent can be checked on an enabled executor; the executor's default is used when the field is empty" do
    @executor.update!(default_model: "opus")
    sign_in(@user)
    with_fake_claude { check(executor_id: @executor.id, model: "") }
    assert_match "opus: answered", response.parsed_body["output"]
    @executor.update!(enabled: false)
    check(executor_id: @executor.id, model: "opus")
    assert_response :forbidden
  end

  test "R4: no checks of someone else's agent, and only admins check an executor's default" do
    sign_in(@other)
    check(agent_id: @agent.id, model: "opus")
    assert_response :not_found
    check(executor_target: @executor.id, model: "opus")
    assert_response :forbidden
    shared = Agent.create!(user: @admin, kind: "shared", name: "Shared", master_prompt: "x", executor: @executor)
    check(agent_id: shared.id, model: "opus")
    assert_response :forbidden
  end

  test "R1: a name that looks like an option is never run" do
    sign_in(@user)
    with_fake_claude("echo should-not-run") { check(agent_id: @agent.id, model: "--dangerously-skip-permissions") }
    assert_not response.parsed_body["ok"]
    assert_match "must not start with -", response.parsed_body["output"]
  end

  test "F-022-1: one check at a time, so checks never take all of the server's threads" do
    sign_in(@user)
    ModelChecksController::RUNNING.synchronize do
      with_fake_claude("echo should-not-run") { check(executor_id: @executor.id, model: "opus") }
    end
    assert_response :conflict
    assert_match "Another check is running", response.parsed_body["output"]
  end

  test "G3, G4: admins refresh the list and check the executor's default on its page" do
    sign_in(@admin)
    get edit_admin_executor_path(@executor)
    assert_response :success
    assert_select "textarea#executor_extra_models"
    assert_select "form[action=?]", refresh_models_admin_executor_path(@executor)
    post refresh_models_admin_executor_path(@executor)
    assert_redirected_to edit_admin_executor_path(@executor)
    assert @executor.reload.models_listed_at
    with_fake_claude { check(executor_target: @executor.id, model: "opus", effort: "max") }
    assert_match "opus, effort max: answered", response.parsed_body["output"]
    assert @executor.reload.model_check_ok
    patch admin_executor_path(@executor), params: { executor: { effort: "high", extra_models: "a\n-b" } }
    assert_response :unprocessable_content
  end
end
