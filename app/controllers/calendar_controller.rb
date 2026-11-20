# Spec 007, G1/G2: the calendar — day, 4 days, week (Mon–Sun) and month views.
class CalendarController < ApplicationController
  VIEWS = %w[day 4days week month].freeze

  def show
    @view = VIEWS.include?(params[:view]) ? params[:view] : (session[:calendar_view] || "week")
    session[:calendar_view] = @view
    @date = parse_date(params[:date]) || Time.zone.today
    @days = days_for(@view, @date)
    from = Time.zone.local(@days.first.year, @days.first.month, @days.first.day)
    to = Time.zone.local(@days.last.year, @days.last.month, @days.last.day) + 1.day
    range = from...to
    @occurrences = Task.occurrences_for(current_user, range)
    @epics = epics_in(range)
    # Spec 010, G6: latest run state per occurrence, for the marks on the calendar.
    @run_states = TaskRun.where(task_id: @occurrences.map { |o| o.task.id }.uniq, occurrence_start: (range.begin - Task::MAX_DURATION)...range.end)
                         .order(:id).pluck(:task_id, :occurrence_start, :state)
                         .each_with_object(Hash.new { |h, k| h[k] = {} }) { |(id, start, state), h| h[id][start.to_i] = state }
    @previous, @next = step(@view, @date, -1), step(@view, @date, 1)
  end

  # Auto refresh: the calendar asks every 20 seconds whether anything it shows has changed.
  def stamp
    render json: { stamp: ChangeStamp.calendar(current_user) }
  end

  private

  # Spec 016, G8: the user's epics in the range, each from its start to its end (spec 013 epics: their steps).
  # They are laid out in the time grid like tasks, so all_day? is false.
  Epic = Data.define(:item, :starts_at, :ends_at) do
    def all_day? = false
  end

  def epics_in(range)
    now = Time.current
    current_user.work_items.includes(:space, :tasks).where("started_at IS NOT NULL OR (state = 'planned' AND starts_at IS NOT NULL) OR id IN (?)",
                                                          Task.where.not(work_item_id: nil).select(:work_item_id)).filter_map do |item|
      span = item.span(now) or next
      Epic.new(item: item, starts_at: span.begin, ends_at: span.end) if span.begin < range.end && span.end > range.begin
    end.sort_by(&:starts_at)
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def days_for(view, date)
    case view
    when "day" then [ date ]
    when "4days" then (date..date + 3).to_a
    when "week" then (date.beginning_of_week(:monday)..date.end_of_week(:monday)).to_a
    when "month" then (date.beginning_of_month.beginning_of_week(:monday)..date.end_of_month.end_of_week(:monday)).to_a
    end
  end

  def step(view, date, direction)
    case view
    when "day" then date + direction
    when "4days" then date + 4 * direction
    when "week" then date + 7 * direction
    when "month" then date.advance(months: direction)
    end
  end
end
