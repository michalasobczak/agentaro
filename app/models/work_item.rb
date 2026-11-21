# Spec 011, G2: an item of a user's work list, kept by the director from the chat.
class WorkItem < ApplicationRecord
  STATES = %w[new planned done cancelled blocked].freeze # spec 012: no "with manager"
  OPEN = %w[new blocked].freeze
  PRIORITIES = %w[normal high].freeze

  belongs_to :user
  belongs_to :space # spec 013
  belongs_to :recurring_order, optional: true # spec 034: the order this occurrence came from
  has_many :tasks, dependent: :nullify # steps; cancelling removes the ones not started (see #cancel!)
  has_many :runs, class_name: "TaskRun", dependent: :nullify
  has_many :epic_steps, -> { order(:position) }, dependent: :destroy # spec 016
  has_many :step_decisions, dependent: :destroy # spec 033

  normalizes :title, with: ->(value) { value.to_s.strip.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :priority, inclusion: { in: PRIORITIES }
  validate :space_of_user
  before_update :retire_plan_on_move, if: :will_save_change_to_space_id?
  before_validation(on: :create) { self.space ||= Space.default_for(user) if user } # the only active space, or "General"

  STATE_ORDER = %w[new planned blocked done].freeze # spec 013: the stored states, in order
  # Owner fix ("dlaczego to, co jest w trakcie, nazywasz planned?"): what the user sees — a planned epic whose steps
  # have started is "running" (the stored state stays planned). Board columns; cancelled folded below.
  BOARD_STATES = %w[new planned running blocked done].freeze

  scope :listed, -> { order(Arel.sql("CASE state WHEN 'done' THEN 2 WHEN 'cancelled' THEN 3 ELSE 1 END"), Arel.sql("CASE priority WHEN 'high' THEN 0 ELSE 1 END"), :position, :id) }
  # Spec 016, G2: new epics are planned at once (their start time only decides when the steps run); never in
  # archived spaces (spec 013, S4).
  scope :due, ->(_now = Time.current) { where(state: "new").where(space_id: Space.active.select(:id)) }

  def state_label = state.tr("_", " ")
  def board_state = running? ? "running" : state
  def open? = OPEN.include?(state)

  def active_steps = epic_steps.where(position: active_step_from..)

  def active_run? = runs.where(state: %w[queued running]).exists?

  # Steps not started are dropped (spec 011: calendar steps; spec 016, G7: pending steps are cancelled; a running
  # step finishes and its answer is kept).
  after_update_commit :record_outcome, if: -> { saved_change_to_state? && state.in?(%w[done blocked]) } # spec 031, G3

  def cancel!
    transaction do
      reload
      runs.where(user_id: user_id, purpose: "epic_step", state: "queued").find_each do |run|
        run.update!(state: "skipped", error: "The epic was cancelled before this step started.", finished_at: Time.current)
      end
      tasks.where("starts_at > ?", Time.current).find_each(&:destroy!)
      epic_steps.where(state: %w[pending queued waiting]).find_each { |step| step.update!(state: "cancelled") } # spec 033: waiting
      step_decisions.pending.each { |d| d.update!(status: "answered", answer: "(the epic was cancelled)") }
      update!(state: "cancelled", finished_at: (Time.current if started_at))
    end
  end

  # Spec 013, Q10: the user closes an epic by hand.
  def done! = update!(state: "done", blocked_reason: nil, finished_at: finished_at || (Time.current if started_at))

  # Spec 016: started and not finished — its steps are running or about to.
  def running? = state == "planned" && started_at.present?

  # Spec 016, G8: in the calendar an epic runs from its start to its end — "now" while running, a short mark while
  # waiting. Epics planned before spec 016 span their calendar steps (Q7).
  MARK = 15.minutes

  def span(now = Time.current)
    if (start = started_at || (starts_at if state == "planned"))
      finish = finished_at || (running? ? now : start + MARK)
      return start...[ finish, start + 1.minute ].max
    end
    starts, ends = tasks.map(&:starts_at).min, tasks.map(&:ends_at).max
    starts && (starts...ends)
  end

  # Spec 033, G1: at level Pytaj a new plan waits for the owner's Approve. True when this call approved it.
  def approve_plan!
    approved = transaction do
      reload
      next false unless state == "planned" && awaiting_approval

      update!(awaiting_approval: false)
    end
    StepChain.start_due(user: user) if approved
    approved
  end

  def block!(reason)
    block_dismissed_at_will_change! # written even when this copy never saw the notice closed (another request did)
    update!(state: "blocked", blocked_reason: reason.to_s.truncate(2000), finished_at: (Time.current if started_at),
            block_dismissed_at: nil) # spec 026: a new block shows its notice again
  end

  # Spec 026: blocked epics whose notice the user has not closed.
  scope :block_notices, -> { where(state: "blocked", block_dismissed_at: nil) }

  private

  def retire_plan_on_move
    self.awaiting_approval = false # spec 033: a new plan is approved anew
    step_decisions.pending.each { |d| d.update!(status: "answered", answer: "(the plan was replaced)") }
    self.active_step_from = (epic_steps.maximum(:position) || 0) + 1
    self.plan_summary = self.blocked_reason = self.started_at = self.finished_at = nil
  end

  # The space is the user's own; a new epic, or one moved to another space, needs an active space (S4).
  def space_of_user
    return unless space

    errors.add(:space, "is not one of your spaces") if space.user_id != user_id
    errors.add(:space, "is archived") if (new_record? || space_id_changed?) && !space.active?
  end

  private

  def record_outcome = Brain.record_epic(self, state == "done" ? "epic_done" : "epic_blocked")
end
