# Spec 029, R3: the chat background pattern chosen by the user; existing accounts get Solid.
class AddChatBackgroundToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chat_background, :string, default: "solid", null: false
  end
end
