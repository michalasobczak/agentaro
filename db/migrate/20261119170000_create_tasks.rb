# Spec 007: calendar tasks. A recurring series is one row; occurrences are computed, never stored.
class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :user, null: false, foreign_key: true # author
      t.string :calendar, null: false, default: "private" # private | system
      t.string :title, null: false
      t.string :location
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :all_day, null: false, default: false
      t.string :repeat, null: false, default: "none" # none | daily | weekly | monthly
      t.integer :repeat_interval, null: false, default: 1
      t.string :repeat_weekdays # ISO weekdays 1 (Mon) – 7 (Sun), comma-separated, for weekly
      t.date :repeat_until
      t.integer :repeat_count
      t.timestamps
    end
    add_index :tasks, [ :calendar, :starts_at ]
    add_index :tasks, [ :user_id, :starts_at ]

    # Occurrences of a series removed or moved on their own ("this one only").
    create_table :task_exceptions do |t|
      t.references :task, null: false, foreign_key: true
      t.datetime :occurs_at, null: false # original start of the skipped occurrence
      t.timestamps
    end
    add_index :task_exceptions, [ :task_id, :occurs_at ], unique: true
  end
end
