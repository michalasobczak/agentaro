# Spec 011, G2: an item of a user's work list, kept by the director from the chat.
class WorkItem < ApplicationRecord
  STATES = %w[new planned done cancelled blocked].freeze # spec 012: no "with manager"
  OPEN = %w[new blocked].freeze
  PRIORITIES = %w[normal high].freeze

  belongs_to :user
  has_many :tasks, dependent: :nullify # steps; cancelling removes the ones not started (see #cancel!)
  has_many :runs, class_name: "TaskRun", dependent: :nullify

  normalizes :title, with: ->(value) { value.to_s.strip.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :state, inclusion: { in: STATES }
  validates :priority, inclusion: { in: PRIORITIES }

  scope :listed, -> { order(Arel.sql("CASE state WHEN 'done' THEN 2 WHEN 'cancelled' THEN 3 ELSE 1 END"), Arel.sql("CASE priority WHEN 'high' THEN 0 ELSE 1 END"), :position, :id) }
  scope :due, ->(now = Time.current) { where(state: "new").where("handle_from IS NULL OR handle_from <= ?", now) }

  def state_label = state.tr("_", " ")
  def open? = OPEN.include?(state)

  def active_run? = runs.where(state: %w[queued running]).exists?

  def cancel!
    transaction do
      tasks.where("starts_at > ?", Time.current).find_each(&:destroy!) # steps not started yet
      update!(state: "cancelled")
    end
  end

  def block!(reason)
    update!(state: "blocked", blocked_reason: reason.to_s.truncate(2000))
  end
end
