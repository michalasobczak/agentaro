# Spec 016: an epic has a start time; its steps are an ordered list without times, run one after another.
class CreateEpicSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :epic_steps do |t|
      t.references :work_item, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.text :description
      t.references :agent, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.timestamps
    end
    add_index :epic_steps, %i[work_item_id position], unique: true

    rename_column :work_items, :handle_from, :starts_at
    add_column :work_items, :started_at, :datetime
    add_column :work_items, :finished_at, :datetime
    add_reference :task_runs, :epic_step, foreign_key: true
  end
end
