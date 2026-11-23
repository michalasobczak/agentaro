require "test_helper"

# Spec 018: a space's working folder — validation (R1), where steps run (G2), what they may and may not read (G4).
class WorkingFolderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @dirs = Dir.mktmpdir
    @project = File.join(@dirs, "project").tap { |d| FileUtils.mkdir_p(d) }
    @other = File.join(@dirs, "other").tap { |d| FileUtils.mkdir_p(d) }
    @executor = Executor.create!(name: "Claude", preset: "claude_code")
    @agent = Agent.create!(user: @user, name: "Dev", master_prompt: "You code.", executor: @executor)
  end

  teardown { FileUtils.rm_rf(@dirs) }

  def space(dir, user: @user, name: "Code") = user.spaces.create!(name: name, goal: "Ship", working_dir: dir)

  test "R1: an absolute existing folder, stored resolved; never /, Agentaro's storage or runs" do
    link = File.join(@dirs, "link")
    File.symlink(@project, link)
    assert_equal File.realpath(@project), space(link).working_dir
    [ "relative/path", File.join(@dirs, "missing"), "/", Rails.root.join("storage").to_s, Rails.root.join("storage", "voice").to_s,
      File.dirname(Rails.application.config.x.runs_dir) ].each do |dir|
      next unless dir.start_with?("/") ? File.directory?(dir) || !File.exist?(dir) : true

      assert_not @user.spaces.new(name: "X#{dir.hash}", goal: "g", working_dir: dir).valid?, dir
    end
    assert @user.spaces.new(name: "Plain", goal: "g").valid?, "the folder is optional"
  end

  test "G4: other spaces' folders (any user) and Agentaro's storage are denied; a folder containing this one is not" do
    mine = space(@project)
    space(@other, user: create_user(username: "bob"), name: "Bob")
    parent = space(@dirs, name: "Parent")
    denied = mine.denied_dirs
    assert_includes denied, File.realpath(@other)
    assert_includes denied, File.expand_path(Rails.root.join("storage"))
    assert_not_includes denied, File.realpath(@dirs), "denying a parent would deny the project itself"
    assert_not_includes denied, File.realpath(@project)
    assert_includes parent.denied_dirs, File.realpath(@project), "a project inside another space's folder stays private"
  end

  # A stand-in "claude": records its arguments and working directory.
  def with_claude
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat > /dev/null\nprintf '%s\\n' \"$@\" > \"#{@dirs}/args\"\npwd > \"#{@dirs}/cwd\"\necho done\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end

  def step_run(space)
    item = @user.work_items.create!(title: "Fix bug", space: space, state: "planned")
    item.epic_steps.create!(position: 1, title: "Fix", agent: @agent)
    StepChain.start(item)
  end

  test "G2, G3, G6: a step runs in the folder with Bash, network for any host, Docker and the read limit" do
    space(@other, user: create_user(username: "bob"), name: "Bob")
    run = step_run(space(@project))
    with_claude { StepChain.new(run).perform! }
    assert_equal "succeeded", run.reload.state
    assert_equal File.realpath(@project), File.read(File.join(@dirs, "cwd")).strip
    args = File.read(File.join(@dirs, "args")).lines(chomp: true)
    assert_equal "Bash WebSearch WebFetch", args[args.index("--allowedTools") + 1]
    settings = JSON.parse(args[args.index("--settings") + 1])
    assert_includes settings.dig("sandbox", "filesystem", "denyRead"), File.realpath(@other)
    assert_includes settings.dig("permissions", "deny"), "Read(/#{File.realpath(@other)}/**)"
    assert_equal [ "*" ], settings.dig("sandbox", "network", "allowedDomains")
    assert_equal false, settings.dig("sandbox", "allowUnsandboxedCommands")
    assert_equal true, settings.dig("sandbox", "failIfUnavailable")
    assert_match "You work in the space's folder #{File.realpath(@project)}", run.prompt
  end

  test "S3: a space without a folder runs as before — an empty run folder, web tools only" do
    @user.update!(relaxed_sandbox: false) # spec 053: with the relaxed sandbox on, the network is open here too (relaxed_sandbox_test.rb)
    run = step_run(@user.spaces.create!(name: "Plain", goal: "g"))
    with_claude { StepChain.new(run).perform! }
    assert_match %r{/work\z}, File.read(File.join(@dirs, "cwd")).strip
    args = File.read(File.join(@dirs, "args")).lines(chomp: true)
    assert_equal "WebSearch WebFetch", args[args.index("--allowedTools") + 1]
    assert_no_match "allowedDomains", args[args.index("--settings") + 1]
  end

  test "resilience: a folder that disappeared fails the step and blocks the epic" do
    run = step_run(space(@project))
    FileUtils.rm_rf(@project)
    StepChain.new(run).perform!
    assert_equal "failed", run.reload.state
    assert_match "Working folder not found", run.error
    assert_equal "blocked", run.work_item.reload.state
  end

  test "Q5: Codex works in the folder with network on (reads not limited)" do
    codex = Executor.create!(name: "Codex", preset: "codex")
    @agent.update!(executor: codex)
    run = step_run(space(@project))
    call = AgentCall.new(run, @agent, AgentCall::Prompt.new(system: "s", user: "u"))
    call.instance_variable_set(:@chdir, File.realpath(@project))
    args, = call.send(:cli_call, "codex", nil, AgentCall::Prompt.new(system: "s", user: "u"), run.epic_step.work_item.space)
    assert_equal [ "--sandbox", "workspace-write", "-c", "sandbox_workspace_write.network_access=true" ], args[3, 4]
    assert_equal File.realpath(@project), args[args.index("-C") + 1]
  end

  test "owner fix: folder suggestions — folders only, by prefix, no hidden ones, nothing inside protected or other users' folders" do
    root = File.realpath(@dirs)
    %w[Agentaro agents archive .secret].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "agenda.txt"), "file")
    found = ->(input, user = @user) { FolderSuggestions.for(input, user).folders }
    assert_equal [ "#{root}/Agentaro/", "#{root}/agents/" ], found.("#{root}/ag"), "case-insensitive, folders only, sorted"
    assert_includes found.("#{root}/"), "#{root}/archive/"
    assert_not found.("#{root}/").any? { |p| p.include?(".secret") }, "hidden folders only when asked for"
    assert_equal [ "#{root}/.secret/" ], found.("#{root}/.se")
    assert FolderSuggestions.for(root, @user).exists
    assert_not FolderSuggestions.for("#{root}/nope", @user).exists

    storage = File.realpath(Rails.root.join("storage"))
    assert_empty found.("#{storage}/"), "Agentaro's storage is never listed"
    assert_not FolderSuggestions.for(storage, @user).exists

    space(File.join(root, "agents"), user: create_user(username: "bob"), name: "Bob's")
    FileUtils.mkdir_p(File.join(root, "agents", "inside"))
    assert_empty found.("#{root}/agents/"), "another user's space folder is not listed"
    assert_not_includes found.("#{root}/"), "#{root}/agents/"
    space(File.join(root, "archive"))
    FileUtils.mkdir_p(File.join(root, "archive", "2026"))
    assert_equal [ "#{root}/archive/2026/" ], found.("#{root}/archive/"), "my own space folder is listed"
    assert found.("~/").all? { |p| p.start_with?(Dir.home) }, "~ is the home folder"
    assert_equal [], found.("relative")
  end
end
