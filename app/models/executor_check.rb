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
  ENV_KEPT = %w[PATH HOME USER LANG TMPDIR].freeze
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

    env = ENV.to_h.slice(*ENV_KEPT)
    reader, writer = IO.pipe
    pid = Process.spawn(env, program, *preset.version_args, unsetenv_others: true, chdir: Dir.tmpdir, pgroup: true,
                        in: File::NULL, out: writer, err: writer, close_others: true)
    writer.close
    output = +""
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0
      next unless reader.wait_readable(remaining)

      chunk = reader.read_nonblock(4096, exception: false)
      break if chunk.nil? # EOF: the program closed its output
      output << chunk if chunk.is_a?(String) && output.bytesize < MAX_OUTPUT * 4
    end

    status = wait_or_kill(pid, deadline)
    return Result.new(false, "No answer within #{@timeout} seconds; stopped.") unless status

    text = self.class.clean(output)
    status.success? ? Result.new(true, text.presence || "OK") : Result.new(false, "Exited with status #{status.exitstatus}. #{text}".strip)
  rescue SystemCallError => e
    Result.new(false, "Could not start #{preset.program}: #{e.message}")
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end

  def wait_or_kill(pid, deadline)
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
    Process.kill("KILL", -pid) rescue Errno::ESRCH
    Process.wait(pid) rescue Errno::ECHILD
    nil
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
