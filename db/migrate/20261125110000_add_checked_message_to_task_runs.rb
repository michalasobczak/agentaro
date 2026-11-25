# Spec 050: a check run knows which director reply it checks.
class AddCheckedMessageToTaskRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :task_runs, :checked_message_id, :integer
  end
end
