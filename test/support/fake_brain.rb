# Spec 031: a stand-in for the local model server — answers chat requests from a queue and gives deterministic
# word-hash vectors, so meaning search can be tested without Ollama.
class FakeBrain
  attr_accessor :answers, :requests, :down

  def initialize(answers = [])
    @answers, @requests, @down = answers, [], false
  end

  def chat_json(system, user, timeout: 180)
    raise Brain::Unavailable, "the model server is not reachable (test)" if down

    @requests << user
    answer = @answers.shift || { operations: [] }
    [ answer.is_a?(String) ? answer : answer.to_json, { input_tokens: 12, output_tokens: 6 } ]
  end

  def embed(texts, timeout: 20)
    raise Brain::Unavailable, "the model server is not reachable (test)" if down

    Array(texts).map { |text| self.class.vector(text) }
  end

  def status = down ? { reachable: false, error: "down" } : { reachable: true, models: { Brain.model => true, Brain.embedding_model => true } }

  def self.vector(text)
    v = Array.new(32, 0.0)
    text.to_s.downcase.scan(/[\p{L}\p{N}]{3,}/).each { |w| v[Zlib.crc32(w[0, 5]) % 32] += 1.0 }
    v
  end
end
