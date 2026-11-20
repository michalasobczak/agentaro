# Spec 026: when the user closed the "blocked" notice of an epic; cleared each time the epic is blocked again.
class AddBlockDismissedAtToWorkItems < ActiveRecord::Migration[8.1]
  def change
    add_column :work_items, :block_dismissed_at, :datetime
  end
end
