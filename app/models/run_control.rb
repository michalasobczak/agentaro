# Spec 025: the agent processes running in this Agentaro process, by run id, so a run can be stopped — the whole
# process group is killed (children included). Runs reached over HTTP have no process; they cannot be stopped here.
class RunControl
  LOCK = Monitor.new
  @pids = {}

  class << self
    # Called by AgentCall around a program it starts.
    def started(run_id, pid) = LOCK.synchronize { @pids[run_id] = pid }
    def finished(run_id) = LOCK.synchronize { @pids.delete(run_id) }
    def running?(run_id) = LOCK.synchronize { @pids.key?(run_id) }

    # Kills the run's process group; true when there was one.
    def stop!(run_id)
      pid = LOCK.synchronize { @pids[run_id] } or return false
      Process.kill("KILL", -pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end
end
