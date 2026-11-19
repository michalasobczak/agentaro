# Spec 007: changes to tasks shared by the forms and by drag & drop (G5, G6, R4).
#
# For a recurring task the change applies either to one occurrence ("this") — the occurrence is
# skipped in the series and a one-time task takes its place — or to the whole series ("series"),
# which is shifted by the same calendar offset (days and time of day), weekdays included.
class TaskEditor
  Result = Data.define(:ok, :task, :errors)

  def initialize(task, occurrence_start: nil)
    @task = task
    @occurrence = task.recurring? && occurrence_start ? task.occurrence_at(occurrence_start) : nil
  end

  # attrs: title, location, description, starts_at, ends_at, all_day, repeat fields, calendar.
  def update(attrs, scope:)
    attrs = attrs.to_h.symbolize_keys
    return save(@task, attrs) unless @occurrence

    scope.to_s == "series" ? update_series(attrs) : detach(attrs)
  end

  def move(starts_at:, ends_at:, scope:)
    update({ starts_at: starts_at, ends_at: ends_at }, scope: scope)
  end

  def destroy(scope:)
    if @occurrence && scope.to_s != "series"
      @task.exceptions.create!(occurs_at: @occurrence.original_start)
      @task.reload
      @task.destroy! if @task.occurrence_starts.empty?
    else
      @task.destroy!
    end
    Result.new(ok: true, task: @task, errors: [])
  end

  # A one-time copy of this task (or of the chosen occurrence) starting at `starts_at`.
  def copy(starts_at:, calendar:)
    source_start = @occurrence&.starts_at || @task.starts_at
    starts_at = starts_at.in_time_zone
    copy = @task.dup
    copy.assign_attributes(starts_at: starts_at, ends_at: starts_at + @task.duration, calendar: calendar,
                           repeat: "none", repeat_until: nil, repeat_count: nil, repeat_weekdays: nil, repeat_interval: 1)
    copy.agent = nil if copy.agent && !copy.agent.usable? # spec 009, F11: a new task never gets an unusable agent
    copy.ends_at = end_for_all_day(copy, source_start) if copy.all_day
    save(copy, {})
  end

  # Q6: duplicate goes to the same time on the next day.
  def duplicate(calendar:)
    start = (@occurrence&.starts_at || @task.starts_at).in_time_zone
    copy(starts_at: start + 1.day, calendar: calendar)
  end

  private

  def save(record, attrs)
    record.assign_attributes(attrs)
    if record.save
      Result.new(ok: true, task: record, errors: [])
    else
      Result.new(ok: false, task: record, errors: record.errors.full_messages)
    end
  end

  # "This one only": skip the occurrence in the series and create a one-time task in its place.
  def detach(attrs)
    single = @task.dup
    single.assign_attributes(starts_at: @occurrence.starts_at, ends_at: @occurrence.ends_at,
                             repeat: "none", repeat_until: nil, repeat_count: nil, repeat_weekdays: nil, repeat_interval: 1)
    single.assign_attributes(attrs.except(:repeat, :repeat_until, :repeat_count, :repeat_interval, :weekdays, :repeat_weekdays))
    Task.transaction do
      unless single.save
        return Result.new(ok: false, task: single, errors: single.errors.full_messages)
      end
      @task.exceptions.create!(occurs_at: @occurrence.original_start)
    end
    Result.new(ok: true, task: single, errors: [])
  end

  # Whole series: move its start by the same calendar offset as the occurrence was moved.
  def update_series(attrs)
    original = @occurrence.original_start.in_time_zone
    new_start = (attrs[:starts_at] || original).in_time_zone
    new_end = (attrs[:ends_at] || (new_start + @occurrence.duration)).in_time_zone
    day_shift = (new_start.to_date - original.to_date).to_i
    time_shift = new_start.seconds_since_midnight - original.seconds_since_midnight

    first = @task.starts_at.in_time_zone
    series_start = first + day_shift.days + time_shift.seconds
    changes = attrs.except(:starts_at, :ends_at).merge(starts_at: series_start, ends_at: series_start + (new_end - new_start))
    changes[:weekdays] = @task.weekdays.map { |d| ((d - 1 + day_shift) % 7) + 1 } if @task.repeat == "weekly" && day_shift != 0 && !attrs.key?(:weekdays)
    changes[:repeat_until] = @task.repeat_until + day_shift if @task.repeat_until && day_shift != 0 && !attrs.key?(:repeat_until)

    Task.transaction do
      result = save(@task, changes)
      raise ActiveRecord::Rollback unless result.ok

      @task.exceptions.each { |e| e.update!(occurs_at: e.occurs_at.in_time_zone + day_shift.days + time_shift.seconds) } if day_shift != 0 || time_shift != 0
      return result
    end
    Result.new(ok: false, task: @task, errors: @task.errors.full_messages)
  end

  def end_for_all_day(copy, source_start)
    days = (@task.ends_at.in_time_zone.to_date - @task.starts_at.in_time_zone.to_date).to_i
    start = copy.starts_at.in_time_zone.beginning_of_day
    copy.starts_at = start
    start + days.days
  end
end
