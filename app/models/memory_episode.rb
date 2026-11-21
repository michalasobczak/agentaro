# Spec 031, G3: evidence — a pointer to something that happened (a message, an epic's outcome) with a short excerpt.
# Episodes of the user's messages wait for extraction (processed_at nil).
class MemoryEpisode < ApplicationRecord
  KINDS = %w[user_message director_answer epic_done epic_blocked edit import].freeze
  EXCERPT = 1500
  self.changelog_summarized = %w[excerpt]

  belongs_to :user
  has_many :memory_fact_sources, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :excerpt, presence: true

  scope :pending, -> { where(processed_at: nil, kind: %w[user_message import]) }
  scope :due, ->(now = Time.current) { pending.where(next_attempt_at: nil).or(pending.where(next_attempt_at: ..now)) }

  def source = source_type && source_id ? source_type.safe_constantize&.find_by(id: source_id) : nil

  def self.record!(user, kind, excerpt, source: nil, at: Time.current)
    create!(user: user, kind: kind, excerpt: excerpt.to_s.strip.truncate(EXCERPT), occurred_at: at,
            source_type: source&.class&.name, source_id: source&.id)
  end
end
