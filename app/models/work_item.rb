# Spec 011, G2: an item of a user's work list, kept by the director from the chat.
class WorkItem < ApplicationRecord
  STATES = %w[new planned done cancelled blocked].freeze # spec 012: no "with manager"
  OPEN = %w[new blocked].freeze
  PRIORITIES = %w[normal high].freeze

  belongs_to :user
  belongs_to :project # spec 013
  has_many :tasks, dependent: :nullify # steps; cancelling removes the ones not started (see #cancel!)
  has_many :runs, class_name: "TaskRun", dependent: :nullify

  normalizes :title, with: ->(value) { value.to_s.strip.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :priority, inclusion: { in: PRIORITIES }
  validate :project_of_user
  before_validation(on: :create) { self.project ||= Project.default_for(user) if user } # the only active project, or "General"

  STATE_ORDER = %w[new planned blocked done].freeze # spec 013: kanban columns; cancelled folded below

  scope :listed, -> { order(Arel.sql("CASE state WHEN 'done' THEN 2 WHEN 'cancelled' THEN 3 ELSE 1 END"), Arel.sql("CASE priority WHEN 'high' THEN 0 ELSE 1 END"), :position, :id) }
  scope :due, ->(now = Time.current) { where(state: "new").where("handle_from IS NULL OR handle_from <= ?", now).where(project_id: Project.active.select(:id)) } # S4

  def state_label = state.tr("_", " ")
  def open? = OPEN.include?(state)

  def active_run? = runs.where(state: %w[queued running]).exists?

  def cancel!
    transaction do
      tasks.where("starts_at > ?", Time.current).find_each(&:destroy!) # steps not started yet
      update!(state: "cancelled")
    end
  end

  # Spec 013, Q10: the user closes an epic by hand.
  def done! = update!(state: "done", blocked_reason: nil)

  # Spec 013, G9: an epic in the calendar spans its steps.
  def span(tasks = self.tasks)
    starts, ends = tasks.map(&:starts_at).min, tasks.map(&:ends_at).max
    starts && (starts...ends)
  end

  def block!(reason)
    update!(state: "blocked", blocked_reason: reason.to_s.truncate(2000))
  end

  private

  # The project is the user's own; a new epic, or one moved to another project, needs an active project (S4).
  def project_of_user
    return unless project

    errors.add(:project, "is not one of your projects") if project.user_id != user_id
    errors.add(:project, "is archived") if (new_record? || project_id_changed?) && !project.active?
  end
end
