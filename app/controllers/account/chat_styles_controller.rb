# Spec 041, G3: how the director talks, for the signed-in account only.
class Account::ChatStylesController < ApplicationController
  def update
    level = params[:level].to_s.to_i
    return redirect_back_or_to(director_path, alert: "Unknown conversation style.") unless ChatStyle.valid?(level)

    current_user.update!(chat_style: level)
    redirect_back_or_to director_path, notice: "Style: #{ChatStyle.name(level)}."
  end
end
