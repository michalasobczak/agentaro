# Spec 007, G1/G2: the calendar — day, 4 days, week (Mon–Sun) and month views.
class CalendarController < ApplicationController
  VIEWS = %w[day 4days week month].freeze
  DEPTHS = %w[epics steps].freeze # spec 013, G9: epics only, or epics and agents' steps

  def show
    @view = VIEWS.include?(params[:view]) ? params[:view] : (session[:calendar_view] || "week")
    session[:calendar_view] = @view
    @date = parse_date(params[:date]) || Time.zone.today
    @days = days_for(@view, @date)
    from = Time.zone.local(@days.first.year, @days.first.month, @days.first.day)
    to = Time.zone.local(@days.last.year, @days.last.month, @days.last.day) + 1.day
    range = from...to
    @depth = DEPTHS.include?(params[:depth]) ? params[:depth] : (session[:calendar_depth] || "epics")
    session[:calendar_depth] = @depth
    @occurrences = Task.occurrences_for(current_user, range)
    @occurrences = @occurrences.reject { |o| o.task.work_item_id } if @depth == "epics" # agents' steps hidden
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

  # Spec 013, G9: the user's epics whose steps fall in the range, each spanning its first step to its last.
  Epic = Data.define(:item, :starts_at, :ends_at)

  def epics_in(range)
    current_user.work_items.where.not(state: "cancelled").includes(:space, :tasks).where(id: Task.select(:work_item_id).where.not(work_item_id: nil)).filter_map do |item|
      span = item.span
      Epic.new(item: item, starts_at: span.begin, ends_at: span.end) if span && span.begin < range.end && span.end > range.begin
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
