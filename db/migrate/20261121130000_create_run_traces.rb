# Spec 030: every model call as a structured trace — prompt parts stored once by digest, the answer, tool events,
# tokens, cost and time, linked to its run (and through it to the user, epic, step, agent and chat message).
class CreateRunTraces < ActiveRecord::Migration[8.1]
  def change
    create_table :trace_parts do |t|
      t.string :digest, null: false
      t.text :content, null: false
      t.integer :bytes, null: false
      t.timestamps
    end
    add_index :trace_parts, :digest, unique: true

    create_table :model_calls do |t|
      t.references :task_run, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :position, null: false
      t.string :pass, null: false
      t.string :layout, null: false, default: "agent"
      t.integer :agent_id
      t.string :agent_name
      t.string :preset
      t.string :model
      t.string :effort
      t.string :state
      t.datetime :started_at
      t.integer :duration_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.float :cost_usd
      t.integer :turns
      t.string :joiner, null: false, default: "\n\n"
      t.references :output_part, foreign_key: { to_table: :trace_parts }
      t.text :error
      t.boolean :redacted, null: false, default: false
      t.binary :events
      t.string :events_format
      t.integer :events_count, null: false, default: 0
      t.boolean :events_cut, null: false, default: false
      t.timestamps
    end
    add_index :model_calls, %i[task_run_id position], unique: true
    add_index :model_calls, %i[user_id created_at]

    create_table :model_call_parts do |t|
      t.references :model_call, null: false, foreign_key: true
      t.references :trace_part, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :section, null: false
      t.string :kind, null: false
    end
    add_index :model_call_parts, %i[model_call_id position], unique: true
  end
end
