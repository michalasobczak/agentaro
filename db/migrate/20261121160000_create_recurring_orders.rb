# Spec 034: recurring work — orders that create a new epic on a schedule.
class CreateRecurringOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :space, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :kind, null: false, default: "weekly" # daily, weekly, monthly, hourly
      t.string :at_time, null: false, default: "08:00" # HH:MM, Europe/Warsaw
      t.string :weekdays                                # weekly: "1,3,5" (1 = Monday)
      t.integer :month_day                              # monthly: 1-31 (the last day in shorter months)
      t.integer :every_hours                            # hourly: at least 1
      t.date :starts_on, null: false
      t.date :ends_on
      t.string :state, null: false, default: "active"   # active, paused
      t.string :report, null: false, default: "always"  # always, attention
      t.json :last_plan                                 # G4: the steps of the last occurrence that succeeded
      t.text :last_plan_summary
      t.datetime :next_at
      t.datetime :last_occurrence_at
      t.text :note                                      # G7: why the last occurrence was skipped
      t.timestamps
    end
    add_index :recurring_orders, %i[state next_at]
    add_reference :work_items, :recurring_order, foreign_key: true
  end
end
