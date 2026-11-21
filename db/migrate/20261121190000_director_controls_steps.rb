# Spec 040: each step's time limit (G2), and the director's reviews of steps — after a failed attempt (G1) or while
# a step runs (G4) — with the decision, its reason and what it changed.
class DirectorControlsSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :epic_steps, :time_limit_minutes, :integer

    create_table :step_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :work_item, null: false, foreign_key: true
      t.references :epic_step, null: false, foreign_key: true
      t.references :task_run, foreign_key: true # the attempt reviewed
      t.references :review_run, foreign_key: { to_table: :task_runs } # the director's run
      t.references :step_decision, foreign_key: true # when the decision was put to the owner
      t.string :kind, null: false # failure, running
      t.string :status, null: false, default: "pending" # pending, asked, decided, failed
      t.string :decision # retry, change, replan, ask, stop, kill, none
      t.text :reason
      t.datetime :retry_at
      t.integer :time_limit_minutes
      t.text :previous_description
      t.json :proposal
      t.json :stopped
      t.timestamps
    end
    add_index :step_reviews, %i[epic_step_id kind created_at]
  end
end
