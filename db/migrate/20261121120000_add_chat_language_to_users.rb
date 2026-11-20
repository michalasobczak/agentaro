# Owner fix after spec 017: the language of the conversation with the director — auto, Polish or English.
class AddChatLanguageToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chat_language, :string, null: false, default: "auto"
  end
end
