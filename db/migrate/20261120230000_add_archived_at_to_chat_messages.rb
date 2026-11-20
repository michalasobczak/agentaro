# Spec 015: an archived conversation — every message of it gets the same archived_at.
class AddArchivedAtToChatMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_messages, :archived_at, :datetime
    add_index :chat_messages, %i[user_id archived_at]
  end
end
