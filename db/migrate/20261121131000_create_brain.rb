# Spec 031: the brain — core blocks, temporal facts, episodes (evidence) and a keyword index over facts.
class CreateBrain < ActiveRecord::Migration[8.1]
  def change
    create_table :memory_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :scope_type, null: false # user, space, agent
      t.integer :scope_id
      t.text :content, null: false, default: ""
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_index :memory_blocks, %i[user_id scope_type scope_id], unique: true

    create_table :memory_episodes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false # user_message, director_answer, epic_done, epic_blocked, edit
      t.string :source_type
      t.integer :source_id
      t.text :excerpt, null: false
      t.datetime :occurred_at, null: false
      t.datetime :processed_at
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.string :last_error
      t.timestamps
    end
    add_index :memory_episodes, %i[user_id processed_at]
    add_index :memory_episodes, %i[source_type source_id]

    create_table :memory_facts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subject_type, null: false # user, space, agent
      t.integer :subject_id
      t.string :kind, null: false # preference, decision, fact, constraint
      t.string :statement, null: false
      t.string :status, null: false, default: "active" # proposed, active, invalid, archived
      t.string :origin, null: false, default: "extracted" # extracted, remembered, edited, imported
      t.float :confidence, null: false, default: 0.7
      t.datetime :valid_from, null: false
      t.datetime :invalid_at
      t.references :superseded_by, foreign_key: { to_table: :memory_facts }
      t.references :supersedes, foreign_key: { to_table: :memory_facts }
      t.boolean :pinned, null: false, default: false
      t.datetime :last_used_at
      t.integer :use_count, null: false, default: 0
      t.binary :embedding
      t.string :embedding_model
      t.timestamps
    end
    add_index :memory_facts, %i[user_id status subject_type subject_id]

    create_table :memory_fact_sources do |t|
      t.references :memory_fact, null: false, foreign_key: true
      t.references :memory_episode, null: false, foreign_key: true
    end
    add_index :memory_fact_sources, %i[memory_fact_id memory_episode_id], unique: true

    create_virtual_table :memory_facts_fts, :fts5, [ "statement", "tokenize='unicode61 remove_diacritics 2'" ]
  end
end
