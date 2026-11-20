# Spec 007: a calendar task — one-time or a recurring series.
#
# A series is stored once; its occurrences are computed when a view is shown (R3). Occurrences
# removed or moved on their own are listed in TaskException. Times are stored in UTC and computed in
# the app's time zone, so a daily task at 09:00 stays at 09:00 across daylight-saving changes.
class Task < ApplicationRecord
  CALENDARS = %w[private system].freeze
  REPEATS = %w[none daily weekly monthly].freeze
  MIN_DURATION = 1.minute
  MAX_DURATION = 4.days
  MAX_ALL_DAY_DAYS = 4
  SERIES_LIMIT = 3.months # Q3: a series lasts at most a quarter

  # One appearance of a task in the calendar. original_start identifies it within its series.
  Occurrence = Data.define(:task, :starts_at, :ends_at, :original_start) do
    def key = "#{task.id}-#{original_start.to_i}"
    def all_day? = task.all_day?
    def duration = ends_at - starts_at
    def recurring? = task.recurring?
  end

  belongs_to :user # author
  belongs_to :agent, optional: true # spec 009
  belongs_to :work_item, optional: true # spec 011, 012: a step of an item planned by the director
  attr_accessor :agent_refused # set by the form when the chosen agent may not be assigned (R3)
  has_many :exceptions, class_name: "TaskException", dependent: :destroy
  has_many :runs, class_name: "TaskRun", dependent: :destroy # spec 010

  normalizes :title, :location, with: ->(value) { value.to_s.strip.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :location, length: { maximum: 200 }
  validates :description, length: { maximum: 5000 }
  validates :calendar, inclusion: { in: CALENDARS }
  validates :repeat, inclusion: { in: REPEATS }
  validates :repeat_interval, numericality: { only_integer: true, in: 1..99 }
  validates :repeat_count, numericality: { only_integer: true, in: 1..400 }, allow_nil: true
  validates :starts_at, :ends_at, presence: true
  validate :duration_within_limits
  validate :recurrence_within_limits
  validate :agent_consistent

  # Spec 010, R1: runs start only for occurrences after the agent was assigned.
  before_save { self.agent_assigned_at = (agent_id ? Time.current : nil) if agent_id_changed? }

  scope :visible_to, ->(user) { where(calendar: "system").or(where(calendar: "private", user_id: user.id)) }

  def system? = calendar == "system"

  def recurring? = repeat != "none"

  def duration = ends_at - starts_at

  def weekdays = repeat_weekdays.to_s.split(",").map(&:to_i).select { |d| d.between?(1, 7) }.uniq.sort

  def weekdays=(days)
    self.repeat_weekdays = Array(days).map(&:to_i).select { |d| d.between?(1, 7) }.uniq.sort.join(",").presence
  end

  def visible_to?(user) = system? || user_id == user.id

  # Q2a: private tasks belong to their author; system-wide tasks are changed only by admins.
  def editable_by?(user) = system? ? user.admin? : user_id == user.id

  # All occurrences visible to `user` that overlap `range`, ordered by start.
  def self.occurrences_for(user, range)
    reach = SERIES_LIMIT + MAX_DURATION
    visible_to(user)
      .where(starts_at: (range.begin - reach)...range.end)
      .includes(:exceptions, agent: :executor)
      .flat_map { |task| task.occurrences(range) }
      .sort_by { |o| [ o.starts_at, -o.duration, o.task.id ] }
  end

  def occurrences(range)
    occurrence_starts.filter_map do |start|
      finish = start + duration
      Occurrence.new(task: self, starts_at: start, ends_at: finish, original_start: start) if start < range.end && finish > range.begin
    end
  end

  def occurrence_at(original_start)
    start = occurrence_starts.find { |s| s.to_i == original_start.to_i } or return nil
    Occurrence.new(task: self, starts_at: start, ends_at: start + duration, original_start: start)
  end

  # Original starts of every occurrence: the series without its exceptions, never beyond SERIES_LIMIT.
  def occurrence_starts
    skipped = exceptions.map { |e| e.occurs_at.to_i }.to_set
    series_starts.reject { |s| skipped.include?(s.to_i) }
  end

  def series_starts
    return [ starts_at.in_time_zone ] unless recurring?

    first = starts_at.in_time_zone
    limit = first + SERIES_LIMIT
    last = repeat_until && Time.zone.local(repeat_until.year, repeat_until.month, repeat_until.day).end_of_day
    starts = []
    each_candidate(first) do |start|
      break if start > limit || (last && start > last) || (repeat_count && starts.size >= repeat_count)

      starts << start
    end
    starts
  end

  private

  def each_candidate(first)
    case repeat
    when "daily"
      (0..).each { |i| yield first + (i * repeat_interval).days }
    when "weekly"
      days = weekdays.presence || [ first.to_date.cwday ]
      monday = first.beginning_of_week(:monday)
      (0..).each do |week|
        base = monday + (week * repeat_interval).weeks
        days.each do |day|
          start = (base + (day - 1).days).change(hour: first.hour, min: first.min, sec: first.sec)
          yield start unless start < first
        end
      end
    when "monthly"
      (0..).each do |i|
        month = first.advance(months: i * repeat_interval)
        if month.day == first.day
          yield month
        elsif month.to_date.beginning_of_month > first.to_date.advance(months: SERIES_LIMIT.in_months.to_i + 1)
          yield month # past every limit: let the caller stop
        end
      end
    end
  end

  def duration_within_limits
    return if starts_at.blank? || ends_at.blank?
    return errors.add(:ends_at, "must be after the start") if ends_at <= starts_at

    if all_day
      local_start, local_end = starts_at.in_time_zone, ends_at.in_time_zone
      days = (local_end.to_date - local_start.to_date).to_i
      unless local_start == local_start.beginning_of_day && local_end == local_end.beginning_of_day
        errors.add(:base, "An all-day task starts and ends at midnight")
      end
      errors.add(:base, "An all-day task lasts 1 to #{MAX_ALL_DAY_DAYS} days") unless days.between?(1, MAX_ALL_DAY_DAYS)
    else
      errors.add(:base, "A task lasts at least 1 minute") if duration < MIN_DURATION
      errors.add(:base, "A task lasts at most 4 days") if duration > MAX_DURATION
    end
  end

  def recurrence_within_limits
    return unless recurring? && starts_at.present?

    errors.add(:base, "Choose when the series ends: a date or a number of times") if repeat_until.blank? && repeat_count.blank?
    first = starts_at.in_time_zone
    if repeat_until && repeat_until > (first + SERIES_LIMIT).to_date
      errors.add(:repeat_until, "must be within 3 months of the first occurrence")
    end
    if repeat_until && repeat_until < first.to_date
      errors.add(:repeat_until, "must not be before the first occurrence")
    end
    if repeat_count && series_starts.size < repeat_count
      errors.add(:repeat_count, "would run past 3 months — a series lasts at most a quarter")
    end
  end

  # Spec 009, R4: a private agent belongs to the task's author and only on a private task.
  def agent_consistent
    errors.add(:agent, "is not available: choose an enabled agent you may use") if agent_refused
    return unless agent
    return if agent.shared?

    errors.add(:agent, "is private to another user") if agent.user_id != user_id
    errors.add(:agent, "must be a shared agent on a system-wide task") if system?
  end
end
