# Spec 034: recurring work — an order that creates a new epic in its space each time it is due (G1, G3).
# Due times are computed from the schedule (resilience), in Europe/Warsaw. One occurrence at a time (G7, R3);
# occurrences missed while Agentaro was off collapse into one. Later occurrences reuse the last plan that
# succeeded (G4) and see the previous occurrence's result (G5).
class RecurringOrder < ApplicationRecord
  KINDS = %w[daily weekly monthly hourly].freeze
  STATES = %w[active paused].freeze
  REPORTS = %w[always attention].freeze
  MAX_ACTIVE = 20
  DAY_NAMES = %w[Mon Tue Wed Thu Fri Sat Sun].freeze
  PREVIOUS_BYTES = 2048 # G5

  self.changelog_ignored = %w[next_at] # bookkeeping of the schedule; real changes are recorded

  belongs_to :user
  belongs_to :space
  has_many :work_items, dependent: :nullify

  normalizes :title, with: ->(v) { v.to_s.squish }
  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }
  validates :report, inclusion: { in: REPORTS }
  validates :at_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "must be HH:MM" }
  validates :starts_on, presence: true
  validates :every_hours, numericality: { only_integer: true, in: 1..168, message: "must be 1 to 168 hours (R2: at least 1 hour apart)" }, if: -> { kind == "hourly" }
  validates :month_day, numericality: { only_integer: true, in: 1..31 }, if: -> { kind == "monthly" }
  validate :weekdays_valid, :space_is_own, :ends_after_start, :active_limit

  before_validation { self.starts_on ||= Time.zone.today }
  before_save :schedule_next, if: -> { new_record? || (changed & %w[kind at_time weekdays month_day every_hours starts_on ends_on state]).any? }

  scope :active, -> { where(state: "active") }

  def active? = state == "active"
  def weekday_list = weekdays.to_s.split(",").map(&:to_i).select { |d| d.between?(1, 7) }.uniq.sort

  # The first occurrence strictly after `after`, or nil past the end date.
  def next_occurrence(after: Time.current)
    hour, minute = at_time.split(":").map(&:to_i)
    from = [ after, Time.zone.local(starts_on.year, starts_on.month, starts_on.day) - 1.second ].max
    found = case kind
            when "hourly"
              anchor = Time.zone.local(starts_on.year, starts_on.month, starts_on.day, hour, minute)
              step = every_hours.hours
              from < anchor ? anchor : anchor + (((from - anchor) / step).floor + 1) * step
            else
              date = from.to_date
              (0..400).lazy.map { |i| date + i }.filter_map { |day|
                next unless kind != "weekly" || weekday_list.include?(day.cwday)
                next unless kind != "monthly" || day.day == [ month_day, day.end_of_month.day ].min

                at = Time.zone.local(day.year, day.month, day.day, hour, minute)
                at if at > from
              }.first
            end
    found if found && (ends_on.nil? || found.to_date <= ends_on)
  end

  def upcoming(from, to, limit: 60)
    list = []
    at = next_occurrence(after: from - 1.second)
    while at && at < to && list.size < limit
      list << at
      at = next_occurrence(after: at)
    end
    list
  end

  # "every Monday and Friday at 08:00, from 24 Nov" — how the schedule is said back (G2).
  def schedule_text
    what = case kind
           when "daily" then "every day at #{at_time}"
           when "weekly" then "every #{weekday_list.map { |d| DAY_NAMES[d - 1] }.join(", ")} at #{at_time}"
           when "monthly" then "every month on day #{month_day} at #{at_time}#{" (the last day in shorter months)" if month_day.to_i > 28}"
           when "hourly" then "every #{every_hours == 1 ? "hour" : "#{every_hours} hours"} from #{at_time}"
           end
    "#{what}, from #{starts_on.strftime("%-d %b %Y")}#{", until #{ends_on.strftime("%-d %b %Y")}" if ends_on}"
  end

  def last_epic = work_items.order(:id).last

  # Scheduler pass: every active order whose time has come gets its occurrence (G3), or a note why not (G7).
  def self.run_due(now: Time.current)
    active.where(next_at: ..now).find_each.filter_map { |order| order.occur!(now: now) }
  end

  def occur!(now: Time.current)
    item = transaction do
      reload
      next unless active? && next_at && next_at <= now

      due = next_at
      update!(next_at: next_occurrence(after: now)) # missed ones collapse into this one (G7)
      next skip!("the space is archived") unless space.active?

      previous = last_epic
      next skip!("the previous occurrence \"#{previous.title}\" is still #{previous.board_state}") if previous && previous.state.in?(%w[new planned blocked])

      create_epic!(due)
    end
    return unless item

    item.state == "planned" ? StepChain.start_due(user: user) : ManagementRunner.dispatch_due(user: user)
    item
  end

  # G4: the plan of the last occurrence that succeeded, while its agents are still the owner's usable members.
  def reusable_plan
    return unless last_plan.is_a?(Array) && last_plan.any?

    members = user.team_roles.members.includes(:agent).to_h { |m| [ m.agent_id, m.agent ] }
    last_plan if last_plan.all? { |s| members[s["agent"].to_i]&.usable? }
  end

  # Called when an occurrence finished: its steps become the plan to reuse.
  def remember_plan!(item)
    steps = item.active_steps.where.not(state: "replaced").map { |s| { "title" => s.title, "description" => s.description.to_s, "agent" => s.agent_id, "minutes" => s.time_limit_minutes } }
    update!(last_plan: steps, last_plan_summary: item.plan_summary) if steps.any? && steps.all? { |s| s["agent"] }
  end

  # G5: what the previous finished occurrence found, for this occurrence's steps.
  def previous_answer(item)
    previous = work_items.where(state: "done").where.not(id: item.id).order(:id).last or return
    run = TaskRun.where(work_item_id: previous.id, purpose: "epic_step", state: "succeeded").order(:id).last or return
    text = TaskRun.prompt_text(run.output).strip
    text.empty? ? nil : [ previous, TaskRun.limit_text(text, PREVIOUS_BYTES) ]
  end

  private

  def create_epic!(due)
    title = "#{self.title} — #{due.in_time_zone.strftime("%d.%m")}#{" #{due.in_time_zone.strftime("%H:%M")}" if kind == "hourly"}".truncate(200)
    plan = reusable_plan
    item = user.work_items.create!(title: title, description: description, space: space, recurring_order: self,
                                   position: user.work_items.maximum(:position).to_i + 1, state: plan ? "planned" : "new",
                                   plan_summary: (last_plan_summary if plan))
    plan&.each_with_index { |s, i| item.epic_steps.create!(position: i + 1, title: s["title"], description: s["description"].presence, agent_id: s["agent"], time_limit_minutes: s["minutes"]) } # spec 040
    update!(last_occurrence_at: due, note: nil)
    item
  end

  def skip!(why)
    update!(note: "Skipped #{Time.current.strftime("%-d %b %H:%M")}: #{why}.")
    nil
  end

  def schedule_next
    self.next_at = active? ? next_occurrence(after: [ Time.current, last_occurrence_at || Time.zone.at(0) ].max) : nil
  end

  def weekdays_valid
    return unless kind == "weekly"

    errors.add(:weekdays, "must name at least one day (1 = Monday … 7 = Sunday)") if weekday_list.empty?
    self.weekdays = weekday_list.join(",")
  end

  def space_is_own
    errors.add(:space, "must be one of your spaces") if space && space.user_id != user_id
  end

  def ends_after_start
    errors.add(:ends_on, "must not be before the start") if ends_on && starts_on && ends_on < starts_on
  end

  def active_limit
    return unless active? && user && (new_record? || will_save_change_to_state?)

    errors.add(:base, "at most #{MAX_ACTIVE} active recurring orders") if user.recurring_orders.active.where.not(id: id).count >= MAX_ACTIVE
  end
end
