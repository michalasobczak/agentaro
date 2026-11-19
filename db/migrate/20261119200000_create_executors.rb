# Spec 008: executors — AI tools reachable as a CLI on the host or a local HTTP API without a token.
# The program, its arguments and the protocol come from Executor::PRESETS in code, never from here (Q3).
class CreateExecutors < ActiveRecord::Migration[8.1]
  def change
    create_table :executors do |t|
      t.string :name, null: false
      t.string :preset, null: false
      t.boolean :enabled, null: false, default: true
      t.string :base_url # API presets only
      t.string :default_model
      t.text :notes
      t.datetime :last_checked_at
      t.boolean :last_check_ok
      t.text :last_check_output
      t.timestamps
    end
    add_index :executors, :name, unique: true
  end
end
