# Spec 031, G6: once a day — duplicates merged, unused facts fade, the weakest archived (pinned ones never).
# Contradictions are resolved when they arrive: the extractor sees the related facts and updates or invalidates them.
module Brain
  class Consolidator
    DUPLICATE = 0.95      # cosine similarity above which two facts of one subject are the same
    FADE_AFTER = 60.days  # unused this long: confidence falls
    FADE = 0.9
    ARCHIVE_BELOW = 0.2

    def initialize(user, now: Time.current)
      @user, @now = user, now
    end

    def run
      { merged: merge_duplicates, faded: fade, archived: archive }
    end

    private

    def merge_duplicates
      merged = 0
      @user.memory_facts.active.group_by(&:subject_key).each_value do |facts|
        kept = []
        facts.sort_by { |f| [ f.pinned ? 0 : 1, -f.confidence, f.id ] }.each do |fact|
          twin = kept.find { |k| same?(k, fact) }
          next kept << fact unless twin

          fact.memory_fact_sources.each { |s| twin.memory_fact_sources.find_or_create_by!(memory_episode_id: s.memory_episode_id) }
          fact.update!(status: "invalid", invalid_at: @now, superseded_by: twin)
          merged += 1
        end
      end
      merged
    end

    def same?(a, b)
      a.statement.casecmp?(b.statement) || (a.embedding && b.embedding && Brain.cosine(a.vector, b.vector) >= DUPLICATE)
    end

    def fade
      stale = @user.memory_facts.active.where(pinned: false).where(last_used_at: ...(@now - FADE_AFTER))
                   .or(@user.memory_facts.active.where(pinned: false, last_used_at: nil).where(valid_from: ...(@now - FADE_AFTER)))
      stale.find_each.count { |f| f.update!(confidence: (f.confidence * FADE).round(3)) }
    end

    def archive
      @user.memory_facts.active.where(pinned: false).where(confidence: ...ARCHIVE_BELOW).find_each.count { |f| f.update!(status: "archived", invalid_at: @now) }
    end
  end
end
