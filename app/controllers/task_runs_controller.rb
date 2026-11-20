# Spec 010: runs of a task. Visible to whoever may see the task (S4); "Run now" (G7) only on tasks the user may change.
class TaskRunsController < ApplicationController
  rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
  # Security analysis, F13: every run uses a subscription or the host's resources, so manual runs are limited per user.
  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { redirect_back fallback_location: calendar_path, alert: "Too many runs started by hand. Try again in a few minutes." }

  def show
    @run = TaskRun.visible_to(current_user).find(params[:id])
    @task = @run.task
  end

  def create
    task = Task.visible_to(current_user).find(params[:task_id])
    unless task.editable_by?(current_user)
      return render "shared/forbidden", status: :forbidden, locals: { reason: "Only admins run system-wide tasks." }
    end
    return redirect_to edit_task_path(task), alert: "Assign an agent to this task first." unless task.agent

    occurrence = (task.occurrence_at(parse_time(params[:occurrence])) if params[:occurrence].present?) || task.occurrence_at(task.starts_at)
    run = TaskRun.create!(task: task, occurrence_start: occurrence&.original_start || task.starts_at, trigger: "manual", requested_by: Current.actor_label)
    Agentaro::TaskScheduler.enqueue(run.id)
    redirect_to task_run_path(run), notice: "Run queued — #{task.agent.name} will start it shortly."
  end

  private

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
