# Spec 017: speech on the host — whisper.cpp turns the user's voice into text, Piper reads the director's answer.
# Both run as separate programs: no shell, fixed arguments, a timeout, the minimal environment (HostProcess);
# audio lives only in a private temporary folder that is deleted at once (R3). Nothing leaves the host.
class Voice
  Error = Class.new(StandardError)
  MAX_AUDIO = 2 * 1024 * 1024 # bytes (R1): about 60 s of 16 kHz mono WAV
  MAX_TEXT = 600              # characters per speech request (R2)
  NOISE = /\A[\[(][^\])]*[\])]\z/ # whisper's notes for silence or noise, e.g. [BLANK_AUDIO], (muzyka)
  # Owner fix after spec 017 ("nie czytaj uśmieszków"): emoji, text smileys and Markdown marks are not read aloud.
  EMOJI = /[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}\u200D\uFE0E\uFE0F\u20E3]/
  SMILEYS = /(?<![\p{L}\p{N}])[:;=8xX][-'^o]?[)(\]\[DPpOo3|\/\\*]+(?![\p{L}\p{N}])|(?<!\S)<3(?!\S)|(?<!\S)\^[_.]?\^(?!\S)/
  MARKDOWN = /\*\*|__|`+|^\s{0,3}[#]{1,6}\s+|^\s{0,3}>\s?|^\s*[-*+]\s+|(?<=\s|^)[*_](?=\S)|(?<=\S)[*_](?=\s|$|[.,!?;:])/

  def self.config = Rails.application.config.x.voice

  def self.listening? = File.executable?(config[:whisper_bin]) && File.file?(config[:whisper_model])
  def self.speaking? = File.executable?(config[:piper_bin]) && File.file?(config[:piper_voice])

  # Owner fix after spec 017: a voice per language; Polish is the main one, English is optional.
  # Spec 019, G6: the verifier speaks with its own voice when one is installed for the language.
  def self.voice_for(language, speaker = "director")
    if speaker == "verifier"
      own = config[language == "en" ? :piper_voice_verifier_en : :piper_voice_verifier]
      return own if own.present? && File.file?(own)
    end
    english = config[:piper_voice_en]
    language == "en" && english && File.file?(english) ? english : config[:piper_voice]
  end

  def self.english_voice? = config[:piper_voice_en].present? && File.file?(config[:piper_voice_en])

  # For "auto": Polish letters or common Polish words mean Polish, otherwise English.
  def self.guess_language(text)
    text.match?(/[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]|\b(jest|nie|się|już|czy|jak|to|na|w|z)\b/i) ? "pl" : "en"
  end

  # G3: WAV bytes in, text out ("" for silence or noise). language: "auto", "pl" or "en" (passed to whisper).
  def self.transcribe(audio, language: "auto")
    raise Error, "Speech recognition is not installed on this computer." unless listening?
    raise Error, "The recording is too long." if audio.bytesize > MAX_AUDIO
    raise Error, "The recording is not a WAV file." unless audio.byteslice(0, 4) == "RIFF" && audio.byteslice(8, 4) == "WAVE"

    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      File.binwrite(path, audio)
      result = HostProcess.run(config[:whisper_bin], [ "-m", config[:whisper_model], "-f", path, "-l", (%w[pl en].include?(language) ? language : "auto"), "-nt", "-np" ],
                               chdir: dir, timeout: 60, max_output: 64 * 1024)
      raise Error, "Speech recognition did not finish in time." if result.timed_out
      raise Error, "Speech recognition failed." unless result.success?

      result.stdout.to_s.force_encoding(Encoding::UTF_8).scrub("").lines.map(&:strip).reject { |l| l.empty? || l.match?(NOISE) }.join(" ").strip
    end
  end

  # What Piper may read: no control characters, emoji, smileys or Markdown marks.
  def self.readable(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
    text = text.gsub(MARKDOWN, "").gsub(EMOJI, "").gsub(SMILEYS, "")
    text.gsub(/[[:cntrl:]]+/, " ").gsub(/\s+([.,!?;:])/, "\\1").squeeze(" ").strip
  end

  # G5: text in, WAV bytes out, in the voice of the chosen language ("auto": guessed from the text).
  def self.speak(text, language: "auto", speaker: "director")
    raise Error, "The voice is not installed on this computer." unless speaking?

    text = readable(text)
    raise Error, "Nothing to say." if text.empty?
    raise Error, "At most #{MAX_TEXT} characters at a time." if text.length > MAX_TEXT

    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      voice = voice_for(%w[pl en].include?(language) ? language : guess_language(text), speaker.to_s == "verifier" ? "verifier" : "director")
      result = HostProcess.run(config[:piper_bin], [ "-m", voice, "-f", path ], stdin: text, chdir: dir, timeout: 30, max_output: 64 * 1024)
      raise Error, "The voice did not finish in time." if result.timed_out
      raise Error, "The voice failed." unless result.success? && File.file?(path)

      File.binread(path)
    end
  end
end
