require "test_helper"

# Spec 053: "Relaxed sandbox" — the web, local ports and Git for command-line agents; file rules unchanged.
class RelaxedSandboxTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @dirs = Dir.mktmpdir
    @project = File.join(@dirs, "project").tap { |d| FileUtils.mkdir_p(d) }
    @other = File.join(@dirs, "other").tap { |d| FileUtils.mkdir_p(d) }
    @claude = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Dev", master_prompt: "You code.", executor: @claude)
  end

  teardown { FileUtils.rm_rf(@dirs) }

  def space(dir, user: @user, name: "Code") = user.spaces.create!(name: name, goal: "Ship", working_dir: dir)

  def step_run(space)
    item = @user.work_items.create!(title: "Fix bug", space: space, state: "planned")
    item.epic_steps.create!(position: 1, title: "Fix", agent: @agent)
    StepChain.start(item)
  end

  def chat_run = TaskRun.create!(user: @user, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "running")

  def settings(run, space = nil)
    JSON.parse(AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "s", user: "u")).send(:claude_settings, space))
  end

  def codex_args(run, space = nil)
    call = AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "s", user: "u"))
    call.instance_variable_set(:@chdir, @project)
    call.send(:cli_call, "codex", nil, AgentCall::Prompt.new(system: "s", user: "u"), space).first
  end

  test "G1: on by default for a new account" do
    assert @user.relaxed_sandbox?
  end

  test "G2, G3, G5: Claude Code gets any host and local ports, in a folder and outside it; reads stay denied" do
    space(@other, user: create_user(username: "bob"), name: "Bob")
    run = step_run(space(@project))
    inside = settings(run, run.epic_step.work_item.space)
    assert_equal [ [ "*" ], true ], [ inside.dig("sandbox", "network", "allowedDomains"), inside.dig("sandbox", "network", "allowLocalBinding") ]
    assert_includes inside.dig("sandbox", "filesystem", "denyRead"), File.realpath(@other), "S4: other spaces stay denied"
    assert_includes inside.dig("sandbox", "filesystem", "denyRead"), File.expand_path(Rails.root.join("storage")), "S4: storage stays denied"
    assert_equal false, inside.dig("sandbox", "allowUnsandboxedCommands"), "the sandbox stays on"

    outside = settings(chat_run)
    assert_equal({ "allowedDomains" => [ "*" ], "allowLocalBinding" => true }, outside.dig("sandbox", "network"))
    assert_equal [ Rails.root.join("storage").realpath.to_s ], outside.dig("sandbox", "filesystem", "denyRead")
    assert_equal true, outside.dig("sandbox", "enabled")
  end

  test "S5: with the setting off the run settings are as before" do
    @user.update!(relaxed_sandbox: false)
    run = step_run(space(@project))
    inside = settings(run, run.epic_step.work_item.space)
    assert_nil inside.dig("sandbox", "network", "allowLocalBinding")
    assert_equal [ "*" ], inside.dig("sandbox", "network", "allowedDomains"), "a folder had the network already (spec 018)"
    assert_nil settings(chat_run).dig("sandbox", "network")
    assert_not_includes codex_args(chat_run), "sandbox_workspace_write.network_access=true"
  end

  test "G2, S2: Codex gets network access outside a folder too (the verifier)" do
    args = codex_args(chat_run)
    assert_equal [ "--sandbox", "workspace-write", "-c", "sandbox_workspace_write.network_access=true" ], args[3, 4]
  end

  # A stand-in "claude" that answers and records its prompt.
  def with_claude
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > \"#{@dirs}/prompt\"\necho done\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  test "G4, S3: a step in a folder without Git gets a repository with no hooks, and its prompt says so" do
    run = step_run(space(@project))
    with_claude { StepChain.new(run).perform! }
    assert_equal "succeeded", run.reload.state
    git = File.join(@project, ".git")
    assert File.directory?(git)
    assert_empty Dir.children(File.join(git, "hooks")).reject { |f| f.start_with?(".") } if File.directory?(File.join(git, "hooks"))
    assert_match "Agentaro created an empty Git repository in your folder", File.read(File.join(@dirs, "prompt"))
    assert_match "Agentaro created an empty Git repository", run.prompt
  end

  test "G4: a folder already in a repository (here or above), or with the setting off, is left alone" do
    nested = File.join(@project, "app").tap { |d| FileUtils.mkdir_p(d) }
    FileUtils.mkdir_p(File.join(@project, ".git"))
    assert_nil WorkingGit.prepare(space(nested), @user)
    assert_equal [], Dir.children(File.join(@project, ".git"))
    assert_not File.exist?(File.join(nested, ".git"))

    @user.update!(relaxed_sandbox: false)
    assert_nil WorkingGit.prepare(space(@other, name: "Other"), @user)
    assert_not File.exist?(File.join(@other, ".git"))
  end

  test "G4 resilience: a failed git init is a note; the step still runs" do
    sp = space(@project)
    original = ExecutorCheck.method(:locate)
    ExecutorCheck.define_singleton_method(:locate) { |program, **opts| program == "git" ? nil : original.call(program, **opts) }
    assert_match "Git is not installed", WorkingGit.prepare(sp, @user)
  ensure
    ExecutorCheck.define_singleton_method(:locate, original) if original
  end

  test "G7: the director and the verifier are told the sandbox's state" do
    runner = ManagementRunner.allocate
    runner.instance_variable_set(:@user, @user)
    assert_match "Sandbox: relaxed", runner.send(:sandbox_line)
    @user.update!(relaxed_sandbox: false)
    assert_match "Sandbox: strict", runner.send(:sandbox_line)
  end
end
