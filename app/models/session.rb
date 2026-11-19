# Spec 002, G3: a signed-in browser. Stored in the database so it can be listed and revoked.
class Session < ApplicationRecord
  LIFETIME = 7.days # fixed from sign-in, not sliding

  belongs_to :user

  scope :current, -> { where(created_at: LIFETIME.ago..) }
  scope :expired, -> { where(created_at: ...LIFETIME.ago) }

  def expired? = created_at < LIFETIME.ago

  def expires_at = created_at + LIFETIME

  # Fully signed in: password checked and, when the account needs TOTP, the code checked too.
  def authenticated? = !user.otp_required? || otp_verified?
end
