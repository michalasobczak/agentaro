# Spec 014: projects become spaces of two kinds — project (with a goal) and team (no goal). "General" becomes a
# team space (Q4).
class ProjectsToSpaces < ActiveRecord::Migration[8.1]
  def up
    rename_table :projects, :spaces
    add_column :spaces, :kind, :string, null: false, default: "project"
    change_column_null :spaces, :goal, true
    rename_column :work_items, :project_id, :space_id
    execute "UPDATE spaces SET kind = 'team', goal = NULL WHERE name = 'General'"
  end

  def down
    execute "UPDATE spaces SET goal = 'Everything that does not belong to another project.' WHERE goal IS NULL"
    rename_column :work_items, :space_id, :project_id
    change_column_null :spaces, :goal, false
    remove_column :spaces, :kind
    rename_table :spaces, :projects
  end
end
