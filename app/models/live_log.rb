# Spec 038: what a running step does, readable while it runs — a file in the run's own folder, so the web threads
# (and a restart) can read it. Events (Claude Code, Codex) are appended one JSON line each; text (Ollama, LM Studio)
# is the latest snapshot. Secrets are replaced before anything is written (R5, as in the trace). The file goes when
# the trace is saved (the trace is then the record); an interrupted run keeps it.
class LiveLog
  EVENTS = "live.jsonl"
  TEXT = "live.txt"
  MAX_EVENTS = ClaudeStream::MAX_EVENTS
  MAX_FIELD = 2048        # bytes kept of each field; the view shows 300 characters (R3)
  MAX_TEXT = 16 * 1024    # the text's tail kept
  TEXT_EVERY = 0.5        # seconds between text snapshots
  # B20 (spec 038): links are never followed, written through or read — a file planted in the run's folder cannot
  # send Agentaro's writes, or the view's reads, somewhere else.
  WRITE_FLAGS = File::WRONLY | File::CREAT | File::NOFOLLOW

  def self.dir_for(run_id, runs_dir: Rails.application.config.x.runs_dir) = Pathname(runs_dir).join(run_id.to_i.to_s)

  def initialize(dir)
    @dir = Pathname(dir)
    @count = 0
    @text_at = 0.0
  end

  def add(event)
    return if (@count += 1) > MAX_EVENTS

    clean = event.to_h.transform_keys(&:to_s).transform_values { |v| v.is_a?(String) ? field(v) : v }
    File.open(@dir.join(EVENTS), WRITE_FLAGS | File::APPEND, 0o600) { |f| f.write(clean.to_json + "\n") }
  rescue StandardError => e # never breaks the run (as spec 030, R7)
    Rails.logger.error("[live] #{@dir}: #{e.class}: #{e.message}")
  end

  def text(value, force: false)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return unless force || now - @text_at >= TEXT_EVERY

    @text_at = now
    tail = value.to_s
    tail = tail.byteslice(-MAX_TEXT, MAX_TEXT).scrub("") if tail.bytesize > MAX_TEXT
    path = @dir.join(TEXT)
    FileUtils.rm_f("#{path}.tmp")
    File.open("#{path}.tmp", WRITE_FLAGS | File::EXCL, 0o600) { |f| f.write(RunTrace.redact(tail).first) }
    File.rename("#{path}.tmp", path)
  rescue StandardError => e
    Rails.logger.error("[live] #{@dir}: #{e.class}: #{e.message}")
  end

  def clear!
    [ EVENTS, TEXT ].each { |name| FileUtils.rm_f(@dir.join(name)) }
  end

  # { events: [...], text: "..." } from the files, or nil when there are none. A line still being written is skipped.
  def self.read(dir)
    dir = Pathname(dir)
    events_path, text_path = dir.join(EVENTS), dir.join(TEXT)
    return unless regular?(events_path) || regular?(text_path)

    events = regular?(events_path) ? File.foreach(events_path).first(MAX_EVENTS).filter_map { |line| JSON.parse(line) rescue nil } : []
    { events: events, text: (File.read(text_path, MAX_TEXT * 2) if regular?(text_path)) }
  end

  def self.regular?(path)
    File.lstat(path).file?
  rescue SystemCallError
    false
  end

  private

  def field(value)
    text = RunTrace.redact(value).first
    text.bytesize > MAX_FIELD ? text.byteslice(0, MAX_FIELD).scrub("") + "…" : text
  end
end
