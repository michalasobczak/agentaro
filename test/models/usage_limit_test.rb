require "test_helper"

# Spec 043, G1–G3: reading the subscription's usage limit from the tools, and the plain message of a failed call.
class UsageLimitTest < ActiveSupport::TestCase
  CLAUDE_EVENT = { "type" => "rate_limit_event", "rate_limit_info" => {
    "status" => "allowed", "resetsAt" => 1_795_374_600, "rateLimitType" => "five_hour",
    "unifiedWindows" => { "five_hour" => { "utilization" => 0.42, "resetsAt" => 1_795_374_600, "status" => "allowed" },
                          "seven_day" => { "utilization" => 0.18, "resetsAt" => 1_795_896_000, "status" => "allowed" } } } }.freeze

  setup { @executor = Executor.create!(name: "Claude", preset: "claude_code") }

  test "S1: Claude Code's stream event becomes a reading with its windows" do
    stream = ClaudeStream.new
    stream.feed("#{CLAUDE_EVENT.to_json}\n#{{ type: "result", result: "ok" }.to_json}\n")
    reading = stream.limit_reading
    assert_equal [ [ "five_hour", 42.0 ], [ "seven_day", 18.0 ] ], reading["windows"].map { |w| [ w["name"], w["used"] ] }
    assert_equal false, reading["reached"]
    travel_to Time.zone.at(1_795_360_000) do
      UsageLimit.record!(@executor, reading)
      assert_match(/\A5 h: 42 %, resets \d\d:\d\d · 7 days: 18 %, resets \d+ \w+ \d\d:\d\d\z/, UsageLimit.summary(@executor.reload))
      assert_nil UsageLimit.until(@executor)
    end
  end

  test "a rejected Claude Code event marks the limit as reached until its reset" do
    info = CLAUDE_EVENT["rate_limit_info"].merge("status" => "rejected")
    info["unifiedWindows"] = info["unifiedWindows"].merge("five_hour" => { "utilization" => 1.0, "resetsAt" => 1_795_374_600, "status" => "rejected" })
    reading = UsageLimit.from_claude(info)
    assert_equal [ true, "five_hour", Time.zone.at(1_795_374_600).iso8601 ], reading.values_at("reached", "window", "resets_at")
    travel_to Time.zone.at(1_795_370_000) do
      UsageLimit.record!(@executor, reading)
      assert_equal Time.zone.at(1_795_374_600), UsageLimit.until(@executor.reload)
    end
    travel_to Time.zone.at(1_795_374_601) { assert_nil UsageLimit.until(@executor), "R2: after the reset it is free again" }
  end

  test "Codex's rate_limits from its newest session log (spec 043, Q1)" do
    Dir.mktmpdir do |home|
      now = Time.zone.local(2026, 11, 22, 15, 0)
      dir = File.join(home, "sessions", "2026/11/22")
      FileUtils.mkdir_p(dir)
      line = { type: "event_msg", payload: { type: "token_count", rate_limits: { primary: { used_percent: 8.0, window_minutes: 300, resets_at: 1_795_376_929 },
                                                                                secondary: { used_percent: 100.0, window_minutes: 10_080, resets_at: 1_795_963_729 } } } }
      File.write(File.join(dir, "rollout-2026-11-22T15-00-00-x.jsonl"), "#{{ type: "session_meta" }.to_json}\n#{line.to_json}\n")
      reading, at = UsageLimit.codex_session_reading(home: home, now: now)
      assert_equal [ [ "300", 8.0 ], [ "10080", 100.0 ] ], reading["windows"].map { |w| [ w["name"], w["used"] ] }
      assert_equal [ true, "10080" ], reading.values_at("reached", "window")
      assert at
    end
    Dir.mktmpdir { |home| assert_nil UsageLimit.codex_session_reading(home: home) }
  end

  test "S2, G3: a limit message becomes the plain message, read back by the retry rules" do
    travel_to Time.zone.local(2026, 11, 22, 12, 4) do
      failure = UsageLimit.failure("Claude Code", "You've hit your 5-hour limit · resets 3:10pm (Europe/Warsaw)")
      assert_equal "Claude Code: 5-hour usage limit reached until 15:10.", failure[:message]
      assert_equal Time.zone.local(2026, 11, 22, 15, 10), StepRetry.reset_time(failure[:message])
      assert_equal true, failure[:reading]["reached"]
      tomorrow = UsageLimit.failure("Codex", "You've hit your usage limit. Try again in 2 days 1 hour.")
      assert_equal "Codex: usage limit reached until 2026-11-24 13:04.", tomorrow[:message]
      assert_equal Time.zone.local(2026, 11, 24, 13, 4), StepRetry.reset_time(tomorrow[:message])
      assert_equal "Claude Code: usage limit reached.", UsageLimit.failure("Claude Code", "Too many requests")[:message]
      assert_nil UsageLimit.failure("Claude Code", "npm ERR! missing script: build")
    end
  end

  test "S2: a Claude Code call that hits its limit fails with the plain message and marks its executor" do
    agent = Agent.create!(user: create_user, name: "A", master_prompt: "x", executor: @executor)
    run = TaskRun.create!(user: agent.user, agent: agent, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat >/dev/null\necho '#{{ type: "result", is_error: true, result: "You've hit your 5-hour limit · resets 11pm (Europe/Warsaw)" }.to_json}'\nexit 1\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      travel_to Time.zone.local(2026, 11, 22, 12, 0) do
        outcome = AgentCall.new(run, agent, AgentCall::Prompt.new(system: "s", user: "u")).call
        assert_equal [ "failed", "Claude Code: 5-hour usage limit reached until 23:00." ], [ outcome.state, outcome.error ]
        assert_equal Time.zone.local(2026, 11, 22, 23, 0), UsageLimit.until(@executor.reload)
        assert_equal 0, DataChange.where(record_type: "Executor", action: "update").count, "readings are bookkeeping, not data changes"
      end
    ensure
      ENV["PATH"] = original
    end
  end

  test "negative, R6: a successful answer that talks about a limit marks nothing" do
    agent = Agent.create!(user: create_user, name: "A", master_prompt: "x", executor: @executor)
    run = TaskRun.create!(user: agent.user, agent: agent, purpose: "chat", trigger: "manual", occurrence_start: Time.current, state: "queued")
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\ncat >/dev/null\necho 'The API rate limit reached its quota; try again in 2 hours.'\n")
      File.chmod(0o755, File.join(bin, "claude"))
      original = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{original}"
      outcome = AgentCall.new(run, agent, AgentCall::Prompt.new(system: "s", user: "u")).call
      assert_equal "succeeded", outcome.state
      assert_nil UsageLimit.until(@executor.reload)
    ensure
      ENV["PATH"] = original
    end
  end

  test "B20: a reset far beyond the longest window is not believed; the limit counts for an hour" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      failure = UsageLimit.failure("Claude Code", "Usage limit reached. Try again in 99 days.")
      assert_equal "Claude Code: usage limit reached.", failure[:message]
      UsageLimit.record!(@executor, failure[:reading])
      assert_equal Time.zone.local(2026, 11, 22, 13, 0), UsageLimit.until(@executor.reload)
      UsageLimit.record!(@executor, { "windows" => [], "reached" => true, "resets_at" => 1.year.from_now.iso8601 }, at: Time.current + 1)
      assert_equal Time.current + 1 + 7.days, UsageLimit.until(@executor.reload)
    end
  end
end
