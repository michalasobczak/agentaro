require "test_helper"
require Rails.root.join("lib/agentaro/audit_retention")

# Spec 005, F3: retention is enforced automatically, at most once a day per process.
class AuditRetentionTest < ActiveSupport::TestCase
  setup { Agentaro::AuditRetention.reset! }

  test "S3: old rows are removed without manual action and the chains still verify" do
    travel_to 4.months.ago do
      create_user(username: "old-one")
      AuditEvent.append!(request_id: "old", http_method: "GET", path: "/old", status: 200)
    end
    create_user(username: "new-one")
    assert Agentaro::AuditRetention.run_if_due(async: false)
    assert AuditEvent.where(occurred_at: ...3.months.ago).none?
    assert DataChange.where(occurred_at: ...3.months.ago).none?
    assert DataChange.exists?(record_type: "User", record_id: User.find_by(username: "new-one").id)
    assert_nil AuditEvent.first_broken_row
    assert_nil DataChange.first_broken_row
  end

  test "runs at most once per 24 hours" do
    assert Agentaro::AuditRetention.run_if_due(async: false)
    assert_not Agentaro::AuditRetention.run_if_due(async: false)
    assert Agentaro::AuditRetention.run_if_due(now: 25.hours.from_now, async: false)
  end
end
