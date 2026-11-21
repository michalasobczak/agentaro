# Spec 033, G2: the owner's default autonomy level, for the signed-in account only.
class Account::AutonomiesController < ApplicationController
  def update
    level = params[:level].to_s.to_i
    return redirect_back_or_to(director_path, alert: "Unknown autonomy level.") unless Autonomy.valid?(level)

    current_user.update!(autonomy_level: level)
    redirect_back_or_to director_path, notice: "Autonomy: #{Autonomy.name(level)}."
  end
end
