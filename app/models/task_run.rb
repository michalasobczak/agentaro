# Spec 010: one run of a task occurrence on its agent's executor (G5).
class TaskRun < ApplicationRecord
  STATES = %w[queued running succeeded failed timed_out skipped].freeze
  FINISHED = %w[succeeded failed timed_out skipped].freeze
  TRIGGERS = %w[scheduled manual].freeze
  MAX_OUTPUT = 200 * 1024 # bytes kept of an answer (G4)
  MAX_ERROR = 20 * 1024

  self.changelog_summarized = %w[prompt output error] # long texts: the changelog keeps their size, not the text

  belongs_to :task

  validates :state, inclusion: { in: STATES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :occurrence_start, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def finished? = FINISHED.include?(state)
  def ok? = state == "succeeded"
  def duration = started_at && finished_at ? finished_at - started_at : nil

  def state_label = state.tr("_", " ")

  # Truncates on character boundaries so stored text stays valid UTF-8.
  def self.limit_text(text, bytes)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    return text if text.bytesize <= bytes

    text.byteslice(0, bytes).scrub("") + "\n[… cut at #{bytes / 1024} KB]"
  end
end
