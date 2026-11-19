require "test_helper"

# Spec 003: S1 (every request logged), S2 (no secrets), S3 (tampering detected), S4 (append-only),
# S5 (admins only), G4 (pruning keeps the chain verifiable).
class AuditLogTest < ActionDispatch::IntegrationTest
  test "S1: every request produces exactly one row, signed in or not" do
    user = create_user
    assert_difference -> { AuditEvent.count }, 1 do
      get rails_health_check_path
    end
    get "/does-not-exist"
    assert_equal [ "/does-not-exist", 404 ], [ AuditEvent.last.path, AuditEvent.last.status ]

    sign_in(user)
    get root_path
    row = AuditEvent.last
    assert_equal [ "GET", "/", 200, user.id, "alice" ], [ row.http_method, row.path, row.status, row.user_id, row.username ]
    assert row.request_id.present? && row.duration_ms
  end

  test "S2: passwords, TOTP codes and link tokens never reach the audit log" do
    admin = create_user(username: "root1", role: "admin")
    code = otp_code(admin)
    post session_path, params: { username: "root1", password: PASSWORD }
    post two_factor_path, params: { code: code }
    link = PasswordLink.issue!(user: create_user, created_by: admin)
    get password_reset_path(token: link.token)
    patch password_reset_path, params: { token: link.token, password: "a fresh passphrase", password_confirmation: "a fresh passphrase" }

    stored = AuditEvent.pluck(:path, :query, :body).flatten.compact.join("\n")
    [ PASSWORD, code, link.token, "a fresh passphrase" ].each { |secret| assert_not_includes stored, secret }
    assert_includes stored, "[FILTERED]"
    assert_includes stored, "root1", "the typed username is kept"
  end

  test "sign-out is attributed to the user even though the session is gone" do
    sign_in(create_user)
    delete session_path
    assert_equal [ "/session", "alice" ], [ AuditEvent.last.path, AuditEvent.last.username ]
  end

  test "a request id sent by the client is replaced" do
    get rails_health_check_path, headers: { "X-Request-Id" => "spoofed" }
    assert_not_equal "spoofed", AuditEvent.last.request_id
    assert_equal AuditEvent.last.request_id, response.headers["X-Request-Id"]
  end

  test "S3: editing or deleting a row breaks verification at that row" do
    3.times { get rails_health_check_path }
    assert_nil AuditEvent.first_broken_row
    rows = AuditEvent.order(:id).last(3)
    AuditEvent.connection.execute("UPDATE audit_events SET path = '/edited' WHERE id = #{rows[1].id}")
    assert_equal rows[1].id, AuditEvent.first_broken_row.id
    AuditEvent.connection.execute("UPDATE audit_events SET path = '#{rows[1].path}' WHERE id = #{rows[1].id}")
    AuditEvent.connection.execute("DELETE FROM audit_events WHERE id = #{rows[1].id}")
    assert_equal rows[2].id, AuditEvent.first_broken_row.id
  end

  test "S4: rows cannot be changed or deleted through the application" do
    get rails_health_check_path
    row = AuditEvent.last
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.update!(path: "/x") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.destroy }
  end

  test "G4: pruning removes old rows and keeps the chain verifiable" do
    travel_to 4.months.ago do
      2.times { get rails_health_check_path }
    end
    get rails_health_check_path
    removed = AuditEvent.prune!(before: AuditEvent::RETENTION.ago)
    assert removed >= 2
    assert AuditEvent.where(occurred_at: ...AuditEvent::RETENTION.ago).none?
    assert_nil AuditEvent.first_broken_row
  end

  test "S5: admins can browse the audit log" do
    sign_in(create_user(username: "root1", role: "admin"))
    get admin_audit_events_path(path: "session")
    assert_response :success
    assert_match "/session", response.body
  end
end
