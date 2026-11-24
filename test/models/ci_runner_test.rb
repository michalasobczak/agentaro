require "test_helper"
require "socket"

# Spec 052: CI runs (G2, G3), the server keeper (G4, S1, S4, S5) and the triggers — real commands in the real sandbox.
class CiRunnerTest < ActiveSupport::TestCase
  setup do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    @dir = File.realpath(Dir.mktmpdir("ci-project"))
    @user = create_user
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra", working_dir: @dir)
  end

  teardown do
    Ci::Server.stop!(@space) if @space&.persisted? && @space.reload.server_pid
    FileUtils.rm_rf(@dir) if @dir
  end

  def config(text) = File.write(File.join(@dir, "agentaro.yml"), text)
  def free_port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
  def run_ci(trigger: "manual") = Ci::Runner.new(Ci.queue!(@space, trigger: trigger)).perform!

  test "S1, G3: build and test run in order; the space keeps the result and the end of the log" do
    config("build: echo building > built.txt\ntest: test -f built.txt && echo tests passed\n")
    run = run_ci
    assert_equal [ "succeeded", "ok" ], [ run.reload.state, @space.reload.ci_state ]
    assert_match "tests passed", @space.ci_log
    assert @space.ci_fingerprint.present?
  end

  test "G3: a failing test is a result, with the log; the build's output is kept" do
    config("build: echo built\ntest: echo 'expected 2 got 3'; exit 1\n")
    run_ci
    assert_equal "failed_test", @space.reload.ci_state
    assert_match "expected 2 got 3", @space.ci_log
  end

  test "S3: a command that writes outside the folder fails in the sandbox" do
    config("build: echo x > #{Dir.home}/agentaro-ci-#{SecureRandom.hex(3)}.txt\n")
    run_ci
    assert_equal "failed_build", @space.reload.ci_state
  end

  test "G2: one waiting run per space; a broken file marks an error and queues nothing" do
    config("build: echo ok\n")
    assert Ci.queue!(@space, trigger: "manual")
    assert_nil Ci.queue!(@space, trigger: "manual"), "one already waits"
    config("build: [x]\n")
    TaskRun.where(purpose: "ci").update_all(state: "skipped")
    assert_nil Ci.queue!(@space, trigger: "manual")
    assert_equal "error", @space.reload.ci_state
  end

  test "S2, R2: after a step, CI only when the folder changed since the last CI" do
    config("build: echo ok\n")
    run_ci
    assert_nil Ci.after_step(@space.reload), "nothing changed"
    File.write(File.join(@dir, "game.js"), "changed")
    assert Ci.after_step(@space.reload), "a file changed"
  end

  test "S1, S4, S5, G4: the server starts, is up, comes back after it dies (at most 3 times in 10 minutes), and after a restart" do
    port = free_port
    config("serve: python3 -m http.server #{port} --bind 127.0.0.1\nurl: http://127.0.0.1:#{port}/\n")
    Ci::Server.start!(@space)
    deadline = Time.current + 15
    sleep 0.3 until Ci::Server.answers?("http://127.0.0.1:#{port}/") || Time.current > deadline
    Ci::Server.check!(@space.reload)
    assert_equal "up", @space.reload.server_state

    3.times do |i|
      Process.kill("KILL", -@space.reload.server_pid)
      sleep 0.5
      Ci::Server.check!(@space.reload)
      assert_equal "starting", @space.reload.server_state, "started again (#{i + 1})"
    end
    Process.kill("KILL", -@space.reload.server_pid)
    sleep 0.5
    Ci::Server.check!(@space.reload)
    assert_equal "down", @space.reload.server_state
    assert_match "3 times in 10 minutes", @space.server_note

    Ci::Server.recover! # S5: after Agentaro starts, a wanted server that is not running is started
    assert Ci::Server.alive?(@space.reload)
    assert_match "start: python3 -m http.server", Ci::Server.log_tail(@space)
  end

  test "G4: a good build restarts a wanted server; stop leaves it stopped" do
    port = free_port
    config("build: echo ok\nserve: python3 -m http.server #{port} --bind 127.0.0.1\n")
    Ci::Server.start!(@space)
    first = @space.reload.server_pid
    run_ci
    assert_not_equal first, @space.reload.server_pid
    Ci::Server.stop!(@space)
    assert_equal [ "stopped", false ], [ @space.reload.server_state, @space.server_wanted ]
    assert_not Ci::Server.alive?(@space)
  end
  def server_alive?(pid) = Process.kill(0, pid).positive? rescue false

  test "owner change 2026-11-24, R6: a check on a stale copy of the space does not start a second server that is then lost" do
    port = free_port
    config("serve: python3 -m http.server #{port} --bind 127.0.0.1\nurl: http://127.0.0.1:#{port}/\n")
    @space.update!(server_wanted: true, server_state: "down")
    stale = Space.find(@space.id) # read before the start, like the 10-second check that runs beside a restart
    first = Ci::Server.start!(@space)
    Ci::Server.check!(stale)
    assert_equal first, @space.reload.server_pid, "the running server is kept, not replaced"
    Ci::Server.stop!(@space)
    sleep 0.3
    assert_not server_alive?(first), "no server of the space outlives a stop"
  end

  test "owner change 2026-11-24, R7: a server process missing from the record is still stopped by the next start" do
    port = free_port
    config("serve: python3 -m http.server #{port} --bind 127.0.0.1\nurl: http://127.0.0.1:#{port}/\n")
    lost = Ci::Server.start!(@space)
    @space.reload.update!(server_pid: nil, server_process_started: nil) # the record forgot it, as in the double start
    second = Ci::Server.start!(@space)
    sleep 0.3
    assert_not server_alive?(lost), "the lost server was stopped before the new one"
    assert server_alive?(second)
    Ci::Server.stop!(@space)
    sleep 0.3
    assert_not server_alive?(second)
    assert_equal [], JSON.parse(@space.reload.server_processes.presence || "[]")
  end
end
