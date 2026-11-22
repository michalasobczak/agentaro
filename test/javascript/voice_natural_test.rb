require "test_helper"
require "open3"
require "tmpdir"
require_relative "voice_mute_test"

# Spec 046, G4 (the acknowledgement) and spec 045, G4 (the spoken summary): the real voice() from chat.js in
# JavaScriptCore, with the fakes of the spec 035 harness.
class VoiceNaturalTest < ActiveSupport::TestCase
  def run_scenario(name)
    skip "JavaScriptCore (jsc) not found at #{VoiceMuteTest::JSC}" unless File.executable?(VoiceMuteTest::JSC)
    Dir.mktmpdir do |dir|
      voice = File.join(dir, "voice.js")
      File.write(voice, VoiceMuteTest.voice_source)
      output, status = Open3.capture2e(VoiceMuteTest::JSC, VoiceMuteTest::DIR.join("voice_harness.js").to_s, voice,
                                       VoiceMuteTest::DIR.join("voice_natural_scenarios.js").to_s, "--", name)
      assert status.success?, output
      assert_equal "ok", output.strip, "scenario #{name}"
    end
  end

  test("S3: two seconds without a reply give one acknowledgement") { run_scenario "ack" }
  test("S3: a reply that starts sooner gets none") { run_scenario "no-ack-when-replying" }
  test("negative: no acknowledgement in the Zwykła mode") { run_scenario "no-ack-plain" }
  test("spec 045, G4: a summary arriving while the voice listens is read aloud") { run_scenario "summary" }
end
