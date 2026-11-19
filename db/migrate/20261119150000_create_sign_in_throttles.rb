# Spec 005, F4: failed sign-ins are counted per typed username — whether or not the account exists —
# so a failure costs the same for known and unknown usernames (no timing difference).
class CreateSignInThrottles < ActiveRecord::Migration[8.1]
  def change
    create_table :sign_in_throttles do |t|
      t.string :username, null: false
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.timestamps
    end
    add_index :sign_in_throttles, :username, unique: true

    remove_column :users, :failed_attempts, :integer, null: false, default: 0
    remove_column :users, :locked_until, :datetime
  end
end
