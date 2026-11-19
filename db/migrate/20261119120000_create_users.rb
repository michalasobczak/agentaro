class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :password_digest
      t.string :role, null: false, default: "user"
      t.string :otp_secret
      t.boolean :otp_required, null: false, default: false
      t.datetime :otp_last_used_at
      t.boolean :active, null: false, default: true
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.datetime :password_changed_at
      t.timestamps
    end
    add_index :users, :username, unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.boolean :otp_verified, null: false, default: false
      t.datetime :last_seen_at
      t.timestamps
    end

    create_table :password_links do |t|
      t.references :user, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :password_links, :token_digest, unique: true
  end
end
