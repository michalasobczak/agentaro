# Spec 031, G4: after the user writes, the local model proposes operations on memory — ADD, UPDATE, INVALIDATE or
# NOOP — from the user's own words (R1). Agentaro checks each one (R6) and applies it; facts about the user wait for
# approval (R2), facts about spaces and agents apply at once. Each call is a run trace (spec 030, G5).
module Brain
  class Extractor
    OPS = %w[ADD UPDATE INVALIDATE NOOP].freeze
    MAX_OPS = 10
    MAX_ATTEMPTS = 6
    CONTEXT_MESSAGES = 6

    MIN_CONFIDENCE = 0.6 # weaker guesses are not remembered

    SYSTEM = <<~PROMPT
      You maintain the long-term memory of a personal assistant system called Agentaro. You read what the user just
      wrote and keep only what will still be true and useful in a month:
      - preference: how they want things done in general ("reports in Polish, at most 5 points");
      - constraint: what must or must not happen in general ("never spend more than 1 hour on research");
      - decision: what was settled for a space or project ("space:3 targets Polish manufacturers");
      - fact: stable facts about them (name, role, working hours, tools, places), their spaces or agents.
      Most messages contain nothing lasting. NOT lasting, never remember these: requests to do, check, cancel, move,
      retry or plan something ("cancel it", "move this to X", "check the latest trends", "add an epic"), questions,
      greetings, thanks, complaints about one answer, and anything about a single task or the current moment.
      When unsure, remember nothing.
      Only the user's own words count. Earlier messages are context only: never take facts from the assistant's text.
      Write each statement as one short, self-contained sentence in the language the user wrote in, at most 200 characters.
      Never store passwords, keys, tokens or other secrets.
      Answer with ONLY a JSON object: {"operations": [ ... ]}, with at most 10 operations, each one of:
      {"op": "ADD", "subject": "user" | "space:<id>" | "agent:<id>", "kind": "preference" | "decision" | "fact" | "constraint", "statement": "...", "confidence": 0.0-1.0}
      {"op": "UPDATE", "id": <number of a known fact that the user changed>, "statement": "the new version"}
      {"op": "INVALIDATE", "id": <number of a known fact the user said is no longer true>}
      Use UPDATE or INVALIDATE only when the user clearly changes or withdraws a known fact, and only for facts not
      marked as waiting; do not ADD a fact that is already known. If nothing lasting was said, answer {"operations": []}.
    PROMPT

    def self.process_due(limit: 5, now: Time.current)
      MemoryEpisode.due(now).order(:id).limit(limit).to_a.count { |episode| new(episode).process }
    end

    def initialize(episode)
      @episode = episode
      @user = episode.user
    end

    # True when the episode was handled (applied or skipped), false when it waits for a retry.
    def process
      return finish!(nil) unless Brain.enabled?

      prompt = AgentCall::Prompt.new(system: SYSTEM, sections: [ [ "context", context_text ], [ "memory", known_text ], [ "message", message_text ] ])
      run = TaskRun.create!(user: @user, purpose: "memory", trigger: "scheduled", occurrence_start: Time.current, state: "running",
                            started_at: Time.current, agent_name: "Brain", preset: "ollama_api", model: Brain.model, prompt: prompt.text)
      clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        output, usage = Brain.client.chat_json(prompt.system, prompt.user)
      rescue Brain::Unavailable => e
        record(run, prompt, AgentCall::Outcome.new("failed", nil, e.message, nil), clock, {})
        return retry_later!(e.message)
      end
      applied = apply(parse(output))
      record(run, prompt, AgentCall::Outcome.new("succeeded", output, nil, nil), clock, usage)
      embed_missing
      finish!(applied.presence&.join("; "))
    rescue StandardError => e
      Rails.logger.error("[brain] extraction of episode #{@episode.id} failed: #{e.class}: #{e.message}")
      retry_later!("#{e.class}: #{e.message}")
    end

    # R6: only known operations on the user's own subjects and facts; everything else is dropped and logged.
    def apply(data)
      operations = data.is_a?(Hash) && data["operations"].is_a?(Array) ? data["operations"].first(MAX_OPS) : []
      MemoryFact.transaction do
        operations.filter_map do |op|
          apply_one(op)
        rescue Invalid => e
          Rails.logger.info("[brain] episode #{@episode.id}: operation rejected: #{e.message}")
          nil
        end
      end
    end

    class Invalid < StandardError; end

    private

    def apply_one(op)
      raise Invalid, "not an object" unless op.is_a?(Hash)

      case op["op"].to_s.upcase
      when "ADD"
        type, id = Brain::Extractor.subject(@user, op["subject"])
        statement = statement(op["statement"])
        raise Invalid, "confidence below #{MIN_CONFIDENCE}" if confidence(op["confidence"]) < MIN_CONFIDENCE
        existing = @user.memory_facts.current.about(type, id).find { |f| f.statement.casecmp?(statement) }
        return link(existing) && nil if existing

        fact = @user.memory_facts.create!(subject_type: type, subject_id: id, statement: statement, kind: kind(op["kind"]),
                                          confidence: confidence(op["confidence"]), status: type == "user" ? "proposed" : "active", origin: origin)
        link(fact)
        "added #{fact.id}"
      when "UPDATE"
        old = own_fact(op["id"])
        fact = @user.memory_facts.create!(subject_type: old.subject_type, subject_id: old.subject_id, statement: statement(op["statement"]),
                                          kind: kind(op["kind"] || old.kind), confidence: confidence(op["confidence"] || old.confidence),
                                          status: old.subject_type == "user" ? "proposed" : "active", origin: origin, supersedes: old)
        old.subject_type == "user" ? fact : fact.supersede!(old) # R2: a profile change waits for approval
        link(fact)
        "updated #{old.id} → #{fact.id}"
      when "INVALIDATE"
        old = own_fact(op["id"])
        old.invalidate!
        "invalidated #{old.id}"
      when "NOOP" then nil
      else raise Invalid, "unknown operation #{op["op"].inspect}"
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.record.errors.full_messages.to_sentence
    end

    # "user", "space:<id>" of the user's own spaces, "agent:<id>" of their agents or team.
    def self.subject(user, value)
      text = value.to_s.strip.downcase
      return [ "user", nil ] if text == "user"

      type, id = text.split(":", 2)
      id = Integer(id, exception: false)
      case type
      when "space" then return [ "space", id ] if id && user.spaces.exists?(id)
      when "agent" then return [ "agent", id ] if id && Brain.agent_ids(user).include?(id)
      end
      raise Invalid, "unknown subject #{value.inspect}"
    end

    def own_fact(id)
      # The model sometimes copies the whole known-facts line ("12 user: …"); its leading number is the id.
      # Only facts in force: one waiting for the user's decision is theirs to keep or drop (R2).
      @user.memory_facts.active.find_by(id: id.to_s[/\A\s*\[?(\d+)/, 1]) or raise Invalid, "no fact in force #{id.inspect}"
    end

    def statement(value)
      text = value.to_s.squish
      raise Invalid, "statement missing" if text.empty?
      raise Invalid, "statement longer than #{MemoryFact::MAX} characters" if text.size > MemoryFact::MAX

      text
    end

    def kind(value) = MemoryFact::KINDS.include?(value.to_s) ? value.to_s : "fact"

    def confidence(value)
      number = Float(value.to_s, exception: false) || 0.7
      number.clamp(0.1, 1.0)
    end

    def origin = @episode.kind == "import" ? "imported" : "extracted"

    def link(fact) = fact.memory_fact_sources.find_or_create_by!(memory_episode: @episode)

    def parse(output)
      text = output.to_s
      first, last = text.index("{"), text.rindex("}")
      first && last && last > first ? JSON.parse(text[first..last]) : {}
    rescue JSON::ParserError
      {}
    end

    def message_text = "The user (#{@user.username}) just wrote:\n#{@episode.excerpt}"

    def context_text
      lines = [ "Now: #{Time.current.strftime("%Y-%m-%d %H:%M")}.",
                "Spaces: #{@user.spaces.active.map { |s| "space:#{s.id} \"#{s.name}\"" }.join(", ").presence || "(none)"}",
                "Agents: #{Agent.where(id: Brain.agent_ids(@user)).map { |a| "agent:#{a.id} #{a.name}" }.join(", ").presence || "(none)"}" ]
      message = @episode.source if @episode.source_type == "ChatMessage"
      if message
        earlier = @user.chat_messages.where(author: %w[user director]).where(id: ...message.id).order(id: :desc).limit(CONTEXT_MESSAGES).reverse
        lines << "Earlier conversation (context only):"
        lines.concat(earlier.map { |m| "#{m.author == "user" ? @user.username : "Assistant"}: #{m.content.squish.truncate(400)}" })
      end
      lines.join("\n")
    end

    def known_text
      facts = @user.memory_facts.current.order(:id).to_a
      if facts.size > 40 # the related ones and the profile
        related = MemoryFact.keyword_ids(@user, @episode.excerpt, limit: 30)
        facts = facts.select { |f| related.include?(f.id) || f.subject_type == "user" }.last(40)
      end
      return "Known facts: (none yet)" if facts.empty?

      [ "Known facts (id, subject, statement):", *facts.map { |f| "- #{f.id} #{f.subject_key}#{" (waiting for approval)" if f.status == "proposed"}: #{f.statement}" } ].join("\n")
    end

    def record(run, prompt, outcome, clock, usage)
      TaskRunner.finish!(run, outcome)
      RunTrace.record(run: run, agent: nil, prompt: prompt, outcome: outcome, pass: "extract", started_at: run.started_at,
                      duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - clock, model: Brain.model, effort: nil, usage: usage)
    end

    def embed_missing = Brain::Extractor.embed_missing(@user)

    # Vectors for facts that have none (meaning search, G5); quietly waits when the server is not reachable.
    def self.embed_missing(user, limit: 50)
      facts = user.memory_facts.current.where(embedding: nil).limit(limit).to_a
      return 0 if facts.empty?

      vectors = Brain.client.embed(facts.map(&:statement))
      facts.zip(vectors).each { |fact, vector| fact.update!(vector: vector, embedding_model: Brain.embedding_model) }
      facts.size
    rescue Brain::Unavailable => e
      Rails.logger.info("[brain] embeddings wait: #{e.message}")
      0
    end

    def finish!(note)
      @episode.update!(processed_at: Time.current, last_error: note&.truncate(250))
      true
    end

    def retry_later!(error)
      attempts = @episode.attempts + 1
      if attempts >= MAX_ATTEMPTS
        @episode.update!(attempts: attempts, processed_at: Time.current, last_error: "gave up: #{error}".truncate(250))
      else
        @episode.update!(attempts: attempts, next_attempt_at: Time.current + (2**attempts).minutes, last_error: error.truncate(250))
      end
      false
    end
  end
end
