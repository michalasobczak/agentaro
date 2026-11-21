# Spec 016: one step of an epic — an ordered task for a team member, without a time. Steps run one after another
# (StepChain); each run is a TaskRun with purpose "epic_step".
class EpicStep < ApplicationRecord
  # spec 033: waiting — for the owner's decision; spec 040: reviewing — the director decides after a failed attempt,
  # replaced — a failed step the director replanned (counts as done for the epic, its answer is not passed on)
  STATES = %w[pending queued running succeeded failed timed_out skipped cancelled waiting reviewing replaced].freeze
  DONE = %w[succeeded replaced].freeze
  LIMIT_MINUTES = (5..240) # spec 040, R5
  DEFAULT_LIMIT_MINUTES = 30
  STOPPED = %w[failed timed_out skipped].freeze

  belongs_to :work_item
  belongs_to :agent, optional: true # cleared when the agent is deleted; such a step is skipped
  has_many :runs, class_name: "TaskRun", dependent: :nullify
  has_many :step_decisions, dependent: :destroy # spec 033

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :time_limit_minutes, numericality: { only_integer: true, in: LIMIT_MINUTES, message: "must be 5 to 240 minutes" }, allow_nil: true
  has_many :step_reviews, dependent: :destroy # spec 040

  scope :ordered, -> { order(:position) }

  def last_run = runs.max_by(&:id)
  def state_label = { "reviewing" => "director decides" }.fetch(state, state.tr("_", " "))

  # Spec 040, G2: the step's own time limit, 30 minutes when the director gave none.
  def time_limit = time_limit_minutes || DEFAULT_LIMIT_MINUTES
  def time_limit_seconds = time_limit * 60
  def stopped? = STOPPED.include?(state)

  # Spec 032, G4: "retrying at 14:05 (attempt 2 of 3) — usage limit" while an automatic retry waits, else nil.
  def retry_note(now: Time.current)
    run = runs.where(purpose: "epic_step", work_item_id: work_item_id).order(id: :desc).first(2)
    StepRetry.note(run.first, run.second) if StepRetry.waiting?(run.first, now: now)
  end
end
