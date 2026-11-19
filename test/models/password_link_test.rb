require "test_helper"

# Spec 002, G6/R8 and S5.
class PasswordLinkTest < ActiveSupport::TestCase
  setup do
    @admin = create_user(username: "root1", role: "admin")
    @user = create_user
  end

  test "stores only a digest; works once" do
    link = PasswordLink.issue!(user: @user, created_by: @admin)
    assert_not_equal link.token, link.token_digest
    assert_equal link, PasswordLink.find_usable(link.token)
    assert link.redeem!(password: "brand new passphrase", password_confirmation: "brand new passphrase")
    assert_nil PasswordLink.find_usable(link.token)
    assert @user.reload.authenticate_password("brand new passphrase")
  end

  test "expires after 24 hours" do
    link = PasswordLink.issue!(user: @user, created_by: @admin)
    travel 25.hours do
      assert_nil PasswordLink.find_usable(link.token)
    end
  end

  test "a new link invalidates older unused ones" do
    old = PasswordLink.issue!(user: @user, created_by: @admin)
    PasswordLink.issue!(user: @user, created_by: @admin)
    assert_nil PasswordLink.find_usable(old.token)
  end

  test "cannot be created for an admin" do
    assert_raises(ActiveRecord::RecordInvalid) { PasswordLink.issue!(user: @admin, created_by: @admin) }
  end

  test "a weak password is rejected and the link stays usable" do
    link = PasswordLink.issue!(user: @user, created_by: @admin)
    assert_not link.redeem!(password: "short", password_confirmation: "short")
    assert PasswordLink.find_usable(link.token)
  end

  test "redeeming clears lockout and revokes sessions" do
    10.times { User.authenticate("alice", "wrong password!!") }
    assert @user.locked?
    @user.sessions.create!
    link = PasswordLink.issue!(user: @user, created_by: @admin)
    link.redeem!(password: "brand new passphrase", password_confirmation: "brand new passphrase")
    assert_not @user.reload.locked?
    assert_equal 0, @user.sessions.count
  end
end
