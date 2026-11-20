# Owner fix after spec 017 ("wiadomości się rozsynchronizowują"): which user message an answer was written for,
# so the chat never presents (or speaks) an answer to an earlier message as the answer to the latest one.
class AddReplyToToChatMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_messages, :reply_to_id, :integer
  end
end
