# Spec 039, G2: how much the director writes, for the signed-in account only.
class Account::ReplyLengthsController < ApplicationController
  def update
    level = params[:level].to_s.to_i
    return redirect_back_or_to(director_path, alert: "Unknown reply length.") unless ReplyLength.valid?(level)

    current_user.update!(reply_length: level)
    redirect_back_or_to director_path, notice: "Reply length: #{ReplyLength.name(level)}."
  end
end
