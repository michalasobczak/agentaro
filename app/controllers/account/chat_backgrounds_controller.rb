# Spec 029, R4: the chat background pattern, saved on the signed-in account only. Exact allowlist: a missing,
# non-string or unknown value is refused (422) and the stored choice stays.
class Account::ChatBackgroundsController < ApplicationController
  def update
    value = params[:chat_background]
    saved = value.is_a?(String) && User::CHAT_BACKGROUNDS.key?(value) && current_user.update(chat_background: value)
    respond_to do |format|
      format.json { render json: { chat_background: current_user.reload.shown_chat_background }, status: saved ? :ok : :unprocessable_entity }
      format.any do
        flash[:alert] = "Unknown chat background." unless saved
        redirect_back_or_to director_path
      end
    end
  end
end
