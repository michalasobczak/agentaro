require "test_helper"

# Spec 052: agentaro.yml (G1, R1) and the sandbox its commands run in (G6, S3) — the sandbox on the real sandbox-exec.
class CiConfigTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("ci-project")
    @user = create_user
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra", working_dir: @dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  def write(text) = File.write(File.join(@dir, "agentaro.yml"), text)

  test "G1: the four keys are read; a folder without the file has no CI" do
    assert_nil Ci::Config.for(@dir)
    write("build: npm run build\nserve: npx http-server dist -p 8080\nurl: http://localhost:8080\n")
    config = Ci::Config.for(@dir)
    assert_equal [ "npm run build", nil, "npx http-server dist -p 8080", "http://localhost:8080" ], [ config.build, config.test, config.serve, config.url ]
    assert config.ci?
  end

  test "R1, negative: a broken or unexpected file runs nothing and says why" do
    write("build: [1, 2]\n")
    assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }
    write("deploy: rm -rf /\n")
    assert_match "unknown key deploy", assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }.message
    write("build: :\n  - x: [\n")
    assert_match "not valid YAML", assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }.message
    write("url: file:///etc/passwd\n")
    assert_match "url must start with http", assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }.message
    write("--- !ruby/object:Object {}\n")
    assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }
  end

  test "S3, G6: in the sandbox a command writes in the folder, but not outside it and never reads Agentaro's storage" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    run = ->(line) { HostProcess.run(Ci::Sandbox::PROGRAM, Ci::Sandbox.command(@space, line), chdir: @dir, timeout: 20, max_output: 10_000) }
    assert run.("echo ok > inside.txt").success?
    assert File.exist?(File.join(@dir, "inside.txt"))
    outside = File.join(Dir.home, "agentaro-sandbox-check-#{SecureRandom.hex(4)}")
    assert_not run.("echo no > #{outside}").success?
    assert_not File.exist?(outside)
    secret = Rails.root.join("storage", "sandbox-check-#{SecureRandom.hex(4)}.txt")
    File.write(secret, "secret")
    result = run.("cat #{secret}")
    assert_not result.success?
    assert_no_match(/secret/, result.stdout)
  ensure
    FileUtils.rm_f(secret) if secret
  end

  test "G4, B20: a space's sandbox reads its own server log, never another space's" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    other_dir = Dir.mktmpdir("ci-other")
    other = @user.spaces.create!(kind: "team", name: "Inna", working_dir: other_dir)
    [ @space, other ].each { |s| FileUtils.mkdir_p(Ci::Server.log_path(s).dirname); File.write(Ci::Server.log_path(s), "log of #{s.name}") }
    run = ->(line) { HostProcess.run(Ci::Sandbox::PROGRAM, Ci::Sandbox.command(@space, line), chdir: @dir, timeout: 20, max_output: 10_000) }
    assert_match "log of Gra", run.("cat #{Ci::Server.log_path(@space)}").stdout
    assert_no_match(/log of Inna/, run.("cat #{Ci::Server.log_path(other)}").stdout)
  ensure
    [ @space, other ].compact.each { |s| FileUtils.rm_rf(Ci::Server.log_path(s).dirname) }
    FileUtils.rm_rf(other_dir) if other_dir
  end

  test "B20: url may only name this computer" do
    write("url: http://192.168.1.10:8080/\n")
    assert_match "url must be on this computer", assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }.message
    write("url: http://user:pw@localhost:8080/\n")
    assert_raises(Ci::Config::Invalid) { Ci::Config.for(@dir) }
    write("url: http://[::1]:8080/\n")
    assert_equal "http://[::1]:8080/", Ci::Config.for(@dir).url
  end

  test "B20: a repository's core.fsmonitor never runs outside the sandbox when Agentaro looks at the folder" do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    git = ExecutorCheck.locate("git") or skip "git not here"
    system(git, "-C", @dir, "init", "-q")
    marker = File.join(Dir.home, "agentaro-fsmonitor-#{SecureRandom.hex(3)}")
    system(git, "-C", @dir, "config", "core.fsmonitor", "touch #{marker}")
    Ci.fingerprint(@dir, space: @space)
    assert_not File.exist?(marker), "the planted command did not run"
  ensure
    FileUtils.rm_f(marker) if marker
  end
end
