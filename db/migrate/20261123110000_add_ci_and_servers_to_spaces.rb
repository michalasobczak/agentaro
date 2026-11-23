# Spec 052: the CI state and the server of a space; a CI run belongs to its space.
class AddCiAndServersToSpaces < ActiveRecord::Migration[8.1]
  def change
    change_table :spaces, bulk: true do |t|
      t.string :ci_state                  # nil (never), queued, running, ok, failed_build, failed_test, error
      t.datetime :ci_finished_at
      t.string :ci_fingerprint             # the folder as the last CI saw it (spec 052, R2)
      t.text :ci_log                       # the end of the last CI run's log
      t.boolean :server_wanted, null: false, default: false
      t.string :server_state, null: false, default: "stopped" # stopped, starting, up, down
      t.integer :server_pid
      t.string :server_process_started     # ps lstart of the process, so a reused pid is never taken for it
      t.datetime :server_started_at
      t.datetime :server_checked_at
      t.string :server_note
      t.text :server_restarts              # JSON list of times it was started again by itself (G4)
    end
    add_reference :task_runs, :space, foreign_key: true
  end
end
