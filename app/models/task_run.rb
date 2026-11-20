# Spec 010: one run of a task occurrence on its agent's executor (G5).
class TaskRun < ApplicationRecord
  STATES = %w[queued running succeeded failed timed_out skipped].freeze
  FINISHED = %w[succeeded failed timed_out skipped].freeze
  TRIGGERS = %w[scheduled manual].freeze
  PURPOSES = %w[step epic_step chat director manager review].freeze # spec 016: epic_step — a step of an epic, run in sequence # spec 011: management runs have no calendar task; spec 012: manager and review only in old runs
  MAX_OUTPUT = 200 * 1024 # bytes kept of an answer (G4)
  MAX_ERROR = 20 * 1024

  self.changelog_summarized = %w[prompt output error] # long texts: the changelog keeps their size, not the text

  belongs_to :task, optional: true
  belongs_to :user, optional: true      # owner of a management run
  belongs_to :work_item, optional: true
  belongs_to :agent, optional: true     # agent of a management run or an epic step
  belongs_to :epic_step, optional: true # spec 016

  validates :state, inclusion: { in: STATES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :occurrence_start, presence: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :task, presence: true, if: -> { purpose == "step" }
  validates :user, presence: true, unless: -> { purpose == "step" }
  validates :epic_step, presence: true, if: -> { purpose == "epic_step" }, on: :create

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  # Runs of tasks the user may see, and the user's own management runs (spec 011).
  scope :visible_to, ->(user) { where(task_id: Task.visible_to(user).select(:id)).or(where(task_id: nil, user_id: user.id)) }

  def step? = purpose == "step"

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
