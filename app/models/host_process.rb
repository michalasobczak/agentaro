# Specs 008 and 010: starts a program on the host safely and waits for it.
#
# No shell: the program and its arguments are passed as a list. The environment holds only ENV_KEPT,
# so Agentaro's own secrets never reach the program. Input is written to standard input (prompts never
# appear in the process list); standard output and error are read separately, each up to a limit. On
# timeout the whole process group is killed, children included.
class HostProcess
  ENV_KEPT = %w[PATH HOME USER LOGNAME LANG TMPDIR].freeze

  Result = Data.define(:status, :stdout, :stderr, :timed_out) do
    def success? = !timed_out && status&.success?
    def exit_status = status&.exitstatus
    # Why it ended, in words: "exit status 1" or "killed by signal 9 (KILL)".
    def ending
      return "stopped after the time limit" if timed_out
      return "exit status #{status.exitstatus}" if status&.exitstatus
      return "killed by signal #{status.termsig} (#{Signal.signame(status.termsig)})" if status&.signaled?

      "unknown ending"
    end
  end

  # on_stdout: called with each chunk of standard output as it arrives (spec 017: streamed answers).
  # on_spawn: called with the process id (also its group id) once it runs (spec 025: runs can be stopped).
  def self.run(program, args, stdin: nil, chdir: Dir.tmpdir, timeout:, max_output:, on_stdout: nil, on_spawn: nil)
    new(program, args, stdin:, chdir:, timeout:, max_output:, on_stdout:, on_spawn:).run
  end

  def initialize(program, args, stdin:, chdir:, timeout:, max_output:, on_stdout: nil, on_spawn: nil)
    @program, @args, @stdin, @chdir, @timeout, @max_output, @on_stdout, @on_spawn = program, args, stdin, chdir, timeout, max_output, on_stdout, on_spawn
  end

  def run
    in_r, in_w = IO.pipe
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    env = ENV.to_h.slice(*ENV_KEPT)
    pid = Process.spawn(env, @program, *@args, unsetenv_others: true, chdir: @chdir, pgroup: true,
                        in: in_r, out: out_w, err: err_w, close_others: true)
    @on_spawn&.call(pid)
    [ in_r, out_w, err_w ].each(&:close)
    writer = Thread.new { write_input(in_w) }

    deadline = now + @timeout
    buffers = { out_r => +"", err_r => +"" }
    open = [ out_r, err_r ]
    exited = nil
    until open.empty?
      remaining = deadline - now
      break if remaining <= 0

      ready, = IO.select(open, nil, nil, [ remaining, 0.5 ].min)
      unless exited
        _, exited = Process.wait2(pid, Process::WNOHANG)
        deadline = [ deadline, now + 2 ].min if exited # a leftover child may hold the output open
      end
      next unless ready

      ready.each do |io|
        chunk = io.read_nonblock(16_384, exception: false)
        if chunk.nil?
          open.delete(io)
        elsif chunk.is_a?(String) && buffers[io].bytesize < @max_output
          buffers[io] << chunk
          @on_stdout&.call(chunk) if io == out_r
        end
      end
    end

    status = exited || wait_or_kill(pid, deadline)
    kill_group(pid) if exited # leftover children
    writer.join(1)
    Result.new(status: status, stdout: buffers[out_r].byteslice(0, @max_output), stderr: buffers[err_r].byteslice(0, @max_output), timed_out: status.nil?)
  ensure
    [ in_r, in_w, out_r, out_w, err_r, err_w ].each { |io| io.close if io && !io.closed? }
  end

  private

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def kill_group(pid)
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def write_input(io)
    io.binmode # bytes as they are, whatever the text's encoding (found with spec 017)
    io.write(@stdin) if @stdin
  rescue IOError, Errno::EPIPE
    nil # the program stopped reading
  ensure
    io.close unless io.closed?
  end

  def wait_or_kill(pid, deadline)
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status
      break if now >= deadline

      sleep 0.05
    end
    kill_group(pid)
    begin
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
    nil
  end
end
