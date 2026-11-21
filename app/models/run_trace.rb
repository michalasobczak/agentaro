# Spec 030: records each model call as a structured trace, keeps traces small (shared parts, compressed old events)
# and rebuilds what was sent. Recording never breaks a run (R7).
module RunTrace
  CHUNK = "\n\n" # sections are stored in blank-line chunks, so repeated blocks (instructions, team, spaces) are kept once
  COMPRESS_AFTER = 90.days # G6, Q2
  INTERVAL = 1.day
  REDACTED = "[secret removed]"

  # R2: things that look like keys, tokens, passwords or private keys. High precision: a marker replaces the value.
  SECRET_PATTERNS = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m,
    /\bsk-ant-[A-Za-z0-9_-]{20,}/,
    /\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}/,
    /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}/,
    /\bgithub_pat_[A-Za-z0-9_]{30,}/,
    /\bglpat-[A-Za-z0-9_-]{20,}/,
    /\bxox[abprs]-[A-Za-z0-9-]{10,}/,
    /\bAKIA[0-9A-Z]{16}\b/,
    /\bAIza[0-9A-Za-z_-]{35}\b/,
    /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+\/=-]{20,}/,
    /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/
  ].freeze
  # "password: …", "api_key=…" and the like: only the value goes.
  SECRET_ASSIGNMENT = /\b((?:api[_-]?key|secret(?:[_-]?key)?|access[_-]?token|auth[_-]?token|token|password|passwd|pwd)\b["']?\s*[:=]\s*["']?)([^\s"',;]{8,})/i

  class << self
    # The text with secrets replaced, and whether anything was replaced.
    def redact(text)
      text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?").delete("\0")
      changed = false
      SECRET_PATTERNS.each { |pattern| text = text.gsub(pattern) { changed = true; REDACTED } }
      text = text.gsub(SECRET_ASSIGNMENT) { changed = true; "#{$1}#{REDACTED}" }
      [ text, changed ]
    end

    def record(run:, agent:, prompt:, outcome:, pass:, started_at:, duration:, model:, effort:, usage: {}, events: nil, events_cut: false)
      return unless run.is_a?(TaskRun) && run.persisted? # a model check (spec 022) is not a run

      redacted = false
      clean = ->(text) { value, changed = redact(text); redacted ||= changed; value }
      ModelCall.transaction do
        call = ModelCall.create!(
          task_run: run, user_id: run.user_id || run.task&.user_id, position: (run.model_calls.maximum(:position) || 0) + 1,
          pass: pass || run.purpose, agent_id: agent&.id, agent_name: agent&.name || run.agent_name, preset: agent&.executor&.preset || run.preset,
          model: model, effort: effort,
          state: outcome.state, started_at: started_at, duration_ms: (duration * 1000).round, joiner: prompt.joiner,
          error: (TaskRun.limit_tail(clean.(outcome.error), TaskRun::MAX_ERROR) if outcome.error.present?),
          output_part: (TracePart.for(TaskRun.limit_text(clean.(outcome.output), TaskRun::MAX_OUTPUT)) if outcome.output.present?),
          **usage.slice(:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :cost_usd, :turns)
        )
        position = 0
        [ [ "master_prompt", prompt.system ], *prompt.sections ].each_with_index do |(kind, text), section|
          chunks(clean.(text)).each do |chunk|
            call.parts.create!(trace_part: TracePart.for(chunk), position: position += 1, section: section, kind: kind)
          end
        end
        if events.present?
          list = events.map { |event| event.transform_values { |v| v.is_a?(String) ? clean.(v) : v } }
          call.update!(events: list.to_json, events_format: "json", events_count: list.size, events_cut: events_cut == true)
        end
        call.update!(redacted: true) if redacted
        call
      end
    rescue StandardError => e
      Rails.logger.error("[traces] run #{run.try(:id)}: could not record the call: #{e.class}: #{e.message}")
      nil
    end

    # Runs from before spec 030 keep their joined prompt as one "legacy" part; returns how many were added.
    def backfill_legacy!
      count = 0
      TaskRun.where.not(prompt: nil).where.missing(:model_calls).find_each do |run|
        ModelCall.transaction do
          text, redacted = redact(run.prompt)
          output = TaskRun.limit_text(redact(run.output).first, TaskRun::MAX_OUTPUT) if run.output.present?
          call = ModelCall.create!(task_run: run, user_id: run.user_id || run.task&.user_id, position: 1, pass: run.purpose, layout: "legacy",
                                   agent_id: run.agent_id, agent_name: run.agent_name, preset: run.preset, model: run.model, state: run.state,
                                   started_at: run.started_at, duration_ms: (run.duration && (run.duration * 1000).round),
                                   output_part: (TracePart.for(output) if output), redacted: redacted)
          chunks(text).each_with_index { |chunk, i| call.parts.create!(trace_part: TracePart.for(chunk), position: i + 1, section: 0, kind: "legacy") }
        end
        count += 1
      end
      count
    end

    # G6: events older than COMPRESS_AFTER are deflated. (Calls linked to a rating will be kept as they are once
    # spec 100 adds ratings.) Returns how many were compressed.
    def compress_old!(now: Time.current)
      count = 0
      ModelCall.where(events_format: "json").where(created_at: ...(now - COMPRESS_AFTER)).find_each do |call|
        call.update!(events: Zlib::Deflate.deflate(call.events), events_format: "zlib")
        count += 1
      end
      count
    end

    # Once a day, from the scheduler: compress old events and delete parts nothing uses.
    def run_if_due(now: Time.current)
      @lock ||= Mutex.new
      @lock.synchronize do
        return false if @last_run && @last_run > now - INTERVAL

        @last_run = now
      end
      compress_old!(now: now)
      TracePart.prune_orphans!
      true
    rescue StandardError => e
      Rails.logger.error("[traces] maintenance failed: #{e.class}: #{e.message}")
      false
    end

    private

    # A section split at blank lines; joining the chunks with CHUNK gives the section back exactly.
    def chunks(text) = text.empty? ? [ "" ] : text.split(CHUNK, -1)
  end
end
