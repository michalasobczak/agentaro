require "test_helper"

# Spec 046, G3, S2, R2: text made ready to be spoken, and the livelier voice of the Naturalna mode.
class SpeechTextTest < ActiveSupport::TestCase
  test "S2: times, numbers, dates and percent become Polish words; paths, links and ids are left out" do
    assert_equal "Krok dwa skończy się o piętnastej dziesięć, plik", SpeechText.prepare("Krok 2 skończy się o 15:10, plik /tmp/a.md", "pl")
    assert_equal "Start dwudziestego czwartego listopada o ósmej zero pięć.", SpeechText.prepare("Start 2026-11-24 o 8:05.", "pl")
    assert_equal "Spotkanie: dwudziesta pierwsza. Gotowe w czterdzieści dwa procent.", SpeechText.prepare("Spotkanie: 21:00. Gotowe w 42%.", "pl")
    assert_equal "Do drugiej trzydzieści.", SpeechText.prepare("Do 2:30.", "pl")
    assert_equal "Zobacz epik.", SpeechText.prepare("Zobacz epik (id 12) https://example.com/x.", "pl")
  end

  test "English: times with AM/PM, dates and numbers in words" do
    assert_equal "Step two ends at three ten PM on November twenty-four.", SpeechText.prepare("Step 2 ends at 15:10 on 2026-11-24.", "en")
  end

  test "R2: unknown forms stay as they are" do
    assert_equal "Wersja v2, 3pm i 1234 sztuk, 3.5 GB.", SpeechText.prepare("Wersja v2, 3pm i 1234 sztuk, 3.5 GB.", "pl")
  end
end

class NaturalVoiceTest < ActiveSupport::TestCase
  def with_piper
    Dir.mktmpdir do |dir|
      voice = File.join(dir, "voice.onnx")
      File.write(voice, "v")
      File.write(File.join(dir, "piper"), "#!/bin/sh\ncat > \"#{dir}/said.txt\"\necho \"$@\" > \"#{dir}/piper-args\"\necho x >> \"#{dir}/runs\"\nprintf 'RIFFxxxxWAVEdata' > \"$4\"\n")
      File.chmod(0o755, File.join(dir, "piper"))
      original = Rails.application.config.x.voice
      Rails.application.config.x.voice = original.merge(piper_bin: File.join(dir, "piper"), piper_voice: voice)
      yield dir
    ensure
      Rails.application.config.x.voice = original
    end
  end

  test "G3: Naturalna speaks the prepared text with livelier settings; Zwykła is unchanged" do
    with_piper do |dir|
      Voice.speak("Do 15:10.", language: "pl", natural: true)
      assert_equal "Do piętnastej dziesięć.", File.read(File.join(dir, "said.txt"))
      assert_match "--noise-scale 0.667 --noise-w-scale 0.8 --sentence-silence 0.25", File.read(File.join(dir, "piper-args"))
      Voice.speak("Do 15:10.", language: "pl")
      assert_equal "Do 15:10.", File.read(File.join(dir, "said.txt"))
      assert_no_match(/noise/, File.read(File.join(dir, "piper-args")))
    end
  end

  test "G4: an acknowledgement's sound is made once and kept" do
    FileUtils.rm_rf(Rails.root.join("tmp", "voice"))
    with_piper do |dir|
      2.times { assert Voice.speak("Chwilka.", language: "pl", natural: true).start_with?("RIFF") }
      assert_equal 1, File.read(File.join(dir, "runs")).lines.size
      Voice.speak("Inne zdanie.", language: "pl", natural: true)
      assert_equal 2, File.read(File.join(dir, "runs")).lines.size, "other text is never kept"
    end
  ensure
    FileUtils.rm_rf(Rails.root.join("tmp", "voice"))
  end
end
