require "net/http"

# Spec 049: the models of the local Ollama, for the "Codex (local model)" preset — its model list (G1), and a check
# before a step that the model is there, so Codex never starts pulling gigabytes by itself (S3). Never raises.
module LocalModels
  TIMEOUT = 5

  def self.url = ENV["AGENTARO_OLLAMA_URL"].presence || "http://127.0.0.1:11434"

  # Model names, or [] when Ollama cannot be reached.
  def self.names
    uri = URI.join(url, "/api/tags")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri) }
    return [] unless response.is_a?(Net::HTTPSuccess)

    Array(JSON.parse(response.body)["models"]).filter_map { |m| m["name"].to_s.presence if m.is_a?(Hash) }
  rescue StandardError
    []
  end

  # nil when the model is there; else the reason, for the step's error.
  def self.missing(model)
    available = names
    return "The local Ollama (#{url}) does not answer; start Ollama and try again." if available.empty?

    wanted = model.include?(":") ? model : "#{model}:latest"
    return if available.include?(model) || available.include?(wanted)

    "The model #{model} is not in the local Ollama (it has #{available.first(5).join(", ")}). Pull it with `ollama pull #{model}` or choose another."
  end
end
