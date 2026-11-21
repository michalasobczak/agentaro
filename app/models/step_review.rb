# Spec 040: the director looks at a step — after an attempt that did not succeed (kind "failure", G1) or while it runs
# with a process older than PROCESS_AGE (kind "running", G4). Each review is a director run (purpose "step_review");
# StepReviewer asks the director and applies its decision. This replaces spec 032's fixed retry rule.
class StepReview < ApplicationRecord
  KINDS = %w[failure running].freeze
  STATUSES = %w[pending asked decided failed].freeze
  DECISIONS = %w[retry change replan ask stop kill none].freeze
  MAX_ATTEMPTS = 5          # R1: attempts per step
  DAILY_CAP = 20            # R1: retries per owner per day
  INTERVAL = 5.minutes      # R7: a running step is looked at at most this often
  PROCESS_AGE = 5.minutes   # G4: only while it has a process at least this old
  LABELS = {
    "retry" => "retried the step", "change" => "retried the step with changed instructions", "replan" => "replanned the rest of the epic",
    "ask" => "asks you", "stop" => "stopped the epic", "kill" => "stopped processes that hung", "none" => "let it run"
  }.freeze

  belongs_to :user
  belongs_to :work_item
  belongs_to :epic_step
  belongs_to :task_run, optional: true
  belongs_to :review_run, class_name: "TaskRun", optional: true
  belongs_to :step_decision, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :decision, inclusion: { in: DECISIONS }, allow_nil: true

  scope :decided, -> { where(status: "decided") }

  def label = LABELS.fetch(decision.to_s, decision.to_s)

  # G1: called by StepChain.after_run, inside its transaction, for an attempt that did not succeed. Returns
  # [the director's queued run, nil] when the director will decide, or [nil, a note for the block message].
  def self.request!(item, step, run, now: Time.current)
    kind = StepRetry.classify(run)
    run.update!(failure_kind: kind)
    return [ nil, nil ] if kind == "stopped" # the owner stopped it (spec 025): nothing to decide
    return [ nil, " Tried #{run.attempt} times (at most #{MAX_ATTEMPTS})." ] if run.attempt >= MAX_ATTEMPTS
    return [ nil, " The daily limit of #{DAILY_CAP} retries is reached." ] if StepRetry.capped?(item.user, now: now)

    director = item.user.director_role&.agent
    return [ nil, " No director to decide." ] unless director&.usable?

    step.update!(state: "reviewing")
    review_run = queue_run(item, step, director, now)
    create!(user: item.user, work_item: item, epic_step: step, task_run: run, review_run: review_run, kind: "failure")
    [ review_run, nil ]
  end

  def self.queue_run(item, step, director, now = Time.current)
    TaskRun.create!(user: item.user, work_item: item, epic_step: step, agent: director, purpose: "step_review",
                    trigger: "scheduled", occurrence_start: now, state: "queued")
  end

  # G4, R7: scheduler pass — running steps with a process older than PROCESS_AGE get a look, at most every INTERVAL.
  def self.review_running_due(now: Time.current)
    TaskRun.where(purpose: "epic_step", state: "running").includes(:epic_step, work_item: :user).find_each.filter_map do |run|
      step, item = run.epic_step, run.work_item
      next unless step && item && step.state == "running"

      old = ProcessTracker.alive(LiveLog.dir_for(run.id)).select { |p| (Time.zone.parse(p["since"].to_s) rescue now) <= now - PROCESS_AGE }
      next if old.empty?

      last = where(epic_step: step, kind: "running").order(:id).last
      next if last && (last.status == "pending" || last.created_at > now - INTERVAL)

      director = item.user.director_role&.agent
      next unless director&.usable?

      review_run = queue_run(item, step, director, now)
      create!(user: item.user, work_item: item, epic_step: step, task_run: run, review_run: review_run, kind: "running")
      Agentaro::TaskScheduler.enqueue(review_run.id)
      review_run
    end
  end
end
