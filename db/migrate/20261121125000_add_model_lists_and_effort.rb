# Spec 022: model lists per executor, effort, and the result of the last "Check model".
class AddModelListsAndEffort < ActiveRecord::Migration[8.1]
  def change
    change_table :executors, bulk: true do |t|
      t.json :models                 # [{ "name" => "...", "efforts" => [...] }] as the tool reported them (G1)
      t.datetime :models_listed_at
      t.text :models_note            # why the list is empty or out of date (R5)
      t.text :extra_models           # names an admin adds, one per line (G1)
      t.string :effort               # default effort (G5)
      t.datetime :model_checked_at   # G4
      t.boolean :model_check_ok
      t.text :model_check_output
    end
    change_table :agents, bulk: true do |t|
      t.string :effort
      t.datetime :model_checked_at
      t.boolean :model_check_ok
      t.text :model_check_output
    end
  end
end
