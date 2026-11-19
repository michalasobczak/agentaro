# Spec 002, G6/R8: one-time link that lets a regular user set a new password, handed over by an admin.
# Only a digest of the token is stored; the token itself is shown once to the admin.
class PasswordLink < ApplicationRecord
  VALIDITY = 24.hours

  belongs_to :user
  belongs_to :created_by, class_name: "User"

  validate :not_for_admins, on: :create

  attr_reader :token

  scope :usable, -> { where(used_at: nil).where(expires_at: Time.current..) }

  # Creates a link and invalidates the user's older unused links.
  def self.issue!(user:, created_by:)
    token = SecureRandom.urlsafe_base64(32)
    transaction do
      user.password_links.usable.find_each { |link| link.update!(expires_at: Time.current) }
      link = create!(user: user, created_by: created_by, token_digest: digest(token), expires_at: VALIDITY.from_now)
      link.instance_variable_set(:@token, token)
      link
    end
  end

  def self.find_usable(token)
    return nil if token.blank?

    usable.find_by(token_digest: digest(token))
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # Sets the password; on success the link is used up, lockout lifted, sessions revoked (via User).
  def redeem!(password:, password_confirmation:)
    transaction do
      user.password = password
      user.password_confirmation = password_confirmation
      user.save!
      SignInThrottle.clear(user.username) # a new password lifts the lockout
      update!(used_at: Time.current)
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  private

  def not_for_admins
    errors.add(:user, "is an admin — admin passwords change only from the command line") if user&.admin?
  end
end
