require "test_helper"

# Spec 002: users, password rules (R2), lockout (R3), TOTP (R4), admin rules (R6), session revocation (R7).
class UserTest < ActiveSupport::TestCase
  test "password rules: length, bytes, username, common list, confirmation" do
    user = User.new(username: "alice")
    { "short-pass1" => "at least 12", "x" * 73 => "at most 72 bytes", "password1234" => "too common",
      "alicealicealice" => nil }.each do |password, message|
      user.password = user.password_confirmation = password
      user.valid?
      message ? assert_match(message, user.errors[:password].join) : assert_empty(user.errors[:password])
    end

    user = User.new(username: "aliceusername", password: "AliceUsername", password_confirmation: "AliceUsername")
    assert_not user.valid?
    assert_match "must not be the username", user.errors[:password].join

    user = User.new(username: "alice", password: PASSWORD, password_confirmation: "something else entirely")
    assert_not user.valid?
    assert user.errors[:password_confirmation].any?
  end

  test "username format and case-insensitive uniqueness" do
    create_user(username: "alice")
    assert_not User.new(username: "ALICE", password: PASSWORD).valid?
    assert_not User.new(username: "a!", password: PASSWORD).valid?
    assert_equal "bob", User.new(username: "  Bob ").username
  end

  test "admins always require TOTP" do
    admin = create_user(username: "root1", role: "admin")
    assert admin.otp_required?
    admin.update(otp_required: false)
    assert admin.reload.otp_required?
  end

  test "the last active admin cannot be demoted or deactivated" do
    admin = create_user(username: "root1", role: "admin")
    assert_not admin.update(role: "user")
    assert_not admin.update(active: false)
    create_user(username: "root2", role: "admin")
    assert admin.reload.update(role: "user")
  end

  test "authenticate: correct password, unknown user, wrong password, lockout after 10 failures" do
    user = create_user
    assert_equal user, User.authenticate("Alice", PASSWORD)
    assert_nil User.authenticate("nobody", PASSWORD)
    10.times { assert_nil User.authenticate("alice", "wrong password!!") }
    assert user.locked?
    assert_nil User.authenticate("alice", PASSWORD), "locked even with the right password"
    travel 16.minutes do
      assert_equal user, User.authenticate("alice", PASSWORD)
      assert_equal 0, SignInThrottle.find_by(username: "alice").failed_attempts
    end
  end

  test "F4: a failed sign-in does the same work for existing and unknown usernames" do
    create_user
    writes = lambda do |username|
      statements = []
      counter = ->(*, payload) { statements << payload[:sql][/\A\s*(INSERT|UPDATE|DELETE)\s+INTO\s+"?(\w+)|\A\s*(UPDATE|DELETE)\s+(FROM\s+)?"?(\w+)/i] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { User.authenticate(username, "wrong password!!") }
      statements.compact.map { |sql| sql.gsub(/\s+/, " ").sub(/"/, "") }
    end
    assert_equal writes.call("ghost"), writes.call("alice")
    assert_equal writes.call("ghost"), writes.call("alice"), "also on the second failure"
    assert_equal 2, SignInThrottle.where(username: %w[alice ghost]).count
  end

  test "unknown usernames are locked too, so lockout does not reveal accounts" do
    10.times { User.authenticate("ghost", "wrong password!!") }
    assert SignInThrottle.locked?("ghost")
  end

  test "inactive users cannot sign in" do
    user = create_user
    user.update!(active: false)
    assert_nil User.authenticate("alice", PASSWORD)
  end

  test "TOTP code is accepted once (no replay) and must be 6 digits" do
    user = create_user(otp: true)
    code = otp_code(user)
    assert user.verify_otp(code)
    assert_not user.verify_otp(code), "replay of the same time-step"
    assert_not user.verify_otp("12345")
    travel 31.seconds do
      assert user.verify_otp(otp_code(user))
    end
  end

  test "enrolment stores the secret only with a valid code" do
    user = create_user
    secret = user.generate_otp_secret
    assert_not user.enroll_otp!(secret, "000000")
    assert_nil user.reload.otp_secret
    assert user.enroll_otp!(secret, ROTP::TOTP.new(secret).now)
    assert_equal secret, user.reload.otp_secret
  end

  test "TOTP secret is stored encrypted" do
    user = create_user(otp: true)
    raw = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}")
    assert_not_equal user.otp_secret, raw
  end

  test "dropping TOTP clears the secret" do
    user = create_user(otp: true)
    user.update!(otp_required: false)
    assert_nil user.reload.otp_secret
  end

  test "sessions are revoked on password, role, status and TOTP changes" do
    user = create_user(otp: true)
    create_user(username: "root1", role: "admin")
    { -> { user.update!(password: "another long passphrase", password_confirmation: "another long passphrase") } => "password",
      -> { user.update!(role: "admin") } => "role",
      -> { user.update!(active: false) } => "status",
      -> { user.reset_otp! } => "totp" }.each do |change, name|
      user.sessions.create!
      change.call
      assert_equal 0, user.sessions.count, "sessions revoked after #{name} change"
    end
  end

  # Spec 029, R3: exactly five chat background patterns; Solid by default; nothing else reaches the page.
  test "chat background: five allowed values, Solid by default, unknown values are invalid and shown as Solid" do
    user = create_user
    assert_equal "solid", user.chat_background
    assert_equal "solid", User.new.chat_background, "database default"
    assert_equal %w[solid dots grid gradient animated], User::CHAT_BACKGROUNDS.keys
    User::CHAT_BACKGROUNDS.each_key do |value|
      user.chat_background = value
      assert user.valid?, value
      assert_equal value, user.shown_chat_background
    end
    [ "", nil, "Dots", "pink", "dots; x" ].each do |value|
      user.chat_background = value
      assert_not user.valid?, value.inspect
      assert_equal "solid", user.shown_chat_background
    end
  end

  test "chat background survives a reload and changing it keeps the sessions" do
    user = create_user
    user.sessions.create!
    user.update!(chat_background: "grid")
    assert_equal "grid", User.find(user.id).chat_background
    assert_equal 1, user.sessions.count
  end
end
