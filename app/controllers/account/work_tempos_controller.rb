# Spec 041, G4: the owner's default tempo, for the signed-in account only (a space's own tempo is on its form, G5).
class Account::WorkTemposController < ApplicationController
  def update
    level = params[:level].to_s.to_i
    return redirect_back_or_to(director_path, alert: "Unknown tempo.") unless WorkTempo.valid?(level)

    current_user.update!(work_tempo: level)
    redirect_back_or_to director_path, notice: "Tempo: #{WorkTempo.name(level)}."
  end
end
