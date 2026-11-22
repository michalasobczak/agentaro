# Spec 040, G3: the processes a step started. A poller (every POLL seconds while the step runs) follows the step's
# agent process down its tree — also children that moved to process groups of their own (Claude Code runs Bash
# commands that way) or lost their parent — and keeps each by its process id and start time (R3), so a reused number
# is never taken for one of them. The list is kept in the run's folder (processes.json): the live view and the
# director read it, and after a restart the step's leftovers are still found (R8). When the step ends, every one
# still alive is stopped: a request to end first, a forced stop after GRACE seconds (R4).
class ProcessTracker
  POLL = 2
  GRACE = 5
  FILE = "processes.json"
  MAX_COMMAND = 300
  Info = Data.define(:pid, :ppid, :pgid, :uid, :started, :cpu, :command)

  # Every process of this user on the computer, now.
  def self.snapshot
    out = IO.popen([ "ps", "-axo", "pid=,ppid=,pgid=,uid=,lstart=,%cpu=,command=" ], err: File::NULL, &:read).to_s
    out.each_line.filter_map do |line|
      pid, ppid, pgid, uid, _wday, mon, day, time, year, cpu, command = line.strip.split(/\s+/, 11)
      next unless command && uid.to_i == Process.uid

      Info.new(pid.to_i, ppid.to_i, pgid.to_i, uid.to_i, "#{year} #{mon} #{day} #{time}", cpu.to_f, command)
    end
  rescue SystemCallError
    []
  end

  def self.key(pid, started) = "#{pid}@#{started}"
  def self.path(dir) = Pathname(dir).join(FILE)

  # The saved list of a run: [{ "pid", "started", "command", "cpu", "since", "alive" }], [] when there is none.
  def self.load(dir)
    file = path(dir)
    return [] unless File.lstat(file).file?

    list = JSON.parse(File.read(file))
    list.is_a?(Array) ? list.grep(Hash) : []
  rescue SystemCallError, JSON::ParserError
    []
  end

  def self.alive(dir) = load(dir).select { |p| p["alive"] }

  def initialize(dir, root_pid)
    @dir = Pathname(dir)
    @root = root_pid
    @tracked = {} # key => hash
    @lock = Monitor.new
  end

  def start
    @thread = Thread.new do
      loop do
        poll!
        sleep POLL
      end
    rescue StandardError => e
      Rails.logger.error("[processes] #{@dir}: #{e.class}: #{e.message}")
    end
    self
  end

  # Finds the step's processes in the current snapshot; returns the ones alive.
  def poll!(snapshot = self.class.snapshot)
    @lock.synchronize do
      by_key = snapshot.to_h { |p| [ self.class.key(p.pid, p.started), p ] }
      known = @tracked.select { |k, _| by_key.key?(k) }.values
      ours = Set[@root, *known.map { |t| t["pid"] }]
      groups = (Set[@root] + known.map { |t| t["pgid"] }) - excluded_groups # the agent's own group, and those of its children
      grown = true
      while grown
        grown = false
        snapshot.each do |p|
          next if ours.include?(p.pid) || excluded?(p)
          next unless ours.include?(p.ppid) || groups.include?(p.pgid)

          ours << p.pid
          groups << p.pgid unless excluded_groups.include?(p.pgid)
          grown = true
        end
      end
      snapshot.each do |p|
        next unless ours.include?(p.pid) && p.pid != @root

        entry = (@tracked[self.class.key(p.pid, p.started)] ||= { "pid" => p.pid, "started" => p.started, "since" => Time.current.iso8601 })
        entry.merge!("pgid" => p.pgid, "cpu" => p.cpu, "command" => clean(p.command), "alive" => true)
      end
      @tracked.each { |k, t| t["alive"] = false unless by_key.key?(k) }
      save
      @tracked.values.select { |t| t["alive"] }
    end
  end

  # The step ended: stop every process of it that is still alive. Returns the commands stopped.
  def finish!
    @thread&.kill
    poll!
    self.class.stop(@dir, @tracked.values.select { |t| t["alive"] })
  end

  # R3, R4: stops the given saved entries (and what they started), each only while its id and start time still match.
  def self.stop(dir, entries)
    return [] if entries.empty?

    snapshot = self.snapshot
    live = ->(list) { now = self.snapshot; list.select { |e| snapshot_has?(now, e) } }
    server = Set[0, 1, Process.getpgrp] # B20: never the server's own group, whatever a saved list says
    in_server = ->(e) { e["pid"].to_i <= 1 || e["pid"] == Process.pid || ((info = snapshot.find { |p| p.pid == e["pid"] }) && server.include?(info.pgid)) }
    # B20 (found in the spec 043 analysis): the server is dropped before its children are gathered, so a saved list
    # naming it never reaches the other runs' processes, which have process groups of their own.
    targets = with_children(entries.select { |e| snapshot_has?(snapshot, e) }.reject(&in_server), snapshot)
    targets = targets.reject(&in_server)
    signal(targets, "TERM")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GRACE
    remaining = targets
    while remaining.any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.2
      remaining = live.(remaining)
    end
    signal(remaining, "KILL") if remaining.any?
    mark_stopped(dir, targets)
    targets.map { |e| e["command"].to_s.truncate(120) }
  end

  # After a restart (R8): the saved processes of an interrupted step that are still alive.
  def self.stop_saved(dir) = stop(dir, alive(dir))

  # G4: one process of a running step, by its saved number; nil when it is not one of the step's own (R3).
  def self.stop_one(dir, pid)
    entry = alive(dir).find { |e| e["pid"] == pid.to_i } or return
    stop(dir, [ entry ])
  end

  def self.snapshot_has?(snapshot, entry) = snapshot.any? { |p| p.pid == entry["pid"] && p.started == entry["started"] }

  def self.with_children(entries, snapshot)
    pids = entries.map { |e| e["pid"] }.to_set
    list = entries.dup
    grown = true
    while grown
      grown = false
      snapshot.each do |p|
        next if pids.include?(p.pid) || !pids.include?(p.ppid) || p.pid == Process.pid

        pids << p.pid
        list << { "pid" => p.pid, "started" => p.started, "command" => p.command.to_s.truncate(MAX_COMMAND) }
        grown = true
      end
    end
    list
  end

  def self.signal(entries, name)
    entries.each do |e|
      next if e["pid"].to_i <= 1 || e["pid"] == Process.pid

      Process.kill(name, e["pid"])
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end

  def self.mark_stopped(dir, targets)
    list = load(dir)
    return if list.empty?

    keys = targets.map { |e| key(e["pid"], e["started"]) }.to_set
    list.each { |e| e["alive"] = false if keys.include?(key(e["pid"], e["started"])) }
    write(dir, list)
  end

  def self.write(dir, list)
    file = path(dir)
    FileUtils.rm_f("#{file}.tmp")
    File.open("#{file}.tmp", File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |f| f.write(list.to_json) }
    File.rename("#{file}.tmp", file)
  rescue SystemCallError => e
    Rails.logger.error("[processes] #{dir}: #{e.class}: #{e.message}")
  end

  private

  def save = self.class.write(@dir, @tracked.values)

  # Never Agentaro itself, launchd, or the session the server runs in.
  def excluded?(p) = p.pid <= 1 || p.pid == Process.pid || excluded_groups.include?(p.pgid)
  def excluded_groups = @excluded_groups ||= Set[0, 1, Process.getpgrp]

  def clean(command)
    text = RunTrace.redact(command.to_s).first
    text.length > MAX_COMMAND ? "#{text[0, MAX_COMMAND]}…" : text
  end
end
