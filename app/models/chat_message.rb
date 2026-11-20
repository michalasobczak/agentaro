# Spec 011, G1: the conversation between a user and their director.
class ChatMessage < ApplicationRecord
  AUTHORS = %w[user director system].freeze

  self.changelog_summarized = %w[content actions_summary]

  belongs_to :user
  belongs_to :task_run, optional: true

  validates :author, inclusion: { in: AUTHORS }
  validates :content, presence: true, length: { maximum: 20_000 }

  scope :ordered, -> { order(:created_at, :id) }
end
