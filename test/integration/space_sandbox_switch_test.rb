require "test_helper"

# Spec 054, G1, Q2, S4: the switch on the space's page — confirmation, owner only, the data changelog.
class SpaceSandboxSwitchTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir("sandbox-page")
    @user = create_user
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra", working_dir: @dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "the page shows the switch with a confirmation that names the risk; on and off again" do
    sign_in(@user)
    get space_path(@space)
    assert_select "#sandbox.desktop-only h2", text: /No sandbox\s*off/
    assert_select "#sandbox form[data-confirm*='Agentaro\\'s databases and secrets'] button", text: "Run without a sandbox"
    assert_select "[style]", 0
    patch sandbox_space_path(@space, on: 1)
    assert_redirected_to space_path(@space, anchor: "sandbox")
    assert @space.reload.no_sandbox?
    assert DataChange.where(record_type: "Space", record_id: @space.id).any? { |c| c.changes_hash.key?("no_sandbox") }, "in the data changelog"
    get space_path(@space)
    assert_select "#sandbox h2", text: /No sandbox\s*on/
    patch sandbox_space_path(@space, on: 0)
    assert_not @space.reload.no_sandbox?
  end

  test "another user cannot change it; signed out, nothing changes" do
    other = create_user(username: "other1")
    sign_in(other)
    patch sandbox_space_path(@space, on: 1)
    assert_response :not_found
    assert_not @space.reload.no_sandbox?
  end

  test "a space without a working folder has no switch" do
    plain = @user.spaces.create!(kind: "team", name: "Zespół")
    sign_in(@user)
    get space_path(plain)
    assert_select "#sandbox", 0
    patch sandbox_space_path(plain, on: 1)
    assert_not plain.reload.no_sandbox?
  end

  test "B20: the space's form cannot turn the sandbox off; only the confirmed switch can" do
    sign_in(@user)
    patch space_path(@space), params: { space: { name: "Gra", no_sandbox: "1" } }
    assert_not @space.reload.no_sandbox?
  end
end
