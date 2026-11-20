# Spec 012: managers removed — the director plans for its members (Q1 migration).
class RemoveManagers < ActiveRecord::Migration[8.1]
  def up
    # Members move directly under the director; an agent in two managers' teams stays once (first role text).
    execute <<~SQL
      DELETE FROM team_roles WHERE role = 'member' AND id NOT IN (
        SELECT MIN(id) FROM team_roles WHERE role = 'member' GROUP BY user_id, agent_id)
    SQL
    execute "UPDATE team_roles SET parent_id = NULL WHERE role = 'member'"
    execute "DELETE FROM team_roles WHERE role = 'manager'"
    # Open items with a manager are planned again by the director; queued manager and review runs are skipped.
    execute "UPDATE work_items SET state = 'new' WHERE state = 'with_manager'"
    execute <<~SQL
      UPDATE task_runs SET state = 'skipped', error = 'Managers were removed (spec 012).', finished_at = CURRENT_TIMESTAMP
      WHERE purpose IN ('manager', 'review') AND state = 'queued'
    SQL

    remove_index :team_roles, name: "index_team_roles_unique"
    remove_index :team_roles, :parent_id
    remove_column :team_roles, :parent_id, :integer
    add_index :team_roles, %i[user_id role agent_id], unique: true, name: "index_team_roles_unique"
    remove_column :work_items, :manager_agent_id, :integer
    remove_column :work_items, :director_note, :text
    remove_column :work_items, :review_comment, :text
    remove_column :work_items, :proposed_plan, :text
    remove_column :work_items, :replan_count, :integer, default: 0, null: false
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "managers were removed (spec 012); restore from a backup"
  end
end
