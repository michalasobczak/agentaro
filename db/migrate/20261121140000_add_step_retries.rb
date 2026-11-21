# Spec 032: automatic retry of failed steps. A failed attempt gets its kind; a retry is a queued run that waits
# until retry_at; attempt counts the tries since the owner last started the step. The owner can switch retries off.
class AddStepRetries < ActiveRecord::Migration[8.1]
  def change
    add_column :task_runs, :failure_kind, :string
    add_column :task_runs, :retry_at, :datetime
    add_column :task_runs, :attempt, :integer, default: 1, null: false
    add_index :task_runs, %i[state retry_at]
    add_column :users, :auto_retry, :boolean, default: true, null: false
  end
end
