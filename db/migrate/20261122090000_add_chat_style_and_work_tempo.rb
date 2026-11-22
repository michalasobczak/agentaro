# Spec 041: the owner's conversation style (Dorosły, 2) and work tempo (Normalnie, 2) for everyone (S4);
# a space's own tempo, empty = the owner's default (G5).
class AddChatStyleAndWorkTempo < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chat_style, :integer, default: 2, null: false
    add_column :users, :work_tempo, :integer, default: 2, null: false
    add_column :spaces, :work_tempo, :integer
  end
end
