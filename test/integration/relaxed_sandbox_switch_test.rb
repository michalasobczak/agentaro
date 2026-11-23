require "test_helper"

# Spec 053, G1, R3: the switch on the Executors page changes only the signed-in account.
class RelaxedSandboxSwitchTest < ActionDispatch::IntegrationTest
  test "the Executors page shows the setting; the switch turns it off and on for this account only" do
    user = create_user
    other = create_user(username: "other1")
    sign_in(user)
    get executors_path
    assert_select ".sandbox-card h2", text: /Relaxed sandbox\s*on/
    assert_select ".sandbox-card", text: /Always denied: reading Agentaro's storage/
    assert_select "[style]", 0
    patch account_relaxed_sandbox_path(on: 0)
    assert_redirected_to executors_path
    assert_not user.reload.relaxed_sandbox?
    assert other.reload.relaxed_sandbox?
    patch account_relaxed_sandbox_path(on: 1)
    assert user.reload.relaxed_sandbox?
  end

  test "signed out, nothing changes" do
    user = create_user
    patch account_relaxed_sandbox_path(on: 0)
    assert user.reload.relaxed_sandbox?
  end
end
