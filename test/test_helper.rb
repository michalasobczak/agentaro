ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)
    # Each test process has its own database, so run ids repeat across processes: give each its own runs folder,
    # or two tests' runs share var/runs/test/<id> (found with spec 019: a flaky verifier test).
    parallelize_setup do |worker|
      Rails.application.config.x.runs_dir = File.join(Rails.application.config.x.runs_dir, "worker-#{worker}")
    end

    include ActiveSupport::Testing::TimeHelpers

    PASSWORD = "correct horse battery staple"

    def create_user(username: "alice", role: "user", password: PASSWORD, otp: false)
      attrs = { username: username, role: role, password: password, password_confirmation: password, otp_required: otp }
      attrs[:otp_secret] = ROTP::Base32.random if otp || role == "admin"
      User.create!(attrs)
    end

    def otp_code(user, at: Time.current)
      ROTP::TOTP.new(user.reload.otp_secret).at(at)
    end
  end
end

class ActionDispatch::IntegrationTest
  setup { https! } # the test browser speaks HTTPS, so Secure cookies are sent back

  # Signs in through the real forms. Moves the clock to a fresh TOTP time-step when needed,
  # because a code can be used only once (replay protection).
  def sign_in(user, password: PASSWORD)
    post session_path, params: { username: user.username, password: password }
    return unless user.otp_required? && user.otp_enrolled?

    travel 31.seconds if user.reload.otp_last_used_at && user.otp_last_used_at.to_i >= (Time.current.to_i / 30) * 30
    post two_factor_path, params: { code: otp_code(user) }
  end
end
