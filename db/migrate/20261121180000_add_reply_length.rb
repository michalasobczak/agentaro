# Spec 039: how much the director writes — the owner's level, Krótko (1) for everyone (S1).
class AddReplyLength < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reply_length, :integer, default: 1, null: false
  end
end
