# Spec 002: every page requires a signed-in user unless a controller opts out.
#
# A session is created after the password step. When the account requires TOTP, the session gives
# no access until a code is verified (or, for a new authenticator, enrolled). Sessions end 7 days
# after sign-in (Session::LIFETIME) and are stored in the database, so they can be revoked.
module Authentication
  extend ActiveSupport::Concern

  LAST_SEEN_INTERVAL = 10.minutes

  included do
    before_action :require_authentication
    helper_method :current_user, :signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def current_user = Current.user

  def signed_in? = resume_session&.authenticated? || false

  def require_authentication
    session_record = resume_session
    if session_record.nil?
      request_authentication
    elsif !session_record.authenticated?
      redirect_to session_record.user.otp_enrolled? ? new_two_factor_path : new_two_factor_enrollment_path
    end
  end

  # Signed in with a password, but TOTP still pending (used by the TOTP pages).
  def require_password_step
    session_record = resume_session
    if session_record.nil?
      request_authentication
    elsif session_record.authenticated?
      redirect_to after_authentication_url
    end
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    id = cookies.signed[:session_id] or return nil
    record = Session.includes(:user).find_by(id: id)
    if record.nil? || record.expired? || !record.user.active?
      record&.destroy
      cookies.delete(:session_id)
      return nil
    end
    remember_for_audit(record)
    record.update!(last_seen_at: Time.current) if record.last_seen_at.nil? || record.last_seen_at < LAST_SEEN_INTERVAL.ago
    record
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url if request.get?
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(user)
    return_to = session[:return_to_after_authenticating]
    reset_session # new Rails session id: no session fixation (R7)
    session[:return_to_after_authenticating] = return_to if return_to
    Session.expired.find_each(&:destroy) # browsers drop expired cookies; remove the rows too (S4)
    Current.actor = "user:#{user.id}:#{user.username}" # the session row is created by the person signing in
    record = user.sessions.create!(user_agent: request.user_agent.to_s[0, 500], ip_address: request.remote_ip)
    Current.session = record
    remember_for_audit(record)
    cookies.signed[:session_id] = {
      value: record.id, expires: record.expires_at, httponly: true, same_site: :lax,
      secure: request.ssl? || Rails.env.production?
    }
    record
  end

  # The audit log (spec 003) reads these after the response, even if the session was deleted meanwhile.
  def remember_for_audit(record)
    request.env["agentaro.session_id"] = record.id
    request.env["agentaro.user_id"] = record.user_id
    request.env["agentaro.username"] = record.user.username
  end

  def terminate_session
    Current.session&.destroy
    Current.session = nil
    cookies.delete(:session_id)
    reset_session
  end

  def require_admin
    render "shared/forbidden", status: :forbidden unless current_user&.admin?
  end
end
