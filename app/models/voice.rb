# Spec 017: speech on the host — whisper.cpp turns the user's voice into text, Piper reads the director's answer.
# Both run as separate programs: no shell, fixed arguments, a timeout, the minimal environment (HostProcess);
# audio lives only in a private temporary folder that is deleted at once (R3). Nothing leaves the host.
class Voice
  Error = Class.new(StandardError)
  MAX_AUDIO = 2 * 1024 * 1024 # bytes (R1): about 60 s of 16 kHz mono WAV
  MAX_TEXT = 600              # characters per speech request (R2)
  NOISE = /\A[\[(][^\])]*[\])]\z/ # whisper's notes for silence or noise, e.g. [BLANK_AUDIO], (muzyka)

  def self.config = Rails.application.config.x.voice

  def self.listening? = File.executable?(config[:whisper_bin]) && File.file?(config[:whisper_model])
  def self.speaking? = File.executable?(config[:piper_bin]) && File.file?(config[:piper_voice])

  # G3: WAV bytes in, text out ("" for silence or noise).
  def self.transcribe(audio)
    raise Error, "Speech recognition is not installed on this computer." unless listening?
    raise Error, "The recording is too long." if audio.bytesize > MAX_AUDIO
    raise Error, "The recording is not a WAV file." unless audio.byteslice(0, 4) == "RIFF" && audio.byteslice(8, 4) == "WAVE"

    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      File.binwrite(path, audio)
      result = HostProcess.run(config[:whisper_bin], [ "-m", config[:whisper_model], "-f", path, "-l", "auto", "-nt", "-np" ],
                               chdir: dir, timeout: 60, max_output: 64 * 1024)
      raise Error, "Speech recognition did not finish in time." if result.timed_out
      raise Error, "Speech recognition failed." unless result.success?

      result.stdout.to_s.force_encoding(Encoding::UTF_8).scrub("").lines.map(&:strip).reject { |l| l.empty? || l.match?(NOISE) }.join(" ").strip
    end
  end

  # G5: text in, WAV bytes out.
  def self.speak(text)
    raise Error, "The voice is not installed on this computer." unless speaking?

    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").gsub(/[[:cntrl:]]+/, " ").squeeze(" ").strip
    raise Error, "Nothing to say." if text.empty?
    raise Error, "At most #{MAX_TEXT} characters at a time." if text.length > MAX_TEXT

    Dir.mktmpdir("agentaro-voice") do |dir|
      path = File.join(dir, "speech.wav")
      result = HostProcess.run(config[:piper_bin], [ "-m", config[:piper_voice], "-f", path ], stdin: text, chdir: dir, timeout: 30, max_output: 64 * 1024)
      raise Error, "The voice did not finish in time." if result.timed_out
      raise Error, "The voice failed." unless result.success? && File.file?(path)

      File.binread(path)
    end
  end
end
