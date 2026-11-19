# Spec 007: layout of tasks in the calendar views.
module CalendarHelper
  ROW_MINUTES = 5
  ROWS = 24 * 60 / ROW_MINUTES # 288
  SUB_COLUMNS = 60
  MAX_LANES = 6

  # The part of an occurrence that falls on one day of the time grid.
  Segment = Data.define(:occurrence, :starts_at, :ends_at, :continues_before, :continues_after, :lane, :lanes) do
    def row = (starts_at.hour * 60 + starts_at.min) / ROW_MINUTES

    def span
      finish = continues_after ? 24 * 60 : ends_at.hour * 60 + ends_at.min + (ends_at.sec.positive? ? 1 : 0)
      [ ((finish - (starts_at.hour * 60 + starts_at.min)) / ROW_MINUTES.to_f).ceil, 1 ].max.clamp(1, ROWS - row)
    end

    def placement_classes
      count = [ lanes, MAX_LANES ].min
      width = SUB_COLUMNS / count
      size = span <= 3 ? "tiny" : (span <= 6 ? "short" : nil) # under 15 / 30 minutes: one line
      [ "r#{row} h#{span} c#{(lane % count) * width + 1} w#{width}", size ].compact.join(" ")
    end
  end

  def day_start(day) = Time.zone.local(day.year, day.month, day.day)

  def timed_segments(day, occurrences)
    from, to = day_start(day), day_start(day) + 1.day
    parts = occurrences.reject(&:all_day?).select { |o| o.starts_at < to && o.ends_at > from }.map do |o|
      { occurrence: o, starts_at: [ o.starts_at, from ].max.in_time_zone, ends_at: [ o.ends_at, to ].min.in_time_zone,
        continues_before: o.starts_at < from, continues_after: o.ends_at > to }
    end
    assign_lanes(parts.sort_by { |p| [ p[:starts_at], p[:starts_at] - p[:ends_at] ] })
  end

  def all_day_occurrences(day, occurrences)
    from, to = day_start(day), day_start(day) + 1.day
    occurrences.select { |o| o.all_day? && o.starts_at < to && o.ends_at > from }
  end

  # Everything touching a day, for the month view: all-day first, then by start.
  def day_occurrences(day, occurrences)
    from, to = day_start(day), day_start(day) + 1.day
    occurrences.select { |o| o.starts_at < to && o.ends_at > from }.sort_by { |o| [ o.all_day? ? 0 : 1, o.starts_at ] }
  end

  def task_time_label(occurrence)
    return "All day" if occurrence.all_day?

    from, to = occurrence.starts_at.in_time_zone, occurrence.ends_at.in_time_zone
    same_day = from.to_date == to.to_date
    "#{l(from, format: "%H:%M")}–#{same_day ? l(to, format: "%H:%M") : l(to, format: "%a %H:%M")}"
  end

  def calendar_title(view, days)
    first, last = days.first, days.last
    case view
    when "day" then l(first, format: "%A, %-d %B %Y")
    when "month" then l(days[days.size / 2], format: "%B %Y")
    else
      first.month == last.month ? "#{first.day}–#{l(last, format: "%-d %B %Y")}" : "#{l(first, format: "%-d %b")} – #{l(last, format: "%-d %b %Y")}"
    end
  end

  # Data attributes the calendar script reads (spec 007, G6). Times are wall-clock in the app time zone.
  def task_data(occurrence)
    task = occurrence.task
    { id: task.id, occurrence: occurrence.original_start.iso8601,
      start: occurrence.starts_at.in_time_zone.strftime("%Y-%m-%dT%H:%M"), end: occurrence.ends_at.in_time_zone.strftime("%Y-%m-%dT%H:%M"),
      recurring: task.recurring?, all_day: task.all_day?,
      editable: task.editable_by?(current_user), title: task.title }
  end

  def task_path_for(occurrence, return_to)
    task = occurrence.task
    params = { return_to: return_to }
    params[:occurrence] = occurrence.original_start.iso8601 if task.recurring?
    task.editable_by?(current_user) ? edit_task_path(task, params) : task_path(task, params)
  end

  def task_classes(occurrence, *extra)
    task = occurrence.task
    [ "task", "t-#{task.calendar}", ("is-recurring" if task.recurring?), ("is-readonly" unless task.editable_by?(current_user)), *extra ].compact.join(" ")
  end

  private

  # Overlapping tasks share the width side by side; a cluster ends when nothing overlaps any more.
  def assign_lanes(parts)
    segments, cluster, lane_ends, cluster_end = [], [], [], nil
    flush = lambda do
      lanes = lane_ends.size
      cluster.each { |p| segments << Segment.new(**p.merge(lanes: [ lanes, 1 ].max)) }
      cluster.clear
      lane_ends.clear
    end
    parts.each do |part|
      flush.call if cluster_end && part[:starts_at] >= cluster_end
      lane = lane_ends.index { |finish| finish <= part[:starts_at] } || lane_ends.size
      lane_ends[lane] = part[:ends_at]
      cluster << part.merge(lane: lane)
      cluster_end = [ cluster_end, part[:ends_at] ].compact.max
      cluster_end = part[:ends_at] if cluster.size == 1
    end
    flush.call
    segments
  end

  # Spec 009: agents offered in the task form — my private and shared ones for a private task, shared only for a
  # system-wide task (admins see both groups); the current agent stays listed, marked when no longer available.
  def agent_options_for(task)
    calendars = current_user.admin? ? %w[private system] : %w[private]
    agents = calendars.flat_map { |c| Agent.assignable(current_user, c).includes(:executor).to_a }.uniq.sort_by { |a| a.name.downcase }
    agents << task.agent if task.agent && !agents.include?(task.agent)
    agents.map { |a| [ "#{a.name}#{" (shared)" if a.shared?}#{" — not available" unless a.usable?}", a.id ] }
  end

  def agent_label(task) = task.agent && "#{task.agent.name}#{" (not available)" unless task.agent.usable?}"
end
