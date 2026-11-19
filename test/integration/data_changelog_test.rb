require "test_helper"

# Spec 004: S1 (create/update/delete recorded), S2 (CLI actor — see AdminCliTest), S3 (no secrets),
# S4 (request id links to the audit log), S5 (tampering detected), R1 (rollbacks not recorded).
class DataChangelogTest < ActionDispatch::IntegrationTest
  test "S1: create, update and destroy are recorded with before/after values" do
    user = create_user
    created = DataChange.where(record_type: "User", record_id: user.id, action: "create").last
    assert_equal [ nil, "alice" ], created.changes_hash["username"]
    assert_equal "system", created.actor

    user.update!(active: false)
    updated = DataChange.where(record_type: "User", record_id: user.id, action: "update").last
    assert_equal [ true, false ], updated.changes_hash["active"]
    assert_not updated.changes_hash.key?("updated_at")

    session = user.sessions.create!
    session.destroy
    destroyed = DataChange.where(record_type: "Session", record_id: session.id, action: "destroy").last
    assert_equal [ user.id, nil ], destroyed.changes_hash["user_id"]
  end

  test "S3: sensitive fields show as changed, with values filtered" do
    user = create_user(otp: true)
    stored = DataChange.where(record_type: "User", record_id: user.id).pluck(:changeset).join
    assert_not_includes stored, user.password_digest
    assert_not_includes stored, user.otp_secret
    created = DataChange.where(record_type: "User", record_id: user.id, action: "create").last.changes_hash
    assert_equal "[FILTERED]", created["password_digest"]
    assert_equal "[FILTERED]", created["otp_secret"]
  end

  test "R1: a rolled-back change is not recorded" do
    assert_no_difference -> { DataChange.count } do
      User.transaction do
        create_user(username: "ghost")
        raise ActiveRecord::Rollback
      end
    end
  end

  test "S4: web changes carry the actor and a request id that exists in the audit log" do
    admin = create_user(username: "root1", role: "admin")
    user = create_user
    sign_in(admin)
    patch admin_user_path(user), params: { user: { otp_required: "1" } }
    change = DataChange.where(record_type: "User", record_id: user.id, action: "update").last
    assert_equal "user:#{admin.id}:root1", change.actor
    assert AuditEvent.exists?(request_id: change.request_id, path: "/admin/users/#{user.id}")
  end

  test "sign-in and password links are attributed to the person, not to system" do
    user = create_user
    sign_in(user)
    assert_equal "user:#{user.id}:alice", DataChange.where(record_type: "Session", action: "create").last.actor

    admin = create_user(username: "root1", role: "admin")
    link = PasswordLink.issue!(user: user, created_by: admin)
    patch password_reset_path, params: { token: link.token, password: "a fresh passphrase", password_confirmation: "a fresh passphrase" }
    change = DataChange.where(record_type: "User", record_id: user.id, action: "update").last
    assert_equal "password-link:#{user.id}:alice", change.actor
  end

  test "fields such as otp_required stay readable; secrets do not" do
    user = create_user
    user.update!(otp_required: true)
    assert_equal [ false, true ], DataChange.where(record_type: "User", record_id: user.id, action: "update").last.changes_hash["otp_required"]
  end

  test "S5: tampering breaks verification" do
    create_user
    assert_nil DataChange.first_broken_row
    row = DataChange.last
    DataChange.connection.execute("UPDATE data_changes SET actor = 'someone' WHERE id = #{row.id}")
    assert_equal row.id, DataChange.first_broken_row.id
  end

  test "G5: admins see a record's history" do
    admin = create_user(username: "root1", role: "admin")
    sign_in(admin)
    get admin_data_changes_path(record_type: "User", record_id: admin.id)
    assert_response :success
    assert_match "root1", response.body
  end
end
