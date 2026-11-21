require "test_helper"
require "open3"
require "tmpdir"

# Spec 035: the behaviour of the microphone mute toggle. The real voice() function from chat.js runs in
# JavaScriptCore (jsc, part of macOS) with a fake panel, microphone, AudioContext and fetch
# (test/javascript/voice_harness.js); the scenarios are in voice_mute_scenarios.js. No gem, no npm, no browser.
class VoiceMuteTest < ActiveSupport::TestCase
  JSC = ENV.fetch("AGENTARO_JSC", "/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc")
  DIR = Rails.root.join("test/javascript")

  # voice() is a nested function of chat.js: from its first line to the first closing brace at the same indent.
  def self.voice_source
    lines = Rails.root.join("app/assets/javascripts/chat.js").read.lines
    first = lines.index("  function voice(app, chat) {\n") or raise "voice() not found in chat.js"
    last = (first...lines.size).find { |i| lines[i] == "  }\n" } or raise "end of voice() not found in chat.js"
    lines[first..last].join
  end

  def run_scenario(name)
    skip "JavaScriptCore (jsc) not found at #{JSC}; set AGENTARO_JSC" unless File.executable?(JSC)
    Dir.mktmpdir do |dir|
      voice = File.join(dir, "voice.js")
      File.write(voice, self.class.voice_source)
      output, status = Open3.capture2e(JSC, DIR.join("voice_harness.js").to_s, voice, DIR.join("voice_mute_scenarios.js").to_s, "--", name)
      assert status.success?, output
      assert_equal "ok", output.strip, "scenario #{name}"
    end
  end

  test "voice() is cut out of chat.js whole" do
    source = self.class.voice_source
    assert_includes source, "function setMuted(value)"
    assert source.rstrip.end_with?("return { end };\n  }"), "the cut ends where voice() ends"
  end

  test "S1: while muted nothing is recorded or sent, not by a pause, the 30 s limit or Done" do
    run_scenario "S1"
  end

  test "S2, S3: muting discards the utterance in progress; after unmuting the next one is sent alone and answered" do
    run_scenario "S2"
  end

  test "S5: the director's answer plays to the end while muted, and the panel stays muted after it" do
    run_scenario "S5"
  end

  test "R9: ending voice mode clears the mute and the buffers" do
    run_scenario "R9"
  end

  test "the toggle does nothing while voice mode is off" do
    run_scenario "off"
  end
end
