# Spec 010: runs of tasks on their agents' executors. A scheduled run exists at most once per occurrence.
class CreateTaskRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :agent_assigned_at, :datetime # R1: no runs for occurrences before the agent was assigned
    reversible do |dir| # tasks assigned before this migration run from now on
      dir.up { execute "UPDATE tasks SET agent_assigned_at = CURRENT_TIMESTAMP WHERE agent_id IS NOT NULL" }
    end

    create_table :task_runs do |t|
      t.references :task, null: false, foreign_key: true
      t.datetime :occurrence_start, null: false # original start of the occurrence
      t.string :trigger, null: false # scheduled | manual
      t.string :state, null: false, default: "queued" # queued | running | succeeded | failed | timed_out | skipped
      t.string :requested_by # actor label for manual runs
      t.string :agent_name   # what ran, kept even when the agent or executor is deleted (R3)
      t.string :executor_name
      t.string :preset
      t.string :model
      t.text :prompt
      t.text :output
      t.text :error
      t.integer :exit_status
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :task_runs, [ :task_id, :occurrence_start ], unique: true, where: "\"trigger\" = 'scheduled'", name: "index_task_runs_one_scheduled_per_occurrence"
    add_index :task_runs, [ :state, :created_at ]
  end
end
