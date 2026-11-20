# Spec 013: a user's project — what they want to achieve (goal) and the epics (work items) that serve it.
# Agents working on an epic see only its own project (G3).
class Project < ApplicationRecord
  STATES = %w[active archived].freeze
  DEFAULT_NAME = "General"
  DEFAULT_GOAL = "Everything that does not belong to another project."

  belongs_to :user
  has_many :work_items, dependent: :restrict_with_error # R5: only empty projects can be deleted

  normalizes :name, with: ->(value) { value.to_s.strip.presence }
  normalizes :goal, with: ->(value) { value.to_s.strip.presence }
  normalizes :description, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :goal, presence: true, length: { maximum: 2000 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where(state: "active") }
  scope :ordered, -> { order(Arel.sql("CASE state WHEN 'active' THEN 0 ELSE 1 END"), Arel.sql("LOWER(name)")) }

  def active? = state == "active"

  # Where an epic goes when nothing says which project: the only active project, or a new "General" (not saved
  # yet — it is saved with the epic). Nil when there are several active projects, or only archived ones.
  def self.default_for(user)
    active = user.projects.active.to_a
    return active.first if active.one?
    return nil if active.many? || user.projects.exists?(name: DEFAULT_NAME)

    user.projects.new(name: DEFAULT_NAME, goal: DEFAULT_GOAL)
  end
end
