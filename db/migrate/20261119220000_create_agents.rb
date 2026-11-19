# Spec 009: agents — a master prompt and an executor; private to a user or shared by admins.
class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.references :user, null: false, foreign_key: true # author; owner of a private agent
      t.string :kind, null: false, default: "private" # private | shared
      t.string :name, null: false
      t.string :description
      t.text :master_prompt, null: false
      t.references :executor, null: false, foreign_key: true
      t.string :model
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :agents, [ :kind, :user_id, :name ]

    add_reference :tasks, :agent, foreign_key: true # optional
  end
end
