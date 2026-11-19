require "io/console"

module Agentaro
  # Spec 002, G7: admin management on the server's command line.
  #
  # Physical or shell access to the machine is the strongest proof of identity available, so this is
  # the only way to create an admin, change an admin password or replace an admin's authenticator.
  # Changes are recorded in the data changelog as "cli:<operating-system user>" (spec 004).
  class AdminCli
    OTP_ATTEMPTS = 3

    def initialize(input: $stdin, output: $stdout, os_user: ENV.fetch("USER", "unknown"))
      @in = input
      @out = output
      Current.actor = "cli:#{os_user}"
    end

    def create(username)
      user = User.new(username: username.presence || ask("Username: "), role: "admin")
      set_password(user) or return false
      return fail_with(user.errors.full_messages) unless user.valid?

      secret = user.generate_otp_secret
      timestamp = confirm_authenticator(user, secret) or return false
      user.otp_secret = secret
      user.otp_last_used_at = Time.zone.at(timestamp)
      user.save!
      say "Admin #{user.username} created. Sign in with the password and a code from the authenticator."
      true
    end

    def change_password(username)
      user = find_admin(username) or return false
      set_password(user) or return false
      return fail_with(user.errors.full_messages) unless user.save

      say "Password of #{user.username} changed. All their sessions were signed out."
      true
    end

    def reset_totp(username)
      user = find_admin(username) or return false
      secret = user.generate_otp_secret
      timestamp = confirm_authenticator(user, secret) or return false
      user.update!(otp_secret: secret, otp_last_used_at: Time.zone.at(timestamp))
      user.sessions.find_each(&:destroy)
      say "Authenticator of #{user.username} replaced. All their sessions were signed out."
      true
    end

    private

    def find_admin(username)
      name = (username.presence || ask("Username: ")).to_s.strip.downcase
      user = User.admins.find_by(username: name)
      user || fail_with([ "No admin named #{name}." ])
    end

    def set_password(user)
      user.password = ask_secret("Password (at least #{User::PASSWORD_MIN} characters): ")
      user.password_confirmation = ask_secret("Repeat password: ")
      return true if user.password.present?

      fail_with([ "Password can't be blank." ])
    end

    # Shows the QR code in the terminal and asks for a code, so the secret is stored only once it works.
    def confirm_authenticator(user, secret)
      uri = user.otp_provisioning_uri(secret)
      say "\nScan this QR code with Google Authenticator (or another TOTP app):\n\n"
      say RQRCode::QRCode.new(uri).as_ansi(quiet_zone_size: 2)
      say "\nOr enter this key manually: #{secret.scan(/.{1,4}/).join(" ")}\n\n"
      OTP_ATTEMPTS.times do
        timestamp = user.check_otp(ask("Code from the app: "), secret: secret)
        return timestamp if timestamp

        say "That code is not valid. Try again."
      end
      fail_with([ "Authenticator not confirmed. Nothing was changed." ])
    end

    def ask(prompt)
      @out.print(prompt)
      @in.gets.to_s.chomp
    end

    def ask_secret(prompt)
      @out.print(prompt)
      line = @in.respond_to?(:noecho) && @in.tty? ? @in.noecho(&:gets) : @in.gets
      @out.puts
      line.to_s.chomp
    end

    def say(text) = @out.puts(text)

    def fail_with(messages)
      messages.each { |m| @out.puts("Error: #{m}") }
      false
    end
  end
end
