# Spec 032, G5: automatic retries of failed steps, on or off for the signed-in account only.
class Account::AutoRetriesController < ApplicationController
  def update
    on = ActiveModel::Type::Boolean.new.cast(params[:auto_retry])
    current_user.update!(auto_retry: on == true)
    redirect_to team_path(anchor: "failed-steps"), notice: "Automatic retries #{current_user.auto_retry ? "on" : "off"}."
  end
end
