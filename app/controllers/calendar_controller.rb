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
    @previous, @next = step(@view, @date, -1), step(@view, @date, 1)
  end

  private

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
