# Spec 011, G1: the user's chat with their director — the only agent the user talks to (Q7).
class DirectorsController < ApplicationController
  def show
    @director = current_user.director_role&.agent
    @messages = current_user.chat_messages.ordered.last(100)
    @writing = TaskRun.where(user: current_user, purpose: "chat", state: %w[queued running]).exists?
  end

  # Auto refresh of the chat, list and item pages.
  def stamp
    render json: { stamp: ChangeStamp.management(current_user) }
  end
end
