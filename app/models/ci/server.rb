require "net/http"

# Spec 052, G4: the server of a space, kept by Agentaro. It runs `serve` from agentaro.yml in the sandbox, detached in
# its own process group, its output in a log file. Every 10 seconds its process and its `url` are checked; a server
# that ended by itself is started again at most 3 times in 10 minutes. A wanted server comes back after a restart.
# Owner change 2026-11-24: start, stop and check of one space run one at a time on the saved record (R6), and every
# process started is remembered until it is seen gone, so a lost one is still stopped (R7).
module Ci
  module Server
    CHECK_EVERY = 10 # seconds
    START_GRACE = 30.seconds
    RESTARTS = 3
    RESTART_WINDOW = 10.minutes
    LOG_LINES = 200
    MAX_LOG = 1024 * 1024
    URL_TIMEOUT = 2

    module_function

    LOCKS = Hash.new { |hash, id| hash[id] = Monitor.new }
    LOCKS_GUARD = Mutex.new

    # R6: one space's server is started, stopped and checked by one thread at a time (re-entrant: a check may start),
    # always on the record as saved now. Puma runs one process, so an in-process lock is enough; a lock file would sit
    # where the server's own sandbox can read it and hold it.
    def locked(space)
      lock = LOCKS_GUARD.synchronize { LOCKS[space.id] }
      lock.synchronize do
        space.reload if space.persisted?
        yield
      end
    end

    def log_path(space) = Pathname(Sandbox.logs_dir).join(space.id.to_s, "server.log") # readable by its own sandbox only

    def start!(space, wanted: true)
      locked(space) { start_locked(space, wanted) }
    end

    def start_locked(space, wanted)
      config = Ci.config_for(space)
      raise Config::Invalid, "#{Config::FILE} has no serve command" unless config&.serve
      raise Config::Invalid, "sandbox-exec is not on this computer" unless Sandbox.available?

      stop_process(space)
      path = log_path(space)
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "") if File.size?(path).to_i > MAX_LOG
      log = File.open(path, "a")
      log.puts("--- #{Time.current.iso8601} start: #{config.serve}")
      env = ENV.to_h.slice(*HostProcess::ENV_KEPT)
      pid = Process.spawn(env, Sandbox::PROGRAM, *Sandbox.command(space, config.serve), unsetenv_others: true, chdir: space.working_dir,
                          pgroup: true, in: File::NULL, out: log, err: log, close_others: true)
      log.close
      Process.detach(pid)
      started = ProcessTracker.snapshot.find { |p| p.pid == pid }&.started
      space.update!(server_processes: (processes(space) + [ { "pid" => pid, "started" => started } ]).to_json) # R7
      space.update!(server_wanted: wanted, server_state: "starting", server_pid: pid, server_process_started: started,
                    server_started_at: Time.current, server_checked_at: Time.current, server_note: nil)
      pid
    rescue Config::Invalid => e
      space.update!(server_state: "down", server_note: e.message, server_checked_at: Time.current)
      nil
    end

    def stop!(space)
      locked(space) do
        stop_process(space)
        space.update!(server_wanted: false, server_state: "stopped", server_pid: nil, server_process_started: nil, server_note: nil)
      end
    end

    def restart!(space)
      start!(space)
    end

    # The process group of the space's server, if it is still the one Agentaro started (pids are reused).
    def alive?(space)
      return false unless space.server_pid

      info = ProcessTracker.snapshot.find { |p| p.pid == space.server_pid }
      info.present? && (space.server_process_started.blank? || info.started == space.server_process_started)
    end

    # R7: the server processes Agentaro started for the space and has not seen end, [{ "pid", "started" }].
    def processes(space)
      list = JSON.parse(space.server_processes.presence || "[]")
      list.is_a?(Array) ? list.select { |e| e.is_a?(Hash) && e["pid"].is_a?(Integer) && e["pid"] > 1 } : []
    rescue JSON::ParserError
      []
    end

    # Stops every server process of the space still running as Agentaro started it (pid and start time match), with
    # its process group; then forgets them. The current one is included even when an old record has no list yet.
    def stop_process(space)
      targets = processes(space)
      targets << { "pid" => space.server_pid, "started" => space.server_process_started } if space.server_pid && targets.none? { |e| e["pid"] == space.server_pid }
      running = ->(entry) { ProcessTracker.snapshot.any? { |p| p.pid == entry["pid"] && (entry["started"].blank? || p.started == entry["started"]) } }
      live = targets.select(&running)
      signal_groups("TERM", live)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      sleep 0.1 while (live = live.select(&running)).any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      signal_groups("KILL", live)
      space.update!(server_processes: nil) if space.persisted? && !space.destroyed? && space.server_processes.present?
    end

    def signal_groups(signal, entries)
      entries.each do |entry|
        Process.kill(signal, -entry["pid"])
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end

    # G4: one look at a wanted server.
    def check!(space, now: Time.current)
      locked(space) { check_locked(space, now) }
    end

    def check_locked(space, now)
      return unless space.server_wanted

      if alive?(space)
        config = (Ci.config_for(space) rescue nil)
        answers = config&.url ? answers?(config.url) : true
        state = if answers then "up"
                elsif space.server_started_at && space.server_started_at > now - START_GRACE then "starting"
                else "down"
                end
        note = state == "down" ? "#{config&.url} does not answer" : nil
        return space.update!(server_state: state, server_checked_at: now, server_note: note)
      end

      restarts = JSON.parse(space.server_restarts.presence || "[]").map { |t| Time.zone.parse(t) rescue nil }.compact.select { |t| t > now - RESTART_WINDOW }
      if restarts.size >= RESTARTS
        return space.update!(server_state: "down", server_pid: nil, server_checked_at: now,
                             server_note: "It ended by itself #{RESTARTS} times in #{RESTART_WINDOW.in_minutes.to_i} minutes; see its log.")
      end
      space.update!(server_restarts: (restarts + [ now ]).map(&:iso8601).to_json)
      start_locked(space, true)
      space.update!(server_note: "It had ended by itself; started again.") if space.server_state == "starting"
    end

    def answers?(url)
      uri = URI.parse(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: URL_TIMEOUT, read_timeout: URL_TIMEOUT) { |http| http.head(uri.request_uri.presence || "/") }
      true
    rescue StandardError
      false
    end

    # The ticker of the servers: every wanted server, each CHECK_EVERY seconds.
    def tick(now: Time.current)
      Space.where(server_wanted: true, state: "active").find_each { |space| check!(space, now: now) }
    end

    # G4, Q1: after Agentaro starts, wanted servers that are not running are started (not counted as restarts).
    def recover!
      Space.where(server_wanted: true, state: "active").find_each { |space| locked(space) { start_locked(space, true) unless alive?(space) } }
    end

    def watch!
      Thread.new do
        Thread.current.name = "agentaro-servers"
        Rails.application.executor.wrap { recover! }
        loop do
          sleep CHECK_EVERY
          Rails.application.executor.wrap { tick }
        rescue StandardError => e
          Rails.logger.error("[servers] #{e.class}: #{e.message}")
        end
      end
    end

    def log_tail(space, lines = LOG_LINES)
      path = log_path(space)
      return "" unless File.file?(path)

      text = File.open(path, "rb") { |f| f.seek([ f.size - 64 * 1024, 0 ].max); f.read }.force_encoding(Encoding::UTF_8).scrub("")
      RunTrace.redact(ExecutorCheck.clean_text(text)).first.lines.last(lines).join
    end
  end
end
