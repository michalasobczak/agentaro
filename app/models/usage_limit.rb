# Spec 043: what an executor's tool says about its subscription's usage limit, and what Agentaro does with it.
# A reading belongs to the executor (R1): its windows (5 hours, 7 days…) with the use in percent and the reset time,
# whether the limit is reached, and when it was read. It comes only from the tool's own output (R6):
# - Claude Code: the `rate_limit_event` line of its stream-json output, on every call;
# - Codex: `rate_limits` in its newest session log on this computer (`codex exec --json` does not stream them, and
#   Agentaro's own calls are ephemeral), and the limit message of a failed call;
# - any tool: the limit message of a failed call ("You've hit your 5-hour limit · resets 3:10pm").
class UsageLimit
  WINDOW_LABELS = { "five_hour" => "5 h", "seven_day" => "7 days", "seven_day_opus" => "7 days (Opus)",
                    "seven_day_sonnet" => "7 days (Sonnet)", "300" => "5 h", "10080" => "7 days" }.freeze
  WINDOW_WORDS = { "five_hour" => "5-hour", "seven_day" => "weekly", "seven_day_opus" => "weekly Opus", "seven_day_sonnet" => "weekly Sonnet" }.freeze
  LONGEST_WINDOW = 7.days # the longest limit window the tools have
  UNKNOWN_RESET = 1.hour # R2: a reached limit with no reset time counts as reached for an hour
  CODEX_TAIL = 512 * 1024

  # --- Readings ---------------------------------------------------------------------------------------------------

  # Claude Code's rate_limit_info → a reading, or nil when the event has no usable data.
  def self.from_claude(info)
    return unless info.is_a?(Hash)

    windows = (info["unifiedWindows"].is_a?(Hash) ? info["unifiedWindows"] : {}).filter_map do |name, w|
      next unless w.is_a?(Hash)

      { "name" => name.to_s, "used" => percent(w["utilization"].is_a?(Numeric) ? w["utilization"] * 100 : nil),
        "resets_at" => epoch(w["resetsAt"]), "reached" => w["status"] == "rejected" }
    end
    reached = info["status"] == "rejected" || windows.any? { |w| w["reached"] }
    window = info["rateLimitType"].to_s.presence || windows.find { |w| w["reached"] }&.dig("name")
    { "windows" => windows, "reached" => reached, "window" => (window if reached),
      "resets_at" => (reached ? epoch(info["resetsAt"]) || windows.find { |w| w["reached"] }&.dig("resets_at") : nil) }
  end

  # Codex's rate_limits (primary, secondary) → a reading.
  def self.from_codex(limits)
    return unless limits.is_a?(Hash)

    windows = %w[primary secondary].filter_map do |key|
      w = limits[key]
      next unless w.is_a?(Hash)

      used = percent(w["used_percent"])
      { "name" => w["window_minutes"].to_s, "used" => used, "resets_at" => epoch(w["resets_at"]), "reached" => used.to_f >= 100 }
    end
    return if windows.empty?

    hit = windows.select { |w| w["reached"] }.max_by { |w| w["resets_at"].to_s }
    { "windows" => windows, "reached" => hit.present?, "window" => hit&.dig("name"), "resets_at" => hit&.dig("resets_at") }
  end

  # The newest rate_limits Codex wrote to a session log on this computer, with the file's time; nil when none.
  def self.codex_session_reading(home: ENV["CODEX_HOME"].presence || File.join(Dir.home, ".codex"), now: Time.current)
    dirs = [ now, now - 1.day ].map { |day| File.join(home, "sessions", day.strftime("%Y/%m/%d")) }.uniq
    file = dirs.flat_map { |dir| Dir.glob(File.join(dir, "rollout-*.jsonl")) }.max_by { |f| File.mtime(f) } or return
    text = File.open(file, "rb") { |f| f.seek([ f.size - CODEX_TAIL, 0 ].max); f.read }.force_encoding(Encoding::UTF_8).scrub("")
    text.lines.reverse_each do |line|
      next unless line.include?("\"rate_limits\"")

      data = JSON.parse(line) rescue next
      limits = find_key(data, "rate_limits") or next
      reading = from_codex(limits) or next
      return [ reading, File.mtime(file) ]
    end
    nil
  rescue SystemCallError, IOError
    nil
  end

  # --- A failed call ----------------------------------------------------------------------------------------------

  # G3: the plain message for a call that ended on a usage limit, or nil when it did not. `text` is the tool's own
  # output (its final answer and errors); `reading` the stream's limit event, when there was one.
  def self.failure(label, text, reading: nil, now: Time.current)
    text = text.to_s
    reached = reading&.dig("reached") || text.last(4000).match?(StepRetry::USAGE_LIMIT)
    return unless reached

    reset = time(reading&.dig("resets_at")) || StepRetry.reset_time(text.last(4000), now: now)
    reset = nil if reset && reset > now + LONGEST_WINDOW # B20: a reset beyond the longest window is not believed
    window = WINDOW_WORDS[reading&.dig("window").to_s] || text[/\b(\d+-hour|weekly|daily|monthly)\b/i, 1]&.downcase
    message = "#{label}: #{[ window, "usage limit reached" ].compact.join(" ")}#{" until #{clock(reset, now)}" if reset}."
    { message: message, resets_at: reset, reading: (reading || { "windows" => [] }).merge("reached" => true, "resets_at" => (reset || now + UNKNOWN_RESET).iso8601) }
  end

  # --- The executor -----------------------------------------------------------------------------------------------

  # R1: a newer reading replaces the older one; a reading without windows keeps the windows known before.
  def self.record!(executor, reading, at: Time.current)
    return unless executor && reading
    return if executor.usage_read_at && executor.usage_read_at > at

    old = read(executor)
    reading = reading.merge("windows" => old["windows"]) if reading["windows"].blank? && old
    executor.update!(usage_limits: reading.to_json, usage_read_at: at)
  rescue StandardError => e
    Rails.logger.error("[limits] executor #{executor&.id}: #{e.class}: #{e.message}")
  end

  def self.read(executor)
    data = JSON.parse(executor.usage_limits.to_s)
    data.is_a?(Hash) ? data : nil
  rescue JSON::ParserError
    nil
  end

  # R2: until when the executor is at a reached limit, or nil.
  def self.until(executor, now: Time.current)
    data = executor && read(executor) or return
    return unless data["reached"]

    at = time(data["resets_at"]) || (executor.usage_read_at && executor.usage_read_at + UNKNOWN_RESET)
    at = [ at, (executor.usage_read_at || now) + LONGEST_WINDOW ].min if at # B20: never longer than a window
    at if at && at > now
  end

  # G2: "5 h: 42 %, resets 15:10 · 7 days: 18 %, resets 24 Nov 08:00".
  def self.summary(executor, now: Time.current)
    data = executor && read(executor) or return
    data["windows"].to_a.map do |w|
      reset = time(w["resets_at"])
      "#{WINDOW_LABELS.fetch(w["name"].to_s, w["name"])}: #{w["used"] ? "#{w["used"].round} %" : "?"}#{", resets #{clock(reset, now, words: true)}" if reset && reset > now}"
    end.join(" · ").presence
  end

  def self.reached_note(executor, now: Time.current)
    at = self.until(executor, now: now) or return
    "usage limit reached until #{clock(at, now)}"
  end

  # "15:10" today, else "2026-11-24 15:10" (StepRetry.reset_time reads both back); words: "24 Nov 15:10".
  def self.clock(at, now = Time.current, words: false)
    at = at.in_time_zone
    return at.strftime("%H:%M") if at.to_date == now.in_time_zone.to_date

    at.strftime(words ? "%-d %b %H:%M" : "%Y-%m-%d %H:%M")
  end

  def self.percent(value) = value.is_a?(Numeric) ? value.to_f.clamp(0, 100).round(1) : nil
  def self.epoch(value) = value.is_a?(Numeric) && value.positive? ? Time.zone.at(value).iso8601 : nil
  def self.time(value) = value.present? ? (Time.zone.parse(value.to_s) rescue nil) : nil

  def self.find_key(data, key)
    case data
    when Hash then data.key?(key) ? data[key] : data.each_value.lazy.filter_map { |v| find_key(v, key) }.first
    when Array then data.lazy.filter_map { |v| find_key(v, key) }.first
    end
  end
  private_class_method :find_key
end
