# Spec 007, G5/G6: creating and changing tasks — through forms and, as JSON, from the calendar script.
class TasksController < ApplicationController
  before_action :set_task, except: %i[new create]

  # S5: other users' private tasks do not exist; the calendar script gets a JSON answer.
  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.json { render json: { ok: false, errors: [ "Task not found." ] }, status: :not_found }
      format.any { head :not_found }
    end
  end
  before_action :require_editable, except: %i[new create show]

  def new
    start = parse_time(params[:starts_at]) || (Time.zone.now + 1.hour).beginning_of_hour
    finish = parse_time(params[:ends_at]) || start + 1.hour
    @task = Task.new(starts_at: start, ends_at: finish, calendar: "private", repeat_interval: 1)
    @return_to = return_path
  end

  def create
    @task = current_user.tasks.new(task_attributes)
    @task.calendar = "private" unless current_user.admin?
    @return_to = return_path
    saved = @task.save
    respond_to do |format|
      # The new-task popup on the calendar sends the form as JSON and shows errors in place.
      format.json do
        if saved
          render json: { ok: true, id: @task.id }
        else
          render json: { ok: false, errors: @task.errors.full_messages }, status: :unprocessable_content
        end
      end
      format.any do
        if saved
          redirect_to calendar_return(@task.starts_at), notice: "Task created."
        else
          render :new, status: :unprocessable_content
        end
      end
    end
  end

  def show
    @occurrence = occurrence
    @return_to = return_path
    redirect_to edit_task_path(@task, occurrence: params[:occurrence], return_to: @return_to) if @task.editable_by?(current_user)
  end

  def edit
    @occurrence = occurrence
    @return_to = return_path
    shown = @occurrence || @task
    @task.starts_at, @task.ends_at = shown.starts_at, shown.ends_at
  end

  def update
    attrs = task_attributes
    attrs.delete(:calendar) unless current_user.admin?
    result = editor.update(attrs, scope: params[:scope])
    respond(result, notice: "Task saved.") do
      @occurrence = occurrence
      @return_to = return_path
      @errors = result.errors
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    result = editor.destroy(scope: params[:scope])
    respond(result, notice: "Task deleted.")
  end

  # JSON from the calendar script: drag & drop and resize.
  def move
    result = editor.move(starts_at: parse_time(params[:starts_at]), ends_at: parse_time(params[:ends_at]), scope: params[:scope])
    respond(result, notice: "Task moved.")
  end

  # Paste of a copied task: a one-time copy at the chosen time.
  def copy
    result = editor.copy(starts_at: parse_time(params[:starts_at]) || @task.starts_at, calendar: target_calendar)
    respond(result, notice: "Task pasted.")
  end

  # Q6: a copy at the same time on the next day.
  def duplicate
    result = editor.duplicate(calendar: target_calendar)
    respond(result, notice: "Task duplicated.")
  end

  private

  # S5: private tasks of other users do not exist for this user (404).
  def set_task
    @task = Task.visible_to(current_user).find(params[:id])
  end

  # Q2a: system-wide tasks are changed only by admins.
  def require_editable
    return if @task.editable_by?(current_user)

    respond_to do |format|
      format.json { render json: { ok: false, errors: [ "Only admins can change system-wide tasks." ] }, status: :forbidden }
      format.any { render "shared/forbidden", status: :forbidden, locals: { reason: "Only admins can change system-wide tasks." } }
    end
  end

  def editor = TaskEditor.new(@task, occurrence_start: parse_time(params[:occurrence]))

  def occurrence = @task.recurring? ? @task.occurrence_at(parse_time(params[:occurrence]) || @task.starts_at) : nil

  def target_calendar = @task.system? && current_user.admin? ? "system" : "private"

  def respond(result, notice:, &failure)
    respond_to do |format|
      format.json do
        if result.ok
          render json: { ok: true, id: result.task.id }
        else
          render json: { ok: false, errors: result.errors }, status: :unprocessable_content
        end
      end
      format.any do
        if result.ok
          redirect_to calendar_return(result.task.starts_at || Time.zone.now), notice: notice
        elsif failure
          failure.call
        else
          redirect_to calendar_return(@task.starts_at), alert: result.errors.to_sentence
        end
      end
    end
  end

  # Form fields are local date and time (Europe/Warsaw); all-day tasks use an inclusive end date.
  def task_attributes
    p = params.fetch(:task, {}).permit(:title, :location, :description, :calendar, :all_day, :start_date, :start_time,
                                       :end_date, :end_time, :repeat, :repeat_interval, :repeat_ends, :repeat_until,
                                       :repeat_count, :agent_id, weekdays: [])
    all_day = p[:all_day] == "1"
    starts = local_time(p[:start_date], all_day ? "00:00" : p[:start_time])
    ends = all_day ? local_time(p[:end_date], "00:00")&.+(1.day) : local_time(p[:end_date], p[:end_time])
    attrs = { title: p[:title], location: p[:location], description: p[:description], all_day: all_day,
              starts_at: starts, ends_at: ends, repeat: (Task::REPEATS.include?(p[:repeat]) ? p[:repeat] : "none"),
              repeat_interval: p[:repeat_interval].presence || 1, weekdays: p[:weekdays] }
    attrs[:calendar] = p[:calendar] if Task::CALENDARS.include?(p[:calendar])
    attrs[:repeat_until] = p[:repeat_ends] == "count" ? nil : (Date.iso8601(p[:repeat_until]) rescue nil)
    attrs[:repeat_count] = p[:repeat_ends] == "count" ? p[:repeat_count].presence : nil
    agent_attributes(p, attrs)
  end

  # Spec 009, R3: a newly chosen agent must be one the user may assign to this kind of task; keeping the
  # current agent is always allowed (so a task stays editable after its agent is disabled).
  def agent_attributes(p, attrs)
    return attrs unless p.key?(:agent_id)

    requested = p[:agent_id].presence&.to_i
    return attrs.merge(agent_id: nil) if requested.nil?
    return attrs.merge(agent_id: requested) if @task&.persisted? && requested == @task.agent_id

    calendar = current_user.admin? ? (attrs[:calendar] || @task&.calendar || "private") : "private"
    agent = Agent.assignable(current_user, calendar).find_by(id: requested)
    agent ? attrs.merge(agent_id: agent.id) : attrs.merge(agent_refused: true)
  end

  def local_time(date, time)
    return nil if date.blank? || time.blank?

    Time.zone.parse("#{date} #{time}")
  rescue ArgumentError
    nil
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # Only calendar paths are accepted as a place to return to (no open redirects).
  def return_path
    path = params[:return_to].to_s
    path.start_with?("/calendar") && !path.start_with?("//") ? path : nil
  end

  def calendar_return(time)
    return_path || calendar_path(date: time.in_time_zone.to_date.iso8601)
  end
end
