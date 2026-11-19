# Spec 008, G4: checks that an executor answers.
#
# CLI (R2, R4): the preset's program with its fixed version argument, no shell, a minimal environment
# without Agentaro's secrets, the system temporary folder as working folder and a 10-second timeout (the process group is
# killed). API (R5): GET of the models endpoint, 10-second timeout, no redirects.
require "net/http"

class ExecutorCheck
  TIMEOUT = 10 # seconds
  MAX_OUTPUT = 2048 # bytes kept
  MAX_BODY = 1.megabyte # largest models list read from an API
  SEARCH_DIRS = [ "~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "~/.lmstudio/bin" ].freeze
  MODELS_PATH = { "ollama" => "/api/tags", "openai" => "/models" }.freeze

  Result = Data.define(:ok, :output)

  attr_reader :executor

  def initialize(executor, timeout: TIMEOUT)
    @executor = executor
    @timeout = timeout
  end

  def run
    preset = executor.preset_definition
    return Result.new(false, "Unknown preset.") unless preset

    preset.cli? ? run_cli(preset) : run_api(preset)
  end

  # Finds a preset's program on PATH or in the usual install folders. Only plain names from PRESETS.
  def self.locate(program, path: ENV["PATH"])
    dirs = path.to_s.split(File::PATH_SEPARATOR) + SEARCH_DIRS.map { |dir| File.expand_path(dir) }
    dirs.uniq.lazy.map { |dir| File.join(dir, program) }.find { |file| File.file?(file) && File.executable?(file) }
  end

  # Removes escape codes and control characters (keeps line breaks and tabs); no length limit.
  def self.clean_text(text)
    text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
        .gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "")
        .gsub(/[^\P{Cc}\n\t]/, "")
        .strip
  end

  def self.clean(text)
    text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
        .gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "") # ANSI escape sequences
        .gsub(/[^\P{Cc}\n\t]/, "")            # other control characters
        .strip.byteslice(0, MAX_OUTPUT).to_s.scrub("")
  end

  private

  def run_cli(preset)
    program = self.class.locate(preset.program)
    return Result.new(false, "#{preset.program} was not found on this computer.") unless program

    result = HostProcess.run(program, preset.version_args, timeout: @timeout, max_output: MAX_OUTPUT * 4)
    return Result.new(false, "No answer within #{@timeout} seconds; stopped.") if result.timed_out

    text = self.class.clean([ result.stdout, result.stderr ].reject(&:empty?).join("\n"))
    result.success? ? Result.new(true, text.presence || "OK") : Result.new(false, "Exited with status #{result.exit_status}. #{text}".strip)
  rescue SystemCallError => e
    Result.new(false, "Could not start #{preset.program}: #{e.message}")
  end

  def run_api(preset)
    uri = URI.parse((executor.base_url.presence || preset.default_url) + MODELS_PATH.fetch(preset.protocol))
    body = +""
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout) do |http|
      http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json")) do |res|
        next unless res.is_a?(Net::HTTPSuccess)

        res.read_body do |chunk|
          body << chunk
          return Result.new(false, "Answered with more than #{MAX_BODY / 1.megabyte} MB; not read.") if body.bytesize > MAX_BODY
        end
      end
    end
    return Result.new(false, "Answered #{response.code} #{response.message}.") unless response.is_a?(Net::HTTPSuccess)

    models = model_names(preset.protocol, JSON.parse(body))
    Result.new(true, self.class.clean(models.any? ? "Models: #{models.first(50).join(", ")}" : "Answered; no models listed."))
  rescue JSON::ParserError
    Result.new(false, "Answered, but not with a list of models.")
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    Result.new(false, "No answer within #{@timeout} seconds.")
  rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
    Result.new(false, "Could not connect: #{e.message}")
  end

  def model_names(protocol, body)
    list = protocol == "ollama" ? body["models"] : body["data"]
    Array(list).filter_map { |model| model.is_a?(Hash) ? (model["name"] || model["id"]).to_s.presence : nil }
  end
end
