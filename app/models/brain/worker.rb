# Spec 031: the brain's background work, driven by the scheduler — extraction of waiting episodes (G4) in its own
# thread so runs never wait for it, and once a day consolidation (G6), missing vectors and the profile summary (Q3).
module Brain
  module Worker
    DAILY = 1.day
    SUMMARY_HOUR = 9 # the daily summary comes in the morning

    class << self
      # Called by the scheduler loop; returns at once (the thread, or nil while the previous one still works).
      # Fix: a flag, not a held mutex — the work ends in another thread, which may not unlock the caller's mutex.
      def kick(now: Time.current)
        return unless Brain.enabled?

        @lock ||= Mutex.new
        @lock.synchronize do
          return if @running

          @running = true
        end
        Thread.new do
          Rails.application.executor.wrap do
            ActiveRecord::Base.uncached do
              Brain::Extractor.process_due(now: now)
              daily(now) if due?(now)
            end
          end
        rescue StandardError => e
          Rails.logger.error("[brain] background work failed: #{e.class}: #{e.message}")
        ensure
          @lock.synchronize { @running = false }
        end
      end

      def due?(now) = @last_daily.nil? || @last_daily < now - DAILY

      def daily(now = Time.current)
        @last_daily = now
        User.where(id: MemoryFact.select(:user_id)).find_each do |user|
          Brain::Consolidator.new(user, now: now).run
          Brain::Extractor.embed_missing(user)
          summarize(user, now) if now.hour >= SUMMARY_HOUR
        end
      end

      # Q3: once a day, the profile facts waiting for approval, as a message in the chat.
      def summarize(user, now = Time.current)
        proposed = user.memory_facts.proposed.where(subject_type: "user").order(:id).to_a
        return if proposed.empty?
        return if user.chat_messages.where(author: "system").where("content LIKE ? OR content LIKE ?", "#{SUMMARY_START[:en]}%", "#{SUMMARY_START[:pl]}%")
                      .where(created_at: (now - 20.hours)..).exists?

        lines = proposed.first(15).map { |f| "- [#{f.id}] #{f.statement}" }.join("\n")
        rest = proposed.size - 15
        content = if polish?(user)
          "#{SUMMARY_START[:pl]} — zostawić?\n#{lines}#{"\n…i #{rest} więcej na stronie Brain." if rest.positive?}\n\n" \
            "Odpisz np. „zostaw wszystkie”, „zostaw 12, usuń 14” albo zdecyduj na stronie Brain."
        else
          "#{SUMMARY_START[:en]} — keep them?\n#{lines}#{"\n…and #{rest} more on the Brain page." if rest.positive?}\n\n" \
            "Reply e.g. \"keep all\", \"keep 12, drop 14\", or decide on the Brain page."
        end
        ChatMessage.create!(user: user, author: "system", content: content)
      end

      SUMMARY_START = { en: "I learned these things about you", pl: "Oto czego dowiedziałem się o Tobie" }.freeze

      # The chat's language (owner fix after spec 017), or Polish when the user's latest message looks Polish.
      def polish?(user)
        return user.chat_language == "pl" unless user.chat_language.to_s.in?([ "", "auto" ])

        user.chat_messages.where(author: "user").order(:id).last&.content.to_s.match?(/[ąćęłńóśźż]|\b(?:jest|nie|się|że|czy|proszę)\b/i)
      end

      # Q5: the chat history from before the brain, once — every user message becomes an episode to extract.
      def import_history(user)
        return 0 if user.memory_episodes.where(kind: "import").exists?

        seen = user.memory_episodes.where(source_type: "ChatMessage").pluck(:source_id).to_set
        user.chat_messages.where(author: "user").find_each.count do |message| # find_each goes by id
          next false if seen.include?(message.id)

          MemoryEpisode.record!(user, "import", message.content, source: message, at: message.created_at)
        end
      end
    end
  end
end
