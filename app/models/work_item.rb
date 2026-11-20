# Spec 011, G2: an item of a user's work list, kept by the director from the chat.
class WorkItem < ApplicationRecord
  STATES = %w[new planned done cancelled blocked].freeze # spec 012: no "with manager"
  OPEN = %w[new blocked].freeze
  PRIORITIES = %w[normal high].freeze

  belongs_to :user
  belongs_to :space # spec 013
  has_many :tasks, dependent: :nullify # steps; cancelling removes the ones not started (see #cancel!)
  has_many :runs, class_name: "TaskRun", dependent: :nullify
  has_many :epic_steps, -> { order(:position) }, dependent: :destroy # spec 016

  normalizes :title, with: ->(value) { value.to_s.strip.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :priority, inclusion: { in: PRIORITIES }
  validate :space_of_user
  before_validation(on: :create) { self.space ||= Space.default_for(user) if user } # the only active space, or "General"

  STATE_ORDER = %w[new planned blocked done].freeze # spec 013: kanban columns; cancelled folded below

  scope :listed, -> { order(Arel.sql("CASE state WHEN 'done' THEN 2 WHEN 'cancelled' THEN 3 ELSE 1 END"), Arel.sql("CASE priority WHEN 'high' THEN 0 ELSE 1 END"), :position, :id) }
  # Spec 016, G2: new epics are planned at once (their start time only decides when the steps run); never in
  # archived spaces (spec 013, S4).
  scope :due, ->(_now = Time.current) { where(state: "new").where(space_id: Space.active.select(:id)) }

  def state_label = state.tr("_", " ")
  def open? = OPEN.include?(state)

  def active_run? = runs.where(state: %w[queued running]).exists?

  # Steps not started are dropped (spec 011: calendar steps; spec 016, G7: pending steps are cancelled; a running
  # step finishes and its answer is kept).
  def cancel!
    transaction do
      tasks.where("starts_at > ?", Time.current).find_each(&:destroy!)
      epic_steps.where(state: %w[pending queued]).find_each { |step| step.update!(state: "cancelled") }
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

  def block!(reason)
    update!(state: "blocked", blocked_reason: reason.to_s.truncate(2000), finished_at: (Time.current if started_at))
  end

  private

  # The space is the user's own; a new epic, or one moved to another space, needs an active space (S4).
  def space_of_user
    return unless space

    errors.add(:space, "is not one of your spaces") if space.user_id != user_id
    errors.add(:space, "is archived") if (new_record? || space_id_changed?) && !space.active?
  end
end
