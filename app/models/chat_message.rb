# Spec 011, G1: the conversation between a user and their director.
class ChatMessage < ApplicationRecord
  AUTHORS = %w[user director verifier system].freeze # spec 019: verifier

  self.changelog_summarized = %w[content actions_summary]

  belongs_to :user
  belongs_to :task_run, optional: true

  validates :author, inclusion: { in: AUTHORS }
  validates :content, presence: true, length: { maximum: 20_000 }

  after_create_commit { Brain.record_message(self) } # spec 031, G3

  scope :ordered, -> { order(:created_at, :id) }
  scope :current, -> { where(archived_at: nil) } # spec 015: the conversation going on now
  scope :archived, -> { where.not(archived_at: nil) }
end
