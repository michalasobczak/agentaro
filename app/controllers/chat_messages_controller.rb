# Spec 011, G1: the user writes to the director; the director answers in a run (spec 010).
# The chat page talks JSON (owner fix: "chat niech będzie naprawdę chatem"); without the script the form
# posts normally and the page reloads.
class ChatMessagesController < ApplicationController
  # Every message starts a run on a subscription or the host, so writing is limited per user (like Run now, F13).
  rate_limit to: 20, within: 10.minutes, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { reject("Too many messages. Try again in a few minutes.", :too_many_requests) }

  # New messages after a given id, and whether the director is writing — polled by the chat page.
  def index
    after = params[:after].to_i
    messages = current_user.chat_messages.where("id > ?", after).ordered.limit(100)
    render json: { messages: messages.map { |m| helpers.chat_message_json(m) }, writing: director_writing? }
  end

  def create
    content = params.dig(:chat_message, :content).to_s.strip
    return reject("Choose a director on the Team page first.") unless current_user.director_role
    return reject("Write a message.") if content.empty?
    return reject("Messages are at most 5,000 characters.") if content.length > 5000

    message = current_user.chat_messages.create!(author: "user", content: content)
    ManagementRunner.chat!(current_user)
    respond_to do |format|
      format.json { render json: { ok: true, message: helpers.chat_message_json(message), writing: director_writing? } }
      format.any { redirect_to director_path }
    end
  end

  private

  def director_writing? = TaskRun.where(user: current_user, purpose: "chat", state: %w[queued running]).exists?

  def reject(error, status = :unprocessable_content)
    respond_to do |format|
      format.json { render json: { ok: false, error: error }, status: status }
      format.any { redirect_to director_path, alert: error }
    end
  end
end
