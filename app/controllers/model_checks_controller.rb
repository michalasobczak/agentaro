# Spec 022, G4/R3/R4: "Check model" — one short question to the model chosen in a form, answered as JSON.
#
# Who may check (R4): an agent's editor (its owner; admins for shared agents), anyone signed in for a new agent on an
# enabled executor, admins for an executor's default. The result is kept on the saved agent or executor.
class ModelChecksController < ApplicationController
  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { render json: { ok: false, output: "Too many checks. Try again in a few minutes." }, status: :too_many_requests }

  # Security analysis after spec 022 (F-022-1): a check holds a server thread for up to a minute and the server has
  # few threads, so only one check runs at a time; another one waits for the next try.
  RUNNING = Mutex.new

  def create
    return render(json: { ok: false, output: "Another check is running; try again in a moment." }, status: :conflict) unless RUNNING.try_lock

    begin
      check
    ensure
      RUNNING.unlock
    end
  end

  private

  def check
    record, executor = target
    return render(json: { ok: false, output: "Not allowed." }, status: :forbidden) unless executor

    model = params[:model].to_s.strip.presence || (record.is_a?(Agent) || record.nil? ? executor.default_model : nil)
    effort = params[:effort].to_s.strip.presence_in(executor.efforts) || (record.is_a?(Executor) ? nil : executor.effort)
    result = ModelCheck.new(executor, model: model, effort: effort).run
    if record
      record.assign_attributes(model_checked_at: Time.current, model_check_ok: result.ok, model_check_output: result.output)
      record.save!(validate: false) # the saved fields may be awaiting a fix (R1); only the check result changes
    end
    render json: { ok: result.ok, output: result.output }
  end

  # [record to keep the result on (or nil), executor to check on] — nil executor when not allowed.
  def target
    if params[:executor_target].present?
      return [ nil, nil ] unless current_user.admin?

      executor = Executor.find(params[:executor_target])
      [ executor, executor ]
    elsif params[:agent_id].present?
      agent = Agent.visible_to(current_user).find(params[:agent_id])
      return [ nil, nil ] unless agent.editable_by?(current_user)

      [ agent, chosen_executor(agent.executor_id) ]
    else
      [ nil, chosen_executor(nil) ]
    end
  end

  # The executor picked in the form: an enabled one, or the agent's current one.
  def chosen_executor(current_id)
    id = params[:executor_id].presence || current_id
    Executor.where(enabled: true).or(Executor.where(id: current_id)).find_by(id: id)
  end
end
