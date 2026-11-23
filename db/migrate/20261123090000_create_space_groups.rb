# Spec 051: the owner's groups of spaces and the order of groups and of spaces within them.
class CreateSpaceGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :space_groups do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_reference :spaces, :space_group, foreign_key: { on_delete: :nullify }
    add_column :spaces, :position, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do # existing spaces keep their name order (R2)
        select_rows("SELECT DISTINCT user_id FROM spaces").each do |(user_id)|
          select_rows("SELECT id FROM spaces WHERE user_id = #{user_id.to_i} ORDER BY LOWER(name)").each_with_index do |(id), i|
            execute("UPDATE spaces SET position = #{i + 1} WHERE id = #{id.to_i}")
          end
        end
      end
    end
  end
end
