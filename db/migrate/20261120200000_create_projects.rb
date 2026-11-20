# Spec 013: projects. Every work item (epic) belongs to one; existing items go to "General" (Q4).
class CreateProjects < ActiveRecord::Migration[8.1]
  def up
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :goal, null: false
      t.text :description
      t.string :state, null: false, default: "active"
      t.timestamps
    end
    add_index :projects, %i[user_id name], unique: true
    add_reference :work_items, :project, foreign_key: true

    execute <<~SQL
      INSERT INTO projects (user_id, name, goal, state, created_at, updated_at)
      SELECT DISTINCT user_id, 'General', 'Everything that does not belong to another project.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM work_items
    SQL
    execute "UPDATE work_items SET project_id = (SELECT id FROM projects WHERE projects.user_id = work_items.user_id AND projects.name = 'General')"
    change_column_null :work_items, :project_id, false
  end

  def down
    remove_reference :work_items, :project, foreign_key: true
    drop_table :projects
  end
end
