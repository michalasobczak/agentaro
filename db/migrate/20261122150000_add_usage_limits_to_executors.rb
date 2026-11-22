# Spec 043, G1: the last usage-limit reading of an executor's subscription (Claude Code, Codex).
class AddUsageLimitsToExecutors < ActiveRecord::Migration[8.1]
  def change
    add_column :executors, :usage_limits, :text
    add_column :executors, :usage_read_at, :datetime
  end
end
