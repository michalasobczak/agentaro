# Spec 002 R3 and spec 005 F4: counts failed sign-ins per typed username.
#
# Keyed by the username as typed (normalized), not by account, so a failed sign-in does exactly the
# same work whether the account exists or not — the response time does not reveal accounts. After
# MAX_FAILED_ATTEMPTS the name is locked for LOCK_DURATION, existing account or not.
class SignInThrottle < ApplicationRecord
  MAX_FAILED_ATTEMPTS = 10
  LOCK_DURATION = 15.minutes
  USERNAME_LIMIT = 64
  STALE_AFTER = 1.day

  scope :stale, -> { where(updated_at: ...STALE_AFTER.ago).where("locked_until IS NULL OR locked_until < ?", Time.current) }

  def self.normalize(username) = username.to_s.strip.downcase[0, USERNAME_LIMIT]

  def self.for(username) = find_or_initialize_by(username: normalize(username))

  def self.locked?(username) = find_by(username: normalize(username))&.locked? || false

  def self.clear(username) = find_by(username: normalize(username))&.clear!

  def locked? = locked_until.present? && locked_until.future?

  def register_failure!
    self.failed_attempts += 1
    self.locked_until = LOCK_DURATION.from_now if failed_attempts >= MAX_FAILED_ATTEMPTS && !locked?
    save!
  end

  def clear!
    update!(failed_attempts: 0, locked_until: nil) if failed_attempts.positive? || locked_until
  end
end
