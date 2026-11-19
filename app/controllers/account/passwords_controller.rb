# Spec 002, G8: regular users change their own password. Admin passwords change only on the command line.
class Account::PasswordsController < ApplicationController
  before_action -> { render "shared/forbidden", status: :forbidden, locals: { reason: "Admin passwords can be changed only from the command line." } if current_user.admin? }

  def edit
  end

  def update
    user = current_user
    unless user.authenticate_password(params[:current_password].to_s)
      flash.now[:alert] = "Current password is incorrect."
      return render :edit, status: :unprocessable_content
    end

    user.password = params[:password]
    user.password_confirmation = params[:password_confirmation]
    if user.password.present? && user.save
      terminate_session # all sessions were revoked by the password change (R7)
      redirect_to new_session_path, notice: "Password changed. Sign in again."
    else
      @errors = user.password.blank? ? [ "Password can't be blank" ] : user.errors.full_messages
      render :edit, status: :unprocessable_content
    end
  end
end
