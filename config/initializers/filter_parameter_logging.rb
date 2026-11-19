# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# :otp is not listed: :secret covers otp_secret and :code covers TOTP codes, so fields such as
# otp_required stay readable in the audit log and changelog (specs 003, 004).
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :ssn, :cvv, :cvc, :code, :digest
]
