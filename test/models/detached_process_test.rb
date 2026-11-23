require "test_helper"

# Spec 053, B20 finding: a step started "a server &" and its shell ended before the tracker's next poll; the server,
# now with no parent and a group of its own, outlived the step (found with a real Claude Code step, port 8797).
class DetachedProcessTest < ActiveSupport::TestCase
  setup do
    @state = Dir.mktmpdir
    @work = Dir.mktmpdir
    @other = Dir.mktmpdir
  end

  teardown do
    [ @left, @foreign ].compact.each { |pid| Process.kill("KILL", pid) rescue nil }
    [ @state, @work, @other ].each { |d| FileUtils.rm_rf(d) }
  end

  # Starts "sleep" detached (its own session; the shell that started it exits at once) in the given folder; its pid.
  PERL = 'use POSIX; setsid(); open(my $f, ">", $ARGV[0]); print $f $$; close $f; exec("sleep", "60")'

  def detached_sleep(dir)
    pidfile = File.join(@state, "pid-#{SecureRandom.hex(4)}")
    shell = Process.spawn("/bin/sh", "-c", "cd \"$1\" && exec /usr/bin/perl -e \"$2\" \"$3\" </dev/null >/dev/null 2>&1 &", "sh", dir, PERL, pidfile,
                          in: File::NULL, out: File::NULL, err: File::NULL)
    Process.wait(shell)
    pid = nil
    50.times do
      pid = File.read(pidfile).to_i if File.size?(pidfile)
      break if pid && ProcessTracker.snapshot.find { |p| p.pid == pid }&.command&.start_with?("sleep")

      sleep 0.1
    end
    pid
  end

  test "a detached process in the step's folder is stopped at the end; one in another folder is left alone" do
    tracker = ProcessTracker.new(@state, 999_999, cwd: @work) # no poll while the step ran
    @left = detached_sleep(@work)
    @foreign = detached_sleep(@other)
    assert_equal 1, ProcessTracker.snapshot.find { |p| p.pid == @left }&.ppid, "the process has no parent"

    stopped = tracker.finish!
    sleep 0.3
    assert(stopped.any? { |c| c.include?("sleep") }, stopped.inspect)
    assert_nil ProcessTracker.snapshot.find { |p| p.pid == @left }, "the step's detached process is gone"
    assert ProcessTracker.snapshot.find { |p| p.pid == @foreign }, "a process working elsewhere is not touched"
  end

  test "without the step's folder nothing is adopted" do
    tracker = ProcessTracker.new(@state, 999_999)
    @left = detached_sleep(@work)
    tracker.finish!
    assert ProcessTracker.snapshot.find { |p| p.pid == @left }
  end
end
