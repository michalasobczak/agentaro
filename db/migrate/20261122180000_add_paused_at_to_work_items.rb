# Spec 048: an epic paused by its owner (a flag on a planned epic, not a new state).
class AddPausedAtToWorkItems < ActiveRecord::Migration[8.1]
  def change
    add_column :work_items, :paused_at, :datetime
  end
end
