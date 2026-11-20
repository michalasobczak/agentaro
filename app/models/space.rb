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
  normalizes :working_dir, with: ->(value) { value.to_s.strip.presence }

  before_validation { self.goal = nil if team? } # spec 014, R1: a team space has no goal

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :goal, presence: { message: "is required for a project space" }, if: :project?
  validates :goal, length: { maximum: 2000 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validate :working_dir_usable

  scope :active, -> { where(state: "active") }
  scope :ordered, -> { order(Arel.sql("CASE state WHEN 'active' THEN 0 ELSE 1 END"), Arel.sql("LOWER(name)")) }

  # Spec 018: folders agents of a space with a working folder may never read — Agentaro's storage, the runs of
  # other steps — and the working folders of all other spaces (of every user), except folders that contain this one.
  def self.protected_dirs = [ Rails.root.join("storage"), Pathname(Rails.application.config.x.runs_dir).dirname ].map { |p| File.expand_path(p.to_s) }

  def denied_dirs
    others = Space.where.not(working_dir: nil).where.not(id: id).distinct.pluck(:working_dir)
    others.reject! { |dir| working_dir == dir || working_dir.start_with?(dir.end_with?("/") ? dir : "#{dir}/") }
    (self.class.protected_dirs + others).uniq
  end

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

  private

  # Spec 018, R1: an absolute path to an existing folder, stored resolved; never "/", Agentaro's storage or the runs.
  def working_dir_usable
    return if working_dir.blank?
    return errors.add(:working_dir, "must be an absolute path, e.g. /Users/you/Code/project") unless working_dir.start_with?("/")
    return errors.add(:working_dir, "does not exist or is not a folder") unless File.directory?(working_dir)

    self.working_dir = File.realpath(working_dir)
    return errors.add(:working_dir, "cannot be the whole disk") if working_dir == "/"

    if self.class.protected_dirs.any? { |dir| working_dir == dir || working_dir.start_with?("#{dir}/") }
      errors.add(:working_dir, "cannot be Agentaro's storage or runs folder")
    end
  end
end
