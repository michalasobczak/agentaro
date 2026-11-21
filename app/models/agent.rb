# Spec 009: an agent — who it is (master prompt, written by people only) and what it runs on (executor).
#
# Private agents belong to one user; shared agents are made by admins and used by everyone (Q1).
# Running tasks, memory and self-improvement come in specs 010–012.
class Agent < ApplicationRecord
  KINDS = %w[private shared].freeze
  # Spec 036, R1: how many steps (of epics or calendar tasks) the agent may run at the same time, in all spaces.
  PARALLEL_DEFAULT = 6
  PARALLEL_RANGE = 1..10

  belongs_to :user # author; owner of a private agent
  belongs_to :executor
  has_many :tasks, dependent: nil # unassigned in before_destroy, with the changelog (R5)
  has_many :team_roles, dependent: :destroy # spec 011

  normalizes :name, :description, :model, with: ->(value) { value.to_s.strip.presence }
  normalizes :effort, with: ->(value) { value.to_s.strip.presence }
  normalizes :master_prompt, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 60 }
  validates :description, length: { maximum: 500 }
  validates :master_prompt, presence: true, length: { maximum: 20_000 }
  validates :model, length: { maximum: 200 }
  validates :model, format: { with: Executor::MODEL_NAME, message: Executor::MODEL_NAME_RULE }, allow_nil: true # spec 022, R1
  validates :max_parallel_tasks, numericality: { only_integer: true, in: PARALLEL_RANGE } # spec 036, S1
  validate :effort_allowed # spec 022, G5
  validate :name_unique_in_its_list
  validate :kind_fixed, on: :update
  validate :shared_only_by_admins, on: :create

  before_destroy :unassign_tasks
  # Spec 036, R4/R7: a changed limit (or an agent switched on or off) counts for the next start at once.
  after_commit(on: %i[create update]) { Agentaro::TaskScheduler.wake(rescale: true) }
  after_destroy_commit { Brain.forget_scope(MemoryFact.where(subject_type: "agent", subject_id: id).select(:user_id), "agent", id) } # spec 031

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

  # Spec 036, R2/R3: the steps it runs now, of every user and space — the same count the scheduler starts by.
  def running_tasks = TaskRun.occupying(id).count
  def full? = running_tasks >= max_parallel_tasks

  # Spec 036, R7: the most steps one agent may run at once — the shared worker pool is sized by it.
  def self.highest_parallel_limit = where(enabled: true).maximum(:max_parallel_tasks) || PARALLEL_DEFAULT

  def runtime_label = [ executor.name, effective_model, effective_effort && "effort #{effective_effort}" ].compact.join(" · ")

  # Spec 022: what a call uses — the agent's own choice, else the executor's default. An effort the tool does not take
  # (e.g. after a change of executor) is never passed.
  def effective_model = model || executor&.default_model
  def effective_effort = (effort || executor&.effort).presence_in(executor&.efforts || [])

  private

  def name_unique_in_its_list
    return if name.blank?

    others = Agent.where(kind: kind).where("lower(name) = ?", name.downcase).where.not(id: id)
    others = others.where(user_id: user_id) if private?
    errors.add(:name, "has already been taken") if others.exists?
  end

  def effort_allowed
    errors.add(:effort, "is not one this agent's executor takes") if effort && !executor&.efforts&.include?(effort)
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
    EpicStep.where(agent_id: id).find_each { |step| step.update_attribute(:agent_id, nil) } # spec 016: such a step is skipped
  end
end
