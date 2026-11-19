# Spec 002, R4/R5: setting up an authenticator (Google Authenticator) when the account requires TOTP.
# The secret is kept in the encrypted Rails session until one valid code confirms it.
class TwoFactorEnrollmentsController < ApplicationController
  layout "auth" # spec 006: centered sign-in card, no navigation
  skip_before_action :require_authentication
  before_action :require_password_step
  before_action -> { redirect_to new_two_factor_path if current_user.otp_enrolled? }

  def new
    @secret = session[:pending_otp_secret] ||= current_user.generate_otp_secret
    @qr_svg = RQRCode::QRCode.new(current_user.otp_provisioning_uri(@secret)).as_svg(module_size: 4, use_path: true, viewbox: true)
  end

  def create
    secret = session[:pending_otp_secret]
    if secret && current_user.enroll_otp!(secret, params[:code])
      session.delete(:pending_otp_secret)
      Current.session.update!(otp_verified: true)
      redirect_to after_authentication_url, notice: "Authenticator set up."
    else
      redirect_to new_two_factor_enrollment_path, alert: "Invalid code. Scan the QR code again and enter the current code."
    end
  end
end
