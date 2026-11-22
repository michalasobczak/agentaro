# Spec 046, G1: how the conversation flows (Zwykła / Naturalna), for the signed-in account only.
class Account::ConversationModesController < ApplicationController
  def update
    level = params[:level].to_s.to_i
    return redirect_back_or_to(director_path, alert: "Unknown conversation mode.") unless ConversationMode.valid?(level)

    current_user.update!(conversation_mode: level)
    redirect_back_or_to director_path, notice: "Conversation: #{ConversationMode.name(level)}."
  end
end
