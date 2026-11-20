# Spec 011: director chat, work list, team of director / managers / members, and management runs.
class CreateManagement < ActiveRecord::Migration[8.1]
  def change
    create_table :team_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.string :role, null: false # director | manager | member
      t.references :parent, foreign_key: { to_table: :team_roles } # a member's manager role
      t.string :role_text # what a member does, read by its manager
      t.timestamps
    end
    add_index :team_roles, [ :user_id, :role, :parent_id, :agent_id ], unique: true, name: "index_team_roles_unique"

    create_table :work_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.datetime :handle_from
      t.date :due_on
      t.string :priority, null: false, default: "normal" # normal | high
      t.integer :position, null: false, default: 0
      t.string :state, null: false, default: "new" # new | with_manager | planned | done | cancelled | blocked
      t.references :manager_agent, foreign_key: { to_table: :agents }
      t.text :director_note
      t.text :proposed_plan # JSON of the manager's latest valid plan, until the director decides
      t.text :plan_summary
      t.text :review_comment # the director's latest rejection, for the manager
      t.integer :replan_count, null: false, default: 0
      t.text :blocked_reason
      t.timestamps
    end
    add_index :work_items, [ :user_id, :state ]

    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true # whose conversation
      t.string :author, null: false # user | director | system
      t.text :content, null: false
      t.text :actions_summary # what Agentaro applied from the director's answer
      t.references :task_run, foreign_key: true
      t.timestamps
    end

    add_reference :tasks, :work_item, foreign_key: true

    change_column_null :task_runs, :task_id, true # management runs have no calendar task
    add_column :task_runs, :purpose, :string, null: false, default: "step" # step | chat | director | manager | review
    add_reference :task_runs, :user, foreign_key: true # owner of management runs
    add_reference :task_runs, :work_item, foreign_key: true
    add_reference :task_runs, :agent, foreign_key: true # agent of management runs
  end
end
