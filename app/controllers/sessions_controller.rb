# Spec 002: sign-in (password step) and sign-out.
class SessionsController < ApplicationController
  INVALID = "Invalid username or password." # same message for every failure (S6)

  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
             with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if signed_in?
  end

  def create
    user = User.authenticate(params[:username], params[:password])
    unless user
      flash.now[:alert] = INVALID
      return render :new, status: :unprocessable_content
    end

    start_new_session_for(user)
    if !user.otp_required?
      redirect_to after_authentication_url
    elsif user.otp_enrolled?
      redirect_to new_two_factor_path
    else
      redirect_to new_two_factor_enrollment_path
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "Signed out."
  end
end
