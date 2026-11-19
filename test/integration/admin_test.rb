require "test_helper"

# Spec 002: S2 (admin pages for admins only), G5 (user management), S5 (password-change links).
class AdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(username: "root1", role: "admin")
  end

  test "S2: regular users get 403 on every admin page and action" do
    user = create_user
    sign_in(user)
    [ admin_users_path, new_admin_user_path, admin_user_path(user), admin_audit_events_path, admin_data_changes_path ].each do |path|
      get path
      assert_response :forbidden, path
    end
    post admin_users_path, params: { user: { username: "mallory" } }
    assert_response :forbidden
    patch admin_user_path(user), params: { user: { role: "admin" } }
    assert_response :forbidden
    assert_equal "user", user.reload.role
    post admin_user_password_links_path(user)
    assert_response :forbidden
  end

  test "admin creates a user and hands over a link; the user sets a password and signs in" do
    sign_in(@admin)
    post admin_users_path, params: { user: { username: "bob" } }
    assert_response :created
    url = response.body[%r{https://[^<"]+/password_reset\?token=[^<"\s]+}]
    assert url, "link shown to the admin"
    bob = User.find_by!(username: "bob")
    assert_equal "user", bob.role
    assert_not bob.password_set?

    delete session_path
    token = Rack::Utils.parse_query(URI(url).query)["token"]
    get password_reset_path(token: token)
    assert_response :success
    patch password_reset_path, params: { token: token, password: "bob's long passphrase", password_confirmation: "bob's long passphrase" }
    assert_redirected_to new_session_path
    patch password_reset_path, params: { token: token, password: "another passphrase!", password_confirmation: "another passphrase!" }
    assert_response :not_found, "link works once"

    sign_in(bob, password: "bob's long passphrase")
    assert_redirected_to root_url
  end

  test "S5: no password-change link for an admin" do
    other_admin = create_user(username: "root2", role: "admin")
    sign_in(@admin)
    post admin_user_password_links_path(other_admin)
    assert_redirected_to admin_user_path(other_admin)
    assert_equal 0, PasswordLink.count
  end

  test "admin requires TOTP for a user, resets it, revokes sessions, deactivates" do
    user = create_user(otp: true)
    user.sessions.create!
    sign_in(@admin)

    post reset_totp_admin_user_path(user)
    assert_nil user.reload.otp_secret
    assert_equal 0, user.sessions.count

    patch admin_user_path(user), params: { user: { otp_required: "0" } }
    assert_not user.reload.otp_required?

    user.sessions.create!
    post revoke_sessions_admin_user_path(user)
    assert_equal 0, user.sessions.count

    patch admin_user_path(user), params: { user: { active: "0" } }
    assert_not user.reload.active?
  end

  test "the last admin cannot deactivate or demote themselves" do
    sign_in(@admin)
    patch admin_user_path(@admin), params: { user: { role: "user" } }
    assert_response :unprocessable_content
    assert @admin.reload.admin?
  end
end
