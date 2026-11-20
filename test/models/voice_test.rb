require "test_helper"

# Spec 017: speech on the host (stand-in programs), streamed answers (ClaudeStream, partial reply).
class VoiceTest < ActiveSupport::TestCase
  WAV = "RIFF\x24\x00\x00\x00WAVEfmt ".b + ("\x00".b * 40)

  # Stand-in whisper-cli and piper: record their arguments and standard input, answer like the real tools.
  def with_tools(transcript: "Cześć Anna", fail: false)
    Dir.mktmpdir do |dir|
      model, voice = File.join(dir, "model.bin"), File.join(dir, "voice.onnx")
      File.write(model, "m"); File.write(voice, "v")
      File.write(File.join(dir, "whisper"), <<~SH)
        #!/bin/sh
        echo "$@" > "#{dir}/whisper-args"
        cp "$4" "#{dir}/heard.wav"
        #{fail ? "exit 2" : "printf '\\n #{transcript}\\n [BLANK_AUDIO]\\n'"}
      SH
      File.write(File.join(dir, "piper"), <<~SH)
        #!/bin/sh
        cat > "#{dir}/said.txt"
        echo "$@" > "#{dir}/piper-args"
        printf 'RIFFxxxxWAVEdata' > "$4"
      SH
      %w[whisper piper].each { |f| File.chmod(0o755, File.join(dir, f)) }
      original = Rails.application.config.x.voice
      Rails.application.config.x.voice = { whisper_bin: File.join(dir, "whisper"), whisper_model: model, piper_bin: File.join(dir, "piper"), piper_voice: voice }
      yield dir
    ensure
      Rails.application.config.x.voice = original
    end
  end

  test "G3, R3: transcription runs whisper with fixed arguments, drops noise notes and removes the audio" do
    with_tools do |dir|
      assert_equal "Cześć Anna", Voice.transcribe(WAV)
      args = File.read(File.join(dir, "whisper-args"))
      assert_match "-l auto -nt -np -sns", args
      heard = args[/-f (\S+)/, 1]
      assert_not File.exist?(heard), "the temporary audio is deleted"
      assert_equal WAV, File.binread(File.join(dir, "heard.wav"))
    end
  end

  test "owner fix (recognition): whisper is told Agentaro's words and the team's names; a hint repeated on silence is dropped" do
    user = create_user
    user.team_roles.create!(agent: Agent.create!(user: user, name: "Market Analyst", master_prompt: "x", executor: Executor.create!(name: "C", preset: "claude_code")), role: "director")
    names = Voice.names_for(user)
    assert_equal [ "Market Analyst" ], names
    with_tools do |dir|
      Voice.transcribe(WAV, language: "pl", names: names + [ "Evil\nName" ])
      args = File.read(File.join(dir, "whisper-args"))
      assert_match "--prompt Rozmowa z dyrektorem w Agentaro o epikach", args
      assert_match "Market Analyst, Evil Name.", args, "names go in one line, without control characters"
    end
    with_tools(transcript: "Rozmowa z dyrektorem w Agentaro o epikach, specach") do
      assert_equal "", Voice.transcribe(WAV, language: "pl"), "only the hint came back: silence"
    end
    assert_operator Voice.hint("pl", [ "x" * 100 ] * 20).length, :<=, Voice::MAX_HINT
  end

  test "owner fix after spec 017: the language goes to whisper; the voice follows the language" do
    with_tools do |dir|
      Voice.transcribe(WAV, language: "pl")
      assert_match "-l pl -nt -np -sns", File.read(File.join(dir, "whisper-args"))
      Voice.transcribe(WAV, language: "xx; rm")
      assert_match "-l auto -nt", File.read(File.join(dir, "whisper-args")), "only known languages reach whisper"
      english = File.join(dir, "en.onnx")
      File.write(english, "e")
      Rails.application.config.x.voice = Rails.application.config.x.voice.merge(piper_voice_en: english)
      Voice.speak("Good morning", language: "en")
      assert_match english, File.read(File.join(dir, "piper-args"))
      Voice.speak("Dzień dobry", language: "auto")
      assert_match "voice.onnx", File.read(File.join(dir, "piper-args")), "auto: Polish text, Polish voice"
      Voice.speak("Good morning", language: "auto")
      assert_match english, File.read(File.join(dir, "piper-args"))
    end
  end

  test "owner fix after spec 017: emoji, smileys and Markdown are not read aloud" do
    assert_equal "Gotowe! Plan jest w kalendarzu.", Voice.readable("**Gotowe!** 🎉 Plan jest w kalendarzu 😊.")
    assert_equal "Super, dzięki!", Voice.readable("Super :) , dzięki ;-)!")
    assert_equal "Lista: pierwszy punkt", Voice.readable("# Lista:\n- pierwszy `punkt` 👍🏽")
    assert_equal "Godzina 10:30, kurs 3:2.", Voice.readable("Godzina 10:30, kurs 3:2."), "times and scores stay"
    assert_equal "Na e-mail: a_b@x.pl", Voice.readable("Na e-mail: a_b@x.pl")
    with_tools { assert_raises(Voice::Error) { Voice.speak("😊 :)") } }
  end

  test "spec 019: the verifier speaks with its own voice, or the main one when it has none" do
    with_tools do |dir|
      own = File.join(dir, "verifier.onnx")
      Voice.speak("Sprawdzam", language: "pl", speaker: "verifier")
      assert_match "voice.onnx", File.read(File.join(dir, "piper-args")), "no own voice: the main one"
      File.write(own, "v")
      Rails.application.config.x.voice = Rails.application.config.x.voice.merge(piper_voice_verifier: own)
      Voice.speak("Sprawdzam", language: "pl", speaker: "verifier")
      assert_match own, File.read(File.join(dir, "piper-args"))
      Voice.speak("Dzień dobry", language: "pl", speaker: "anything else")
      assert_no_match own, File.read(File.join(dir, "piper-args"))
    end
  end

  test "owner fix: phantom sentences from silence or noise are dropped; real speech stays" do
    assert_equal "", Voice.without_phantoms("Wszystkie prawa zastrzeżone.")
    assert_equal "", Voice.without_phantoms("Napisy stworzone przez społeczność Amara.org. Dziękuję za obejrzenie!")
    assert_equal "", Voice.without_phantoms("Thanks for watching! ♪")
    assert_equal "", Voice.without_phantoms("KONIEC"), "heard from plain noise on the host"
    assert_equal "Koniec na dziś, dzięki.", Voice.without_phantoms("Koniec na dziś, dzięki.")
    assert_equal "Dodaj epik o remoncie kuchni.", Voice.without_phantoms("Dodaj epik o remoncie kuchni. Wszystkie prawa zastrzeżone.")
    assert_equal "Sprawdź, czy w umowie jest klauzula, że wszystkie prawa zastrzeżone są po stronie wydawcy.",
                 Voice.without_phantoms("Sprawdź, czy w umowie jest klauzula, że wszystkie prawa zastrzeżone są po stronie wydawcy."), "a real sentence that mentions it stays"
    with_tools(transcript: "Wszystkie prawa zastrzeżone.") { assert_equal "", Voice.transcribe(WAV) }
  end

  test "owner fix: speech speed becomes Piper's length scale (1.5x by default, 1x to 2x)" do
    with_tools do |dir|
      Voice.speak("Szybciej")
      assert_match "--length-scale 0.58", File.read(File.join(dir, "piper-args"))
      Voice.speak("Szybciej", speed: 2.0)
      assert_match "--length-scale 0.39", File.read(File.join(dir, "piper-args"))
      Voice.speak("Szybciej", speed: 9)
      assert_match "--length-scale 0.39", File.read(File.join(dir, "piper-args")), "never beyond 2x"
    end
  end

  test "R1: only WAV, at most 2 MB" do
    with_tools do
      assert_raises(Voice::Error) { Voice.transcribe("OggS....") }
      assert_raises(Voice::Error) { Voice.transcribe(WAV + ("\x00".b * Voice::MAX_AUDIO)) }
    end
  end

  test "G5, R2: speech gets the text on standard input, never in the arguments; at most 600 characters" do
    with_tools do |dir|
      audio = Voice.speak("Dzień dobry;\u0007 rm -rf /")
      assert audio.start_with?("RIFF")
      assert_equal "Dzień dobry; rm -rf /", File.read(File.join(dir, "said.txt"))
      assert_no_match "rm -rf", File.read(File.join(dir, "piper-args"))
      assert_raises(Voice::Error) { Voice.speak("x" * 601) }
      assert_raises(Voice::Error) { Voice.speak(" ") }
    end
  end

  test "G7: missing tools are reported, not run" do
    original = Rails.application.config.x.voice
    Rails.application.config.x.voice = original.merge(whisper_bin: "/nonexistent/whisper", piper_voice: "/nonexistent/voice.onnx")
    assert_not Voice.listening?
    assert_not Voice.speaking?
    assert_raises(Voice::Error) { Voice.transcribe(WAV) }
  ensure
    Rails.application.config.x.voice = original
  end

  test "G4: Claude's stream-json is joined as it arrives; the result line is the answer" do
    seen = []
    stream = ClaudeStream.new(->(text) { seen << text.dup })
    assert_equal [ "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--x" ], stream.arguments([ "-p", "--output-format", "text", "--x" ])
    lines = [ { type: "system" }, { type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text: "{\"reply\": \"Dzie" } } },
              { type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text: "ń dobry\"}" } } },
              { type: "result", result: "{\"reply\": \"Dzień dobry\"}" } ].map(&:to_json).join("\n") + "\n"
    out = lines.b
    stream.feed(out.byteslice(0, 70)); stream.feed(out.byteslice(70..)) # split mid-line and mid-character
    assert_equal [ "{\"reply\": \"Dzie", "{\"reply\": \"Dzień dobry\"}" ], seen
    assert_equal "{\"reply\": \"Dzień dobry\"}", stream.answer(out)
    assert_equal "plain", ClaudeStream.new(->(_) {}).answer("plain"), "nothing streamed: the plain output"
  end

  test "G4: the reply so far is decoded from partial JSON" do
    assert_equal "", ReplyStream.partial_reply("{\"actions\": [")
    assert_equal "Cześć,\nnowa \"linia\" ż", ReplyStream.partial_reply("```json\n{\"reply\": \"Cze\\u015b\\u0107,\\nnowa \\\"linia\\\" \\u017c")
    assert_equal "Ab", ReplyStream.partial_reply("{\"reply\": \"Ab\\u01")
    assert_equal "Done", ReplyStream.partial_reply("{\"reply\": \"Done\", \"actions\": []}")
  end
end
