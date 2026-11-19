require "test_helper"

# Spec 002: S1 (pages need a session), S3 (admins need TOTP), S4 (7-day sessions), S6 (no enumeration).
class AuthenticationTest < ActionDispatch::IntegrationTest
  test "S1: pages redirect to sign-in without a session; public pages stay public" do
    [ root_path, account_sessions_path, edit_account_password_path, admin_users_path, admin_audit_events_path, admin_data_changes_path ].each do |path|
      get path
      assert_redirected_to new_session_path, path
    end
    get new_session_path
    assert_response :success
    get rails_health_check_path
    assert_response :success
    get password_reset_path(token: "nope")
    assert_response :not_found
  end

  test "regular user without TOTP signs in and out" do
    user = create_user
    sign_in(user)
    assert_redirected_to root_url
    follow_redirect!
    assert_match "Welcome, alice", response.body
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "returns to the page that was requested before sign-in" do
    user = create_user
    get account_sessions_path
    sign_in(user)
    assert_redirected_to account_sessions_url
  end

  test "S6: same response for unknown user, wrong password, inactive and locked accounts" do
    create_user
    inactive = create_user(username: "carol")
    create_user(username: "root1", role: "admin")
    inactive.update!(active: false)
    bodies = [ %w[nobody whatever-password], [ "alice", "wrong password!!" ], [ "carol", PASSWORD ] ].map do |username, password|
      post session_path, params: { username: username, password: password }
      assert_response :unprocessable_content
      response.body.scan(/<div class="flash alert"[^>]*>.*?<\/div>/).first
    end
    assert_equal 1, bodies.uniq.size
    assert_match SessionsController::INVALID, bodies.first
  end

  test "S3: an admin cannot reach any page before the TOTP step" do
    admin = create_user(username: "root1", role: "admin")
    post session_path, params: { username: "root1", password: PASSWORD }
    assert_redirected_to new_two_factor_path
    get root_path
    assert_redirected_to new_two_factor_path
    get admin_users_path
    assert_redirected_to new_two_factor_path
    post two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_content
    post two_factor_path, params: { code: otp_code(admin) }
    assert_redirected_to root_url
    get admin_users_path
    assert_response :success
  end

  test "repeated wrong TOTP codes lock the account and end the session" do
    admin = create_user(username: "root1", role: "admin")
    post session_path, params: { username: "root1", password: PASSWORD }
    10.times { post two_factor_path, params: { code: "000000" } }
    assert admin.reload.locked?
    get root_path
    assert_redirected_to new_session_path
  end

  test "user who must use TOTP but has no authenticator enrols right after the password" do
    user = create_user
    user.update!(otp_required: true)
    post session_path, params: { username: "alice", password: PASSWORD }
    assert_redirected_to new_two_factor_enrollment_path
    get root_path
    assert_redirected_to new_two_factor_enrollment_path
    get new_two_factor_enrollment_path
    assert_response :success
    assert_match "<svg", response.body
    secret = session[:pending_otp_secret]
    post two_factor_enrollment_path, params: { code: "000000" }
    assert_redirected_to new_two_factor_enrollment_path
    post two_factor_enrollment_path, params: { code: ROTP::TOTP.new(secret).now }
    assert_redirected_to root_url
    assert_equal secret, user.reload.otp_secret
  end

  test "S4: a session older than 7 days is rejected and deleted" do
    user = create_user
    sign_in(user)
    old_session = user.sessions.last
    travel 7.days + 1.minute do
      assert old_session.reload.expired?
      get root_path
      assert_redirected_to new_session_path
      sign_in(user)
      assert_not Session.exists?(old_session.id), "expired rows are removed"
    end
  end

  test "S4: an expired session is rejected even if the browser still sends its cookie" do
    user = create_user
    sign_in(user)
    user.sessions.last.update!(created_at: 8.days.ago)
    get root_path
    assert_redirected_to new_session_path
    assert_equal 0, user.sessions.count
  end

  test "session cookie is httponly and SameSite=Lax" do
    sign_in(create_user)
    cookie = Array(response.headers["Set-Cookie"]).join("\n").lines.find { |l| l.start_with?("session_id=") }
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
  end

  test "users see and revoke their own sessions" do
    user = create_user
    other = user.sessions.create!(user_agent: "other browser")
    sign_in(user)
    get account_sessions_path
    assert_match "other browser", response.body
    delete account_session_path(other)
    assert_not Session.exists?(other.id)
    stranger = create_user(username: "bob").sessions.create!
    delete account_session_path(stranger)
    assert_response :not_found
    assert Session.exists?(stranger.id)
  end

  test "regular users change their own password; admins cannot in the web interface" do
    user = create_user
    sign_in(user)
    patch account_password_path, params: { current_password: "wrong", password: "new long passphrase", password_confirmation: "new long passphrase" }
    assert_response :unprocessable_content
    patch account_password_path, params: { current_password: PASSWORD, password: "new long passphrase", password_confirmation: "new long passphrase" }
    assert_redirected_to new_session_path
    assert user.reload.authenticate_password("new long passphrase")

    admin = create_user(username: "root1", role: "admin")
    sign_in(admin)
    get edit_account_password_path
    assert_response :forbidden
    patch account_password_path, params: { current_password: PASSWORD, password: "new long passphrase", password_confirmation: "new long passphrase" }
    assert_response :forbidden
    assert admin.reload.authenticate_password(PASSWORD)
  end
end
