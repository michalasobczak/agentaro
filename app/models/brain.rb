require "net/http"

# Spec 031: the brain — long-term memory per user. Settings, the local model client and the hooks that record
# episodes. The parts: Brain::Extractor (facts from the user's messages), Brain::Retriever (what goes into prompts),
# Brain::Consolidator (nightly) and Brain::Worker (background jobs).
module Brain
  # R7: the local model is called on this computer only.
  LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

  class Unavailable < StandardError; end

  class << self
    def url = ENV.fetch("AGENTARO_BRAIN_URL", "http://127.0.0.1:11434")
    def model = ENV.fetch("AGENTARO_BRAIN_MODEL", "qwen3:8b")
    def embedding_model = ENV.fetch("AGENTARO_BRAIN_EMBEDDING_MODEL", "bge-m3")

    # Tests set a stand-in; otherwise the Ollama client.
    attr_writer :client

    def client = @client ||= Client.new(url)

    def enabled? = Rails.application.config.x.brain_enabled != false

    # Agents the user's memory may be about: their own agents and the agents on their team.
    def agent_ids(user)
      return [] unless user

      (user.agents.pluck(:id) + user.team_roles.pluck(:agent_id)).uniq
    end

    # G3: a chat message becomes an episode; the user's messages wait for extraction (G4).
    def record_message(message)
      return unless enabled?

      kind = { "user" => "user_message", "director" => "director_answer" }[message.author] or return
      MemoryEpisode.record!(message.user, kind, message.content, source: message, at: message.created_at)
    rescue StandardError => e
      Rails.logger.error("[brain] could not record message #{message.id}: #{e.class}: #{e.message}")
    end

    # G3: an epic's outcome is evidence for later lessons (spec 101); it is not extracted on its own (R1).
    def record_epic(item, kind)
      return unless enabled?

      text = kind == "epic_done" ? "Epic \"#{item.title}\" in space \"#{item.space&.name}\" finished." : "Epic \"#{item.title}\" was blocked: #{item.blocked_reason}"
      MemoryEpisode.record!(item.user, kind, text, source: item)
    rescue StandardError => e
      Rails.logger.error("[brain] could not record epic #{item.id}: #{e.class}: #{e.message}")
    end

    def cosine(a, b)
      return 0.0 unless a && b && a.size == b.size

      dot = na = nb = 0.0
      a.each_index do |i|
        x, y = a[i], b[i]
        dot += x * y
        na += x * x
        nb += y * y
      end
      na.zero? || nb.zero? ? 0.0 : dot / Math.sqrt(na * nb)
    end

    # R2: a profile fact the user keeps; one it replaces becomes history.
    def approve!(fact)
      fact.transaction do
        fact.update!(status: "active", valid_from: Time.current)
        fact.supersede!(fact.supersedes) if fact.supersedes&.status == "active"
      end
    end

    # Data of a deleted space or agent goes with it.
    def forget_scope(user_ids, type, id)
      MemoryFact.where(user_id: user_ids, subject_type: type, subject_id: id).find_each(&:destroy!)
      MemoryBlock.where(user_id: user_ids, scope_type: type, scope_id: id).find_each(&:destroy!)
    end
  end

  # The local Ollama server: JSON chat for extraction, embeddings for meaning search.
  class Client
    def initialize(url)
      @uri = URI.parse(url)
      raise ArgumentError, "the brain's model server must be on this computer" unless LOCAL_HOSTS.include?(@uri.host)
    end

    # [answer text, usage]; raises Unavailable when the server cannot be reached or answers with an error.
    def chat_json(system, user, timeout: 180)
      body = { model: Brain.model, stream: false, format: "json", think: false, options: { temperature: 0 },
               messages: [ { role: "system", content: system }, { role: "user", content: user } ] }
      data = post("/api/chat", body, timeout)
      [ data.dig("message", "content").to_s, { input_tokens: data["prompt_eval_count"], output_tokens: data["eval_count"] }.compact ]
    end

    def embed(texts, timeout: 20)
      data = post("/api/embed", { model: Brain.embedding_model, input: Array(texts) }, timeout)
      vectors = data["embeddings"]
      raise Unavailable, "no embeddings in the answer" unless vectors.is_a?(Array) && vectors.size == Array(texts).size

      vectors
    end

    # Which of the two models are present (for the Brain page).
    def status
      data = get("/api/tags", 3)
      names = Array(data["models"]).map { |m| m["name"].to_s }
      { reachable: true, models: [ Brain.model, Brain.embedding_model ].index_with { |m| names.any? { |n| n == m || n == "#{m}:latest" } } }
    rescue Unavailable => e
      { reachable: false, error: e.message }
    end

    private

    def post(path, body, timeout)
      request(Net::HTTP::Post.new(path, "Content-Type" => "application/json").tap { |r| r.body = body.to_json }, timeout)
    end

    def get(path, timeout) = request(Net::HTTP::Get.new(path), timeout)

    def request(req, timeout)
      response = Net::HTTP.start(@uri.host, @uri.port, open_timeout: 3, read_timeout: timeout, write_timeout: 30) { |http| http.request(req) }
      raise Unavailable, "the model server answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Unavailable, "the model server's answer was not JSON"
    rescue SystemCallError, SocketError, IOError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
      raise Unavailable, "the model server is not reachable (#{e.class.name.demodulize})"
    end
  end
end
