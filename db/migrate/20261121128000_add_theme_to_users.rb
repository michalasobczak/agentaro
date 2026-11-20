# Owner fix ("potrzebuję też dark mode"): the colour theme chosen by the user — auto (the system's), light or dark.
class AddThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :theme, :string, default: "auto", null: false
  end
end
