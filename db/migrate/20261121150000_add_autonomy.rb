# Spec 033: the autonomy slider. A level for the owner (default 2, "Ważne pytaj") and an optional one per space;
# decisions and assumptions of plans and steps; plans waiting for approval at level 1; clarifying rounds.
class AddAutonomy < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :autonomy_level, :integer, default: 2, null: false
    add_column :spaces, :autonomy_level, :integer
    add_column :work_items, :awaiting_approval, :boolean, default: false, null: false
    add_column :work_items, :clarifications, :integer, default: 0, null: false

    create_table :step_decisions do |t|
      t.references :work_item, null: false, foreign_key: true
      t.references :epic_step, foreign_key: true # nil: an assumption of the plan
      t.references :task_run, foreign_key: true  # the run that asked or assumed
      t.string :status, null: false, default: "pending" # pending, answered
      t.string :answered_by # owner, assumption
      t.text :question
      t.json :options
      t.text :recommended
      t.text :why
      t.boolean :important, null: false, default: false
      t.boolean :always_ask, null: false, default: false
      t.text :answer
      t.text :correction
      t.datetime :corrected_at
      t.timestamps
    end
    add_index :step_decisions, %i[work_item_id status]
  end
end
