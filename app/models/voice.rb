# Spec 017: speech on the host — whisper.cpp turns the user's voice into text, Piper reads the director's answer.
# Both run as separate programs: no shell, fixed arguments, a timeout, the minimal environment (HostProcess);
# audio lives only in a private temporary folder that is deleted at once (R3). Nothing leaves the host.
class Voice
  Error = Class.new(StandardError)
  MAX_AUDIO = 2 * 1024 * 1024 # bytes (R1): about 60 s of 16 kHz mono WAV
  MAX_TEXT = 600              # characters per speech request (R2)
  NOISE = /\A[\[(][^\])]*[\])]\z/ # whisper's notes for silence or noise, e.g. [BLANK_AUDIO], (muzyka)
  # Owner fix after spec 017 ("dodaj usuwanie szumów, żeby nie było 'wszystkie prawa zastrzeżone'"): sentences Whisper
  # invents on silence or noise (learnt from film subtitles). A sentence made only of such a phrase is dropped.
  PHANTOMS = Regexp.union(
    /wszystkie prawa zastrze[żz]one/i, /napisy (wykonane|stworzone|przygotowane|zrobione)( przez[^.!?]*)?/i, /amara\.org/i, /tvp\s*s\.?a\.?/i,
    /dzi[ęe]kuj[ęe] za (obejrzenie|uwag[ęe]|ogl[ąa]danie)/i, /dzi[ęe]ki za (obejrzenie|ogl[ąa]danie)/i,
    /(zapraszam do |nie zapomnij )?(zasubskrybowa[ćc]|subskrybuj|subskrypcj[ię])/i, /do zobaczenia w (nast[ęe]pnym|kolejnym) (odcinku|filmie)/i,
    /thank(s| you) for watching/i, /please subscribe/i, /subtitles? (by|made by)[^.!?]*/i, /all rights reserved/i, /copyright/i,
    /\A[♪♫\s.…-]*\z/
  )
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

  # Owner fix ("rozpoznawanie mowy jest znowu średnie"): Whisper gets a hint with the words of this conversation —
  # Agentaro's own terms and the names of the user's team — so it writes them right. It is only a hint; a recording
  # that comes back as nothing but the hint (Whisper repeats it on silence) counts as silence.
  HINT = {
    "pl" => "Rozmowa z dyrektorem w Agentaro o epikach, specach, krokach, przestrzeniach i agentach; weryfikator.",
    "en" => "A conversation with the director in Agentaro about epics, specs, steps, spaces and agents; the verifier."
  }.freeze
  MAX_HINT = 400 # characters; Whisper takes at most about 220 tokens

  def self.names_for(user)
    user.team_roles.includes(:agent).filter_map { |role| role.agent&.name }.uniq
  end

  def self.hint(language, names = [])
    base = HINT[language] || HINT["pl"]
    names = names.map { |n| n.to_s.gsub(/[[:cntrl:]]+/, " ").squish.truncate(40, omission: "") }.compact_blank.uniq
    names.empty? ? base : "#{base} #{names.join(", ")}.".truncate(MAX_HINT, omission: "")
  end

  def self.only_hint?(text, hint)
    plain = ->(s) { s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip }
    plain.(text).present? && plain.(hint).include?(plain.(text)) && plain.(text).length > 20
  end

  # G3: WAV bytes in, text out ("" for silence or noise). language: "auto", "pl" or "en" (passed to whisper).
  def self.transcribe(audio, language: "auto", names: [])
    raise Error, "Speech recognition is not installed on this computer." unless listening?
    raise Error, "The recording is too long." if audio.bytesize > MAX_AUDIO
    raise Error, "The recording is not a WAV file." unless audio.byteslice(0, 4) == "RIFF" && audio.byteslice(8, 4) == "WAVE"

    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      File.binwrite(path, audio)
      hint = hint(language, names)
      result = HostProcess.run(config[:whisper_bin], [ "-m", config[:whisper_model], "-f", path, "-l", (%w[pl en].include?(language) ? language : "auto"), "-nt", "-np", "-sns",
                                                      "--prompt", hint ],
                               chdir: dir, timeout: 60, max_output: 64 * 1024)
      raise Error, "Speech recognition did not finish in time." if result.timed_out
      raise Error, "Speech recognition failed." unless result.success?

      text = result.stdout.to_s.force_encoding(Encoding::UTF_8).scrub("").lines.map(&:strip).reject { |l| l.empty? || l.match?(NOISE) }.join(" ")
      only_hint?(text, hint) ? "" : without_phantoms(text)
    end
  end

  # What Piper may read: no control characters, emoji, smileys or Markdown marks.
  def self.readable(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
    text = text.gsub(MARKDOWN, "").gsub(EMOJI, "").gsub(SMILEYS, "")
    text.gsub(/[[:cntrl:]]+/, " ").gsub(/\s+([.,!?;:])/, "\\1").squeeze(" ").strip
  end

  # Drops whole sentences that are only a phantom phrase; real sentences that merely mention one stay.
  WHOLE_PHANTOMS = /\A(koniec|the end|dzi[ęe]kuj[ęe]( bardzo)?|thank you)[.!…]*\z/i # phantoms when they are all that was "heard"

  def self.without_phantoms(text)
    return "" if text.strip.match?(WHOLE_PHANTOMS)

    text.split(/(?<=[.!?…])\s+/).reject { |sentence| sentence.strip.match?(PHANTOMS) && sentence.gsub(PHANTOMS, "").gsub(/[\p{P}\s]/, "").length < 12 }
        .join(" ").strip
  end

  # G5: text in, WAV bytes out, in the voice of the chosen language ("auto": guessed from the text).
  # speed: 1.0 is Piper's natural pace; 1.5 speaks 1.5 times faster (owner fix), without changing the pitch.
  # Spec 046, G3: Naturalna — more varied intonation and a short pause between sentences (Piper's general defaults;
  # the Polish voices ship with flatter values, 0.5 and 0.333).
  NATURAL_ARGS = [ "--noise-scale", "0.667", "--noise-w-scale", "0.8", "--sentence-silence", "0.25" ].freeze

  def self.speak(text, language: "auto", speaker: "director", speed: 1.5, natural: false)
    raise Error, "The voice is not installed on this computer." unless speaking?

    text = readable(text)
    raise Error, "At most #{MAX_TEXT} characters at a time." if text.length > MAX_TEXT

    language = %w[pl en].include?(language) ? language : guess_language(text)
    text = SpeechText.prepare(text, language) if natural # spec 046, G3
    raise Error, "Nothing to say." if text.empty?

    voice = voice_for(language, speaker.to_s == "verifier" ? "verifier" : "director")
    # Pauses shrink less than sounds, so the scale goes a bit further than 1/speed: measured on the host, 1.5 gives
    # about 1.5x and 2.0 about 2x the natural duration.
    length = format("%.2f", speed.to_f.clamp(1.0, 2.0)**-1.35)
    args = [ "-m", voice, nil, "--length-scale", length, *(NATURAL_ARGS if natural) ] # nil: where the output file goes
    return cached(text, args) if ConversationMode.acknowledgement?(text) # spec 046, G4: made once and kept

    synthesize(text, args)
  end

  def self.synthesize(text, args)
    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      result = HostProcess.run(config[:piper_bin], args.flat_map { |a| a.nil? ? [ "-f", path ] : [ a ] }, stdin: text, chdir: dir, timeout: 30, max_output: 64 * 1024)
      raise Error, "The voice did not finish in time." if result.timed_out
      raise Error, "The voice failed." unless result.success? && File.file?(path)

      File.binread(path)
    end
  end

  # Spec 046, G4: an acknowledgement's sound, kept per phrase, voice and speed in tmp/voice (not tracked).
  def self.cached(text, args)
    file = Rails.root.join("tmp", "voice", "#{Digest::SHA256.hexdigest([ text, *args.compact ].join("\0"))}.wav")
    return File.binread(file) if File.file?(file)

    wav = synthesize(text, args)
    FileUtils.mkdir_p(file.dirname)
    File.binwrite("#{file}.tmp", wav)
    File.rename("#{file}.tmp", file)
    wav
  end
end
