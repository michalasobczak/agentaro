# Specs 013/014: a user's space — a project space (with a goal it works towards) or a team space (no goal: it
# takes care of ongoing work, described in its description). Agents working on an epic see only its own space.
class Space < ApplicationRecord
  STATES = %w[active archived].freeze
  KINDS = %w[project team].freeze
  DEFAULT_NAME = "General"
  DEFAULT_DESCRIPTION = "Everything that does not belong to another space."

  belongs_to :user
  has_many :work_items, dependent: :restrict_with_error # spec 013, R5: only empty spaces can be deleted

  normalizes :name, with: ->(value) { value.to_s.strip.presence }
  normalizes :goal, with: ->(value) { value.to_s.strip.presence }
  normalizes :description, with: ->(value) { value.to_s.strip.presence }

  before_validation { self.goal = nil if team? } # spec 014, R1: a team space has no goal

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :goal, presence: { message: "is required for a project space" }, if: :project?
  validates :goal, length: { maximum: 2000 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where(state: "active") }
  scope :ordered, -> { order(Arel.sql("CASE state WHEN 'active' THEN 0 ELSE 1 END"), Arel.sql("LOWER(name)")) }

  def active? = state == "active"
  def project? = kind == "project"
  def team? = kind == "team"

  # What the space is for, in one line: a project's goal, or what a team space takes care of.
  def purpose = project? ? goal : description

  # Spec 014, G3: how prompts describe the space.
  def purpose_line
    project? ? "project space; goal: #{goal}" : "team space (no goal); takes care of: #{description.presence || "-"}"
  end

  # Where an epic goes when nothing says which space: the only active space, or a new "General" team space (not
  # saved yet — it is saved with the epic). Nil when there are several active spaces, or only archived ones.
  def self.default_for(user)
    active = user.spaces.active.to_a
    return active.first if active.one?
    return nil if active.many? || user.spaces.exists?(name: DEFAULT_NAME)

    user.spaces.new(name: DEFAULT_NAME, kind: "team", description: DEFAULT_DESCRIPTION)
  end
end
