# Spec 022, G1/R5: the models an executor's tool reports — never raises.
#
# Each source is the tool's own: Ollama and LM Studio list what is installed (CLI or API), OpenAI-compatible servers
# answer /models, Codex keeps a cache of the models its account can use (an unofficial file: a missing or changed
# file gives an empty list), Claude Code lists nothing (its aliases are added by Executor#model_choices, Q3).
# Programs run only with fixed arguments, no shell, a minimal environment and a 10-second timeout (spec 008).
class ModelList
  Result = Data.define(:ok, :models, :note)
  TIMEOUT = 10
  MAX_MODELS = 200
  MAX_FILE = 5.megabytes
  MAX_OUTPUT = 512.kilobytes

  def initialize(executor, codex_home: ENV["CODEX_HOME"].presence || File.expand_path("~/.codex"), timeout: TIMEOUT)
    @executor, @codex_home, @timeout = executor, codex_home, timeout
  end

  def run
    preset = @executor.preset_definition
    return Result.new(false, [], "Unknown preset.") unless preset

    case preset.key
    when "claude_code" then Result.new(true, [], "Claude Code lists no models; its aliases are always offered. Add full names below.")
    when "codex" then codex
    when "ollama_cli" then cli("ollama", [ "list" ]) { |out| out.lines.drop(1).filter_map { |line| line.split.first } }
    when "lm_studio_cli" then cli("lms", [ "ls", "--llm", "--json" ]) { |out| Array(JSON.parse(out)).filter_map { |m| m["modelKey"] if m.is_a?(Hash) } }
    else
      preset.api? ? named(ExecutorCheck.new(@executor, timeout: @timeout).api_models(preset)) : Result.new(false, [], "#{preset.label} gives no model list; add names below.")
    end
  rescue ExecutorCheck::Failure => e
    Result.new(false, [], e.message)
  rescue StandardError => e
    Rails.logger.warn("[models] #{@executor.name}: #{e.class}: #{e.message}")
    Result.new(false, [], "Could not read the list (#{e.class}).")
  end

  private

  def codex
    file = File.join(@codex_home, "models_cache.json")
    return Result.new(false, [], "Codex has not saved its model list yet; run codex once on this computer.") unless File.file?(file)
    return Result.new(false, [], "Codex's model list file is too large; not read.") if File.size(file) > MAX_FILE

    data = JSON.parse(File.read(file))
    allowed = Executor::EFFORTS.fetch("codex")
    models = Array(data.is_a?(Hash) ? data["models"] : nil).filter_map do |m|
      next unless m.is_a?(Hash) && m["visibility"] != "hide"

      efforts = Array(m["supported_reasoning_levels"]).filter_map { |level| level["effort"] if level.is_a?(Hash) } & allowed
      { "name" => m["slug"].to_s, "efforts" => efforts }
    end
    finish(models)
  rescue JSON::ParserError
    Result.new(false, [], "Codex's model list file has a format Agentaro does not know.")
  end

  def cli(program, args)
    path = ExecutorCheck.locate(program)
    return Result.new(false, [], "#{program} was not found on this computer.") unless path

    result = HostProcess.run(path, args, timeout: @timeout, max_output: MAX_OUTPUT)
    return Result.new(false, [], "No answer within #{@timeout} seconds; stopped.") if result.timed_out
    return Result.new(false, [], "#{program} ended: #{result.ending}. #{ExecutorCheck.clean(result.stderr)}".strip) unless result.success?

    named(yield(result.stdout))
  rescue JSON::ParserError
    Result.new(false, [], "#{program} did not answer with a list.")
  end

  def named(names) = finish(names.map { |name| { "name" => name.to_s, "efforts" => [] } })

  # R1: names that could be read as options, or that are odd in any other way, are left out.
  def finish(models)
    models = models.select { |m| m["name"].match?(Executor::MODEL_NAME) }.uniq { |m| m["name"] }.first(MAX_MODELS)
    Result.new(true, models, models.empty? ? "The tool lists no models yet." : nil)
  end
end
