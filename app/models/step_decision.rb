# Spec 033: a decision a step asked the owner (pending until answered), or an assumption a plan or step made on
# its own (answered by "assumption"). The owner can correct an assumption; the correction becomes a fact in the
# brain for next time (G5). Options and recommendations are data shown escaped, never actions (R5).
class StepDecision < ApplicationRecord
  STATUSES = %w[pending answered].freeze
  BY = %w[owner assumption].freeze
  MAX_ANSWER = 1000

  belongs_to :work_item
  belongs_to :epic_step, optional: true
  belongs_to :task_run, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :answered_by, inclusion: { in: BY }, allow_nil: true
  validates :answer, length: { maximum: MAX_ANSWER }
  validates :correction, length: { maximum: MAX_ANSWER }

  scope :pending, -> { where(status: "pending") }
  scope :assumptions, -> { where(answered_by: "assumption") }

  def pending? = status == "pending"
  def assumption? = answered_by == "assumption"
  def option_list = Array(options)

  # The line shown and reported: "Assumed: …" for assumptions, the question and answer for the owner's decisions.
  def text = question.present? ? "#{question} → #{answer}" : answer.to_s

  # G3: the owner's answer to a pending decision resumes the step that asked (R3). Returns true when it was this
  # call that answered it (one winner).
  def answer_by_owner!(value)
    value = value.to_s.strip
    raise ArgumentError, "the answer is empty" if value.empty?
    raise ArgumentError, "the answer is longer than #{MAX_ANSWER} characters" if value.length > MAX_ANSWER

    item = work_item
    resumed = item.transaction do
      next false unless reload.pending?

      update!(status: "answered", answered_by: "owner", answer: value)
      next true if item.step_decisions.pending.exists? # another question still waits

      step = epic_step
      step.update!(state: "pending") if step&.state == "waiting"
      item.reload
      item.update!(state: "planned", blocked_reason: nil, finished_at: nil) if item.state == "blocked"
      true
    end
    StepChain.queue_next(item.reload) if resumed && item.state == "planned"
    resumed
  end

  # G5: the owner corrects an assumption; it becomes a fact about the space, active at once.
  def correct!(value)
    value = value.to_s.squish
    raise ArgumentError, "the correction is empty" if value.empty?
    raise ArgumentError, "only assumptions can be corrected" unless assumption?

    transaction do
      update!(correction: value.truncate(MAX_ANSWER), corrected_at: Time.current)
      statement = "Instead of assuming \"#{answer.to_s.truncate(100)}\": #{value}".truncate(MemoryFact::MAX)
      work_item.user.memory_facts.create!(subject_type: "space", subject_id: work_item.space_id, statement: statement,
                                          kind: "decision", status: "active", origin: "remembered", confidence: 1.0)
    end
  end
end
