require "test_helper"
require Rails.root.join("lib/agentaro/admin_cli")

# Spec 002, G7: admins are created and managed on the command line.
class AdminCliTest < ActiveSupport::TestCase
  # Feeds answers to the prompts; the TOTP code is computed from the secret printed on screen.
  def run_cli(command, username, answers)
    output = StringIO.new
    input = Object.new
    queue = answers.dup
    input.define_singleton_method(:gets) do
      answer = queue.shift
      answer = answer.call(output.string) if answer.respond_to?(:call)
      "#{answer}\n"
    end
    result = Agentaro::AdminCli.new(input: input, output: output, os_user: "tester").public_send(command, username)
    [ result, output.string ]
  end

  def code_from_screen = ->(screen) { ROTP::TOTP.new(screen[/manually: ([A-Z2-7 ]+)/, 1].delete(" ")).now }

  test "creates an admin with a confirmed authenticator, attributed to cli:<user>" do
    ok, screen = run_cli(:create, "root1", [ PASSWORD, PASSWORD, code_from_screen ])
    assert ok, screen
    admin = User.find_by!(username: "root1")
    assert admin.admin? && admin.otp_enrolled? && admin.authenticate_password(PASSWORD)
    assert_equal "cli:tester", DataChange.where(record_type: "User", record_id: admin.id, action: "create").last.actor
  end

  test "nothing is created when the authenticator is not confirmed" do
    ok, screen = run_cli(:create, "root1", [ PASSWORD, PASSWORD, "000000", "000000", "000000" ])
    assert_not ok
    assert_match "Nothing was changed", screen
    assert_not User.exists?(username: "root1")
  end

  test "rejects a weak password" do
    ok, screen = run_cli(:create, "root1", %w[short short])
    assert_not ok
    assert_match "at least 12", screen
  end

  test "changes an admin password and signs out their sessions" do
    admin = create_user(username: "root1", role: "admin")
    admin.sessions.create!
    ok, = run_cli(:change_password, "root1", [ "new admin passphrase", "new admin passphrase" ])
    assert ok
    assert admin.reload.authenticate_password("new admin passphrase")
    assert_equal 0, admin.sessions.count
  end

  test "replaces an admin authenticator" do
    admin = create_user(username: "root1", role: "admin")
    old = admin.otp_secret
    ok, = run_cli(:reset_totp, "root1", [ code_from_screen ])
    assert ok
    assert_not_equal old, admin.reload.otp_secret
  end

  test "refuses to manage regular users" do
    create_user
    ok, screen = run_cli(:change_password, "alice", [])
    assert_not ok
    assert_match "No admin named alice", screen
  end
end
