# Spec 011, G1: the user's chat with their director — the only agent the user talks to (Q7).
# Spec 015: a new conversation archives the current one; the archive is read-only.
class DirectorsController < ApplicationController
  rate_limit to: 20, within: 10.minutes, only: :verify, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { respond_to { |f| f.json { render json: { ok: false, error: "Too many checks. Try again in a few minutes." }, status: :too_many_requests }; f.any { redirect_to director_path, alert: "Too many checks. Try again in a few minutes." } } }
  def show
    @director = current_user.director_role&.agent
    @messages = current_user.chat_messages.current.ordered.last(100)
    @writing = writing?
    @work = WorkPanel.for(current_user)
  end

  # Spec 027: the panel beside the chat, polled by work_panel.js.
  def work
    render json: WorkPanel.for(current_user)
  end

  # Spec 038: one step of the owner's own epic (?step=id), or the step to follow of an epic (?epic=id). Only steps of
  # the current plan (R1); anything else is not found.
  def live
    if params[:epic].present?
      item = current_user.work_items.find(params[:epic])
      step = StepView.step_for(item) or raise ActiveRecord::RecordNotFound
    else
      step = EpicStep.joins(:work_item).where(work_items: { user_id: current_user.id }).find(params[:step])
      raise ActiveRecord::RecordNotFound unless step.position >= step.work_item.active_step_from.to_i
    end
    render json: StepView.new(step).to_h.merge(following: params[:epic].present?)
  end

  # Spec 019, owner fix ("jak zapraszam weryfikatora, to ma on być do odwołania aktywny"): the button invites the
  # verifier — it checks the conversation now and every answer of the director after — or sends it away again.
  def verify
    return respond_verify(false, "Choose a verifier on the Team page first.") unless current_user.verifier_role

    current_user.update!(verifier_active: !current_user.verifier_active?)
    run = ManagementRunner.verify!(current_user) if current_user.verifier_active?
    respond_verify(true, nil, writing: run.present?)
  end

  # Owner fix: how fast the voices speak (1x to 2x).
  def speech_speed
    current_user.update(speech_speed: params[:speed].to_f) if User::SPEECH_SPEEDS.include?(params[:speed].to_f)
    respond_to do |format|
      format.json { render json: { speed: current_user.speech_speed.to_f } }
      format.any { redirect_back_or_to director_path }
    end
  end

  # Auto refresh of the chat, list and item pages.
  def stamp
    render json: { stamp: ChangeStamp.management(current_user) }
  end

  # Spec 015, G1/G5: every message of the current conversation gets the same archived_at (one changelog entry
  # each, R2). Refused while the director is writing, so its answer cannot land in the new conversation.
  def new_conversation
    return redirect_back_or_to(director_path, alert: "The director is writing an answer. Start a new conversation when it has answered.") if writing?

    now = Time.current
    messages = current_user.chat_messages.current
    count = messages.count
    ChatMessage.transaction { messages.find_each { |message| message.update!(archived_at: now) } }
    redirect_back_or_to director_path, notice: count.zero? ? "This conversation is already empty." : "New conversation. The previous one (#{count} messages) is in the archive."
  end

  # Spec 015, G4: earlier conversations, newest first.
  def archive
    @director = current_user.director_role&.agent
    @conversations = current_user.chat_messages.archived.ordered.group_by(&:archived_at).sort_by { |at, _| -at.to_f }
  end

  private

  def respond_verify(ok, error, writing: false)
    respond_to do |format|
      format.json { ok ? render(json: { ok: true, active: current_user.verifier_active?, writing: writing }) : render(json: { ok: false, error: error }, status: :unprocessable_content) }
      format.any { ok ? redirect_back_or_to(director_path) : redirect_back_or_to(director_path, alert: error) }
    end
  end

  def writing? = TaskRun.where(user: current_user, purpose: %w[chat verify], state: %w[queued running]).exists?
end
