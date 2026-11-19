# Spec 002: a person who can sign in. Created only by admins (web) or on the command line (first admin).
class User < ApplicationRecord
  ROLES = %w[admin user].freeze
  USERNAME_FORMAT = /\A[a-z0-9._-]{3,32}\z/
  PASSWORD_MIN = 12
  PASSWORD_MAX_BYTES = 72 # bcrypt limit
  OTP_ISSUER = "Agentaro"

  has_secure_password validations: false
  encrypts :otp_secret

  has_many :sessions, dependent: :destroy
  has_many :password_links, dependent: :destroy
  has_many :tasks, dependent: :destroy # spec 007 (accounts are deactivated, not deleted)
  has_many :agents, dependent: :destroy # spec 009

  normalizes :username, with: ->(u) { u.to_s.strip.downcase }

  validates :username, presence: true, format: { with: USERNAME_FORMAT, message: "must be 3–32 characters: a–z, 0–9, . _ -" },
                       uniqueness: { case_sensitive: false }
  validates :role, inclusion: { in: ROLES }
  validate :password_rules, if: -> { password.present? || password_confirmation.present? }
  validate :keeps_an_active_admin, on: :update

  before_validation { self.otp_required = true if admin? } # R6: TOTP is mandatory for admins
  before_save { self.password_changed_at = Time.current if will_save_change_to_password_digest? }
  before_save { self.otp_secret = nil if will_save_change_to_otp_required? && !otp_required } # dropping TOTP clears it
  after_update :revoke_sessions, if: :security_relevant_change?

  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }

  def admin? = role == "admin"

  def locked? = SignInThrottle.locked?(username)

  def password_set? = password_digest.present?

  def otp_enrolled? = otp_secret.present?

  # --- Sign-in (R3) ---------------------------------------------------------------------------

  # Returns the user only when username and password match, the account is active and not locked.
  # Unknown users still cost one bcrypt comparison (authenticate_by), so timing does not reveal them.
  # Every failure — unknown user, wrong password, locked or inactive account — does the same work:
  # one bcrypt comparison (authenticate_by also hashes for unknown users) and one throttle write
  # (spec 005, F4). Only a successful sign-in takes a different path.
  def self.authenticate(username, password)
    throttle = SignInThrottle.for(username)
    user = authenticate_by(username: throttle.username, password: password.to_s)
    if user.nil? || throttle.locked? || !user.active?
      throttle.register_failure!
      return nil
    end

    throttle.clear! if throttle.persisted?
    user
  end

  # --- TOTP (R4) ------------------------------------------------------------------------------

  def generate_otp_secret = ROTP::Base32.random

  def totp(secret = otp_secret) = ROTP::TOTP.new(secret, issuer: OTP_ISSUER)

  def otp_provisioning_uri(secret = otp_secret) = totp(secret).provisioning_uri(username)

  # Returns the time-step of a valid code, or nil. A code is accepted once: the time-step of the last
  # accepted code cannot be reused (no replay). ±1 step of clock drift is tolerated.
  def check_otp(code, secret: otp_secret)
    code = code.to_s.gsub(/\s/, "")
    return nil if secret.blank? || code !~ /\A\d{6}\z/

    totp(secret).verify(code, drift_behind: 30, drift_ahead: 30, after: otp_last_used_at&.to_i)
  end

  def verify_otp(code)
    timestamp = check_otp(code) or return false
    update!(otp_last_used_at: Time.zone.at(timestamp))
  end

  # Enrolment: the secret is stored only after one valid code proves the authenticator works.
  def enroll_otp!(secret, code)
    timestamp = check_otp(code, secret: secret) or return false
    update!(otp_secret: secret, otp_last_used_at: Time.zone.at(timestamp))
  end

  def reset_otp!
    update!(otp_secret: nil, otp_last_used_at: nil)
  end

  private

  def password_rules
    if password.to_s.length < PASSWORD_MIN
      errors.add(:password, "must be at least #{PASSWORD_MIN} characters")
    elsif password.to_s.bytesize > PASSWORD_MAX_BYTES
      errors.add(:password, "must be at most #{PASSWORD_MAX_BYTES} bytes")
    elsif password.to_s.downcase == username.to_s.downcase
      errors.add(:password, "must not be the username")
    elsif CommonPasswords.include?(password)
      errors.add(:password, "is too common")
    end
    errors.add(:password_confirmation, "doesn't match password") if password_confirmation && password != password_confirmation
  end

  # R6: the last active admin cannot be demoted or deactivated.
  def keeps_an_active_admin
    return unless (will_save_change_to_role? && role_in_database == "admin") || (will_save_change_to_active? && !active && admin?)
    return if User.active.admins.where.not(id: id).exists?

    errors.add(:base, "At least one active admin must remain")
  end

  # R7: sessions are revoked when the password, role, TOTP or account status changes.
  def security_relevant_change?
    saved_change_to_password_digest? || saved_change_to_role? || saved_change_to_active? ||
      (saved_change_to_otp_secret? && otp_secret.nil?) || (saved_change_to_otp_required? && otp_required)
  end

  def revoke_sessions
    sessions.destroy_all
  end
end
