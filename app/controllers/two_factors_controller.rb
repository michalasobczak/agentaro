# Spec 002, G2: the TOTP step after the password, for accounts with an enrolled authenticator.
class TwoFactorsController < ApplicationController
  layout "auth" # spec 006: centered sign-in card, no navigation
  skip_before_action :require_authentication
  before_action :require_password_step
  before_action -> { redirect_to new_two_factor_enrollment_path unless current_user.otp_enrolled? }
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
             with: -> { redirect_to new_two_factor_path, alert: "Too many attempts. Try again in a few minutes." }

  def new
  end

  def create
    user = current_user
    if user.verify_otp(params[:code])
      Current.session.update!(otp_verified: true)
      redirect_to after_authentication_url
    else
      throttle = SignInThrottle.for(user.username)
      throttle.register_failure!
      return sign_out_locked if throttle.locked?

      flash.now[:alert] = "Invalid code."
      render :new, status: :unprocessable_content
    end
  end

  private

  def sign_out_locked
    terminate_session
    redirect_to new_session_path, alert: SessionsController::INVALID
  end
end
