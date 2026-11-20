# Spec 016: one step of an epic — an ordered task for a team member, without a time. Steps run one after another
# (StepChain); each run is a TaskRun with purpose "epic_step".
class EpicStep < ApplicationRecord
  STATES = %w[pending queued running succeeded failed timed_out skipped cancelled].freeze
  STOPPED = %w[failed timed_out skipped].freeze

  belongs_to :work_item
  belongs_to :agent, optional: true # cleared when the agent is deleted; such a step is skipped
  has_many :runs, class_name: "TaskRun", dependent: :nullify

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(:position) }

  def last_run = runs.max_by(&:id)
  def state_label = state.tr("_", " ")
  def stopped? = STOPPED.include?(state)
end
