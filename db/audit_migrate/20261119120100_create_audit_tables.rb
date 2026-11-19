class CreateAuditTables < ActiveRecord::Migration[8.1]
  def change
    # Spec 003: one row per HTTP request, hash-chained.
    create_table :audit_events do |t|
      t.datetime :occurred_at, null: false
      t.string :request_id, null: false
      t.integer :user_id
      t.string :username
      t.integer :session_id
      t.string :remote_addr
      t.string :forwarded_for
      t.string :user_agent
      t.string :http_method, null: false
      t.string :host
      t.string :path, null: false
      t.text :query
      t.text :body
      t.integer :status
      t.float :duration_ms
      t.string :prev_hash, null: false
      t.string :row_hash, null: false
    end
    add_index :audit_events, :occurred_at
    add_index :audit_events, :request_id
    add_index :audit_events, :user_id

    # Spec 004: one row per data change, hash-chained.
    create_table :data_changes do |t|
      t.datetime :occurred_at, null: false
      t.string :request_id
      t.string :actor, null: false
      t.string :record_type, null: false
      t.integer :record_id, null: false
      t.string :action, null: false
      t.text :changeset, null: false
      t.string :prev_hash, null: false
      t.string :row_hash, null: false
    end
    add_index :data_changes, :occurred_at
    add_index :data_changes, [ :record_type, :record_id ]
    add_index :data_changes, :request_id

    # Chain anchors: the hash the oldest remaining row must follow after pruning.
    create_table :chain_anchors do |t|
      t.string :chain, null: false
      t.string :anchor_hash, null: false
      t.datetime :pruned_before
      t.timestamps
    end
    add_index :chain_anchors, :chain, unique: true
  end
end
