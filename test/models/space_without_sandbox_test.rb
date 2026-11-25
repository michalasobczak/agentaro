require "test_helper"
require "socket"

# Spec 054: a space without a sandbox — steps, CI and the server run with the account's full rights; off = as before.
class SpaceWithoutSandboxTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @dir = File.realpath(Dir.mktmpdir("nosb-project"))
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra", working_dir: @dir)
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Dev", master_prompt: "You code.", executor: @claude)
    @outside = Rails.root.join("tmp", "nosb-#{SecureRandom.hex(4)}.txt").to_s # outside the folder and the temporary folders
  end

  teardown do
    Ci::Server.stop!(@space) if @space&.persisted? && @space.reload.server_pid
    FileUtils.rm_rf(@dir)
    FileUtils.rm_f(@outside)
  end

  def step_run
    @step_run ||= begin
      item = @user.work_items.create!(title: "Fix bug", space: @space, state: "planned")
      item.epic_steps.create!(position: 1, title: "Fix", agent: @agent)
      StepChain.start(item)
    end
  end

  def cli(key, run = step_run)
    call = AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "s", user: "u"))
    call.instance_variable_set(:@chdir, @dir)
    call.send(:cli_call, key, "m", AgentCall::Prompt.new(system: "s", user: "u"), @space.reload).first
  end

  def option(args, name) = args[args.index(name) + 1]
  def config(text) = File.write(File.join(@dir, "agentaro.yml"), text)
  def run_ci = Ci::Runner.new(Ci.queue!(@space, trigger: "manual")).perform!

  test "G1: off by default" do
    assert_not @space.no_sandbox?
  end

  test "G6, S3: with the switch off, Claude Code and Codex keep their sandbox" do
    claude = cli("claude_code")
    assert_equal "acceptEdits", option(claude, "--permission-mode")
    assert_equal true, JSON.parse(option(claude, "--settings")).dig("sandbox", "enabled")
    assert_equal "workspace-write", option(cli("codex"), "--sandbox")
    assert_equal "workspace-write", option(cli("codex_local"), "--sandbox")
  end

  test "G2: with the switch on, a step runs Claude Code and Codex without a sandbox" do
    @space.update!(no_sandbox: true)
    claude = cli("claude_code")
    assert_equal "bypassPermissions", option(claude, "--permission-mode")
    settings = JSON.parse(option(claude, "--settings"))
    assert_equal false, settings.dig("sandbox", "enabled")
    assert_nil settings.dig("permissions", "deny")
    assert_not_includes claude, "--allowedTools", "every tool is allowed"
    assert_equal "danger-full-access", option(cli("codex"), "--sandbox")
    assert_equal "danger-full-access", option(cli("codex_local"), "--sandbox")
    assert_not cli("codex").any? { |a| a.include?("sandbox_workspace_write") }
  end

  test "R2: a run that is not a step of this space keeps its sandbox (the director, Q1)" do
    @space.update!(no_sandbox: true)
    chat = TaskRun.create!(user: @user, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "running")
    call = AgentCall.new(chat, @agent, AgentCall::Prompt.new(system: "s", user: "u"))
    call.instance_variable_set(:@chdir, @dir)
    claude = call.send(:cli_call, "claude_code", "m", AgentCall::Prompt.new(system: "s", user: "u"), nil).first
    assert_equal "acceptEdits", option(claude, "--permission-mode")
  end

  test "G5: the step's prompt says the space has no sandbox" do
    run = step_run
    assert_no_match(/no sandbox/i, StepChain.prompt_for(run.epic_step, @agent).text)
    @space.update!(no_sandbox: true)
    assert_match(/no sandbox/i, StepChain.prompt_for(run.epic_step.reload, @agent).text)
  end

  test "G3, S3: CI writes outside the folder only with the switch on" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    config("build: echo x > #{@outside}\n")
    run_ci
    assert_equal "failed_build", @space.reload.ci_state
    assert_not File.exist?(@outside)
    @space.update!(no_sandbox: true)
    TaskRun.where(purpose: "ci").update_all(state: "skipped")
    run_ci
    assert_equal "ok", @space.reload.ci_state
    assert File.exist?(@outside)
  end

  test "G3, S1: the server writes outside the folder only with the switch on" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    config("serve: echo x > #{@outside}; sleep 30\n")
    Ci::Server.start!(@space)
    sleep 0.5
    assert_not File.exist?(@outside)
    @space.update!(no_sandbox: true)
    Ci::Server.start!(@space)
    sleep 0.5
    assert File.exist?(@outside)
    assert Ci::Server.alive?(@space.reload)
  end

  test "G4: a change of the switch restarts a wanted server under the new rules" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    config("serve: echo x > #{@outside}; sleep 30\n")
    first = Ci::Server.start!(@space)
    @space.reload.set_no_sandbox!(true)
    assert_not_equal first, @space.reload.server_pid
    sleep 0.5
    assert File.exist?(@outside)
  end

  test "G5: the director sees that a space has no sandbox" do
    @space.update!(no_sandbox: true)
    run = TaskRun.create!(user: @user, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "running")
    assert_match(/no sandbox/i, ManagementRunner.new(run).send(:ci_text, @space))
  end
end
