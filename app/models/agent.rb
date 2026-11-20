# Spec 009: an agent — who it is (master prompt, written by people only) and what it runs on (executor).
#
# Private agents belong to one user; shared agents are made by admins and used by everyone (Q1).
# Running tasks, memory and self-improvement come in specs 010–012.
class Agent < ApplicationRecord
  KINDS = %w[private shared].freeze

  belongs_to :user # author; owner of a private agent
  belongs_to :executor
  has_many :tasks, dependent: nil # unassigned in before_destroy, with the changelog (R5)
  has_many :team_roles, dependent: :destroy # spec 011

  normalizes :name, :description, :model, with: ->(value) { value.to_s.strip.presence }
  normalizes :master_prompt, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 60 }
  validates :description, length: { maximum: 500 }
  validates :master_prompt, presence: true, length: { maximum: 20_000 }
  validates :model, length: { maximum: 200 }
  validate :name_unique_in_its_list
  validate :kind_fixed, on: :update
  validate :shared_only_by_admins, on: :create

  before_destroy :unassign_tasks

  scope :ordered, -> { order(:name) }
  # G2: my private agents and every shared agent; admins do not see other users' private agents.
  scope :visible_to, ->(user) { where(kind: "shared").or(where(kind: "private", user_id: user.id)) }
  # R3: what may be put on a task — usable agents, shared only for system-wide tasks.
  scope :assignable, ->(user, calendar) {
    base = calendar == "system" ? where(kind: "shared") : visible_to(user)
    base.where(enabled: true).joins(:executor).where(executors: { enabled: true })
  }

  def shared? = kind == "shared"
  def private? = kind == "private"

  def editable_by?(someone) = shared? ? someone.admin? : user_id == someone.id

  # Disabled agents, or agents on a disabled executor, keep their tasks but get no new ones (S3).
  def usable? = enabled? && executor.enabled?

  def runtime_label = [ executor.name, model || executor.default_model ].compact.join(" · ")

  private

  def name_unique_in_its_list
    return if name.blank?

    others = Agent.where(kind: kind).where("lower(name) = ?", name.downcase).where.not(id: id)
    others = others.where(user_id: user_id) if private?
    errors.add(:name, "has already been taken") if others.exists?
  end

  def kind_fixed
    errors.add(:kind, "cannot be changed after the agent is created") if kind_changed?
  end

  def shared_only_by_admins
    errors.add(:kind, "shared agents are created by admins") if shared? && !user&.admin?
  end

  def unassign_tasks
    tasks.find_each { |task| task.update_attribute(:agent_id, nil) } # runs callbacks: recorded in the changelog
    TaskRun.where(agent_id: id).find_each { |run| run.update_attribute(:agent_id, nil) } # runs keep the agent's name
  end
end
