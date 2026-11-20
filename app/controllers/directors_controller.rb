# Spec 011, G1: the user's chat with their director — the only agent the user talks to (Q7).
# Spec 015: a new conversation archives the current one; the archive is read-only.
class DirectorsController < ApplicationController
  rate_limit to: 20, within: 10.minutes, only: :verify, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { respond_to { |f| f.json { render json: { ok: false, error: "Too many checks. Try again in a few minutes." }, status: :too_many_requests }; f.any { redirect_to director_path, alert: "Too many checks. Try again in a few minutes." } } }
  def show
    @director = current_user.director_role&.agent
    @messages = current_user.chat_messages.current.ordered.last(100)
    @writing = writing?
  end

  # Spec 019, G2/R2: ask the verifier to check the conversation; refused without a verifier or while someone writes.
  def verify
    run = ManagementRunner.verify!(current_user)
    error = current_user.verifier_role ? "Wait until the current answer is finished." : "Choose a verifier on the Team page first."
    respond_to do |format|
      format.json { run ? render(json: { ok: true, writing: true }) : render(json: { ok: false, error: error }, status: :unprocessable_content) }
      format.any { run ? redirect_back_or_to(director_path) : redirect_back_or_to(director_path, alert: error) }
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

  def writing? = TaskRun.where(user: current_user, purpose: %w[chat verify], state: %w[queued running]).exists?
end
