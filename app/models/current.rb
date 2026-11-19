# Per-request (or per-command) context: who is acting and which request caused it.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :actor, :request_id

  delegate :user, to: :session, allow_nil: true

  # Actor recorded in the data changelog (spec 004).
  def self.actor_label
    actor || (user ? "user:#{user.id}:#{user.username}" : "system")
  end
end
