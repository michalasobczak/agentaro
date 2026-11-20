# Owner fixes after spec 019: the verifier stays active until switched off; messages remember whether they were spoken.
class VerifierActiveAndSpoken < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :verifier_active, :boolean, null: false, default: false
    add_column :chat_messages, :spoken, :boolean, null: false, default: false
  end
end
