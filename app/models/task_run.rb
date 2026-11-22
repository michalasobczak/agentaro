# Spec 010: one run of a task occurrence on its agent's executor (G5).
class TaskRun < ApplicationRecord
  STATES = %w[queued running succeeded failed timed_out skipped].freeze
  FINISHED = %w[succeeded failed timed_out skipped].freeze
  TRIGGERS = %w[scheduled manual retry].freeze # spec 032: retry — an automatic retry of a failed step
  PURPOSES = %w[step epic_step chat verify director manager review memory step_review summary].freeze # spec 045: summary — the director sums up a finished epic # spec 040: step_review — the director decides about a step # spec 031: memory — the brain's local model # spec 016: epic_step — a step of an epic, run in sequence # spec 011: management runs have no calendar task; spec 012: manager and review only in old runs
  # Spec 036, R1: the runs that take one of their agent's parallel slots — steps of epics and of calendar tasks.
  LIMITED_PURPOSES = %w[step epic_step].freeze
  MAX_OUTPUT = 200 * 1024 # bytes kept of an answer (G4)
  MAX_ERROR = 20 * 1024

  self.changelog_summarized = %w[prompt output error] # long texts: the changelog keeps their size, not the text

  belongs_to :task, optional: true
  belongs_to :user, optional: true      # owner of a management run
  belongs_to :work_item, optional: true
  belongs_to :agent, optional: true     # agent of a management run or an epic step
  belongs_to :epic_step, optional: true # spec 016
  has_many :step_decisions, dependent: :nullify # spec 033
  has_many :model_calls, -> { order(:position) }, dependent: :destroy, inverse_of: :task_run # spec 030: its traces

  validates :state, inclusion: { in: STATES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :occurrence_start, presence: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :task, presence: true, if: -> { purpose == "step" }
  validates :user, presence: true, unless: -> { purpose == "step" }
  validates :epic_step, presence: true, if: -> { purpose == "epic_step" }, on: :create

  # Spec 036: a calendar run takes its task's agent, so it counts towards that agent's limit (R2).
  before_validation(on: :create) { self.agent_id ||= task&.agent_id if step? }

  # Spec 036, R2/R3: the runs that hold a slot of the agent now (state running is the slot).
  scope :occupying, ->(agent_id) { where(state: "running", purpose: LIMITED_PURPOSES, agent_id: agent_id) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  # Runs of tasks the user may see, and the user's own management runs (spec 011).
  scope :visible_to, ->(user) { where(task_id: Task.visible_to(user).select(:id)).or(where(task_id: nil, user_id: user.id)) }

  def step? = purpose == "step"
  def limited? = LIMITED_PURPOSES.include?(purpose) # spec 036

  def finished? = FINISHED.include?(state)
  def ok? = state == "succeeded"
  def duration = started_at && finished_at ? finished_at - started_at : nil

  def state_label = state.tr("_", " ")

  def self.prompt_text(text)
    text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?").delete("\0")
        .gsub(/\r\n|[\r\v\f\u0085\u2028\u2029]/, "\n")
  end

  # Truncates on character boundaries so stored text stays valid UTF-8.
  def self.limit_text(text, bytes)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    return text if text.bytesize <= bytes

    text.byteslice(0, bytes).scrub("") + "\n[… cut at #{bytes / 1024} KB]"
  end

  # Errors end with what matters (tools print their logs first), so a long error keeps its end (owner fix: a Codex
  # failure was cut away behind 20 KB of its own log).
  def self.limit_tail(text, bytes)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    return text if text.bytesize <= bytes

    "[… #{(text.bytesize - bytes) / 1024} KB of log left out …]\n" + text.byteslice(text.bytesize - bytes, bytes).scrub("")
  end
end
