# Spec 046, G1: how the conversation flows — 1 Zwykła, 2 Naturalna (default).
class AddConversationModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :conversation_mode, :integer, default: 2, null: false
  end
end
